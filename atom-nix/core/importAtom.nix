/**
  # `importAtom`

  > #### ⚠️ Warning ⚠️
  >
  > `importAtoms` current implementation should be reduced close to:
  > ```nix
  >   compose <| std.fromJSON
  > ```

  In other words, compose should receive a dynamically generated json from the CLI.

  If nix-lang gets some sort of native (and performant!) schema validation such as:
  [nixos/nix#5403](https://github.com/NixOS/nix/pull/5403) in the future, we can look at
  revalidating on the Nix side as an extra precaution, but initially, we just assume we have a
  valid input (and the CLI should type check on it's end)
*/
let
  mod = import ./mod.nix;

  importAtom =
    importAtomArgs@{
      system ? null,
      features ? null,
      __internal__test ? false,
    }:
    path':
    let
      l = builtins;
      path = mod.prepDir path';
      root = mod.prepDir (dirOf path); # TODO Is prepDir required twice?

      file = l.readFile path;
      config = l.fromTOML file;
      atom = config.atom or { };
      id = l.seq version (atom.id or (mod.errors.missingAtom path' "id"));
      version = atom.version or (mod.errors.missingAtom path' "version");
      core = config.core or { };
      std = config.std or { };
      meta = atom.meta or { };

      features =
        let
          atomFeatures = importAtomArgs.features or null;
          featSet = config.features or { };
          default = featSet.default or [ ];
          argsHaveNoFeatures = atomFeatures == null;
          featIn = if argsHaveNoFeatures then default else atomFeatures;
        in
        mod.features.resolve featSet featIn;

      backend = config.backend or { };
      nix = backend.nix or { };

      impliedSrc =
        let
          file = mod.parse (baseNameOf path);
          len = l.stringLength file.name;
        in
        l.substring 0 (len - 1) file.name;

      src = l.seq id (atom.src or impliedSrc);

      extern =
        let
          # TODO native doesn't exist yet
          fetcher = nix.fetcher or "native";
          throwMissingNativeFetcher = abort "Native fetcher isn't implemented yet";

          fetcherConfig = config.fetcher or { };
          npinRoot = fetcherConfig.npin.root or "npins";
          pins = import (dirOf path + "/${npinRoot}");

          local = config.local or { };

          isDepEnabled =
            depName: depConfig:
            let
              optional = depConfig.optional or false;
              featureIsEnabled = l.elem depName features;
            in
            (optional && featureIsEnabled) || (!optional);

          obtainLocalDep =
            depName: depConfig:
            let
              depManifest = "${root}/${depConfig.path}";
              depIsEnabled = isDepEnabled depName depConfig;
              dependency = importAtom { inherit system; } depManifest;
            in
            if depIsEnabled then { "${depName}" = dependency; } else null;

          obtainedLocalDeps = mod.filterMap obtainLocalDep local;

          localDeps = if local != { } then obtainedLocalDeps else { };

          fetchEnabledNpinsDep =
            depName: depConfig:
            let
              depIsImport = depConfig.import or false;
              depIsFlake = depConfig.flake or false;
              inputOverrides = depConfig.inputOverrides or [ ];
              depHasInputOverrides = inputOverrides != [ ];
              depArgs = depConfig.args or [ ];
              depHasArgs = depArgs != [ ];
              depIsEnabled = isDepEnabled depName depConfig;

              npinSrc = "${pins.${depConfig.name or depName}}/${depConfig.subdir or ""}";

              applyArguments =
                appliedFunction: nextArgument:
                let
                  argsFromDeps = depConfig.argsFromDeps or true && l.isAttrs nextArgument;
                  argIntersectedwithDeps = nextArgument // (l.intersectAttrs nextArgument extern);
                in
                if argsFromDeps nextArgument then
                  appliedFunction argIntersectedwithDeps
                else
                  appliedFunction nextArgument;

              importedSrcWithArgs = l.foldl' applyArguments (import npinSrc) depArgs;

              importedSrc = if depHasArgs then importedSrcWithArgs else import npinSrc;

              flakeCompatFn = import (import ../npins).flake-compat;

              importedFlakeDep =
                let
                  flakeCompatResult = flakeCompatFn {
                    src = npinSrc;
                    inherit system;
                  };
                  mkOverrideNV =
                    name:
                    let
                      missingInputError = abort "Manifest is missing input override `${name}`";
                      value = pins.${name};
                    in
                    assert l.hasAttr name pins || missingInputError;
                    {
                      inherit name value;
                    };
                  overridesList = l.map mkOverrideNV inputOverrides;
                  overrides = l.listToAttrs overridesList;
                  resultWithoutOverrides = flakeCompatResult.defaultNix;
                  resultWithInputOverrides = resultWithoutOverrides.overrideInputs overrides;
                  result = if depHasInputOverrides then resultWithInputOverrides else resultWithoutOverrides;
                in
                result;

              dependency =
                if depIsImport then
                  importedSrc
                else if depIsFlake then
                  importedFlakeDep
                else
                  npinSrc;
            in
            if depIsEnabled then { "${depName}" = dependency; } else null;

          npinsDeps = mod.filterMap fetchEnabledNpinsDep config.fetch or { };

          externalDeps =
            if fetcher == "npins" then
              npinsDeps
            else if fetcher == "native" then
              throwMissingNativeFetcher
            else
              { };

        in
        localDeps // externalDeps;

    in
    mod.compose {
      inherit
        src
        root
        config
        system
        extern
        features
        __internal__test
        ;
      coreFeatures =
        let
          feat = core.features or mod.coreToml.features.default;
        in
        mod.features.resolve mod.coreToml.features feat;
      stdFeatures =
        let
          feat = std.features or mod.stdToml.features.default;
        in
        mod.features.resolve mod.stdToml.features feat;

      __isStd__ = meta.__is_std__ or false;
    };

in
importAtom
