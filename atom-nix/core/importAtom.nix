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
  flakeCompatFn = import (import ../npins).flake-compat;

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
      fetcher = nix.fetcher or "native";
      # TODO native doesn't exist yet
      throwMissingNativeFetcher = abort "Native fetcher isn't implemented yet";
      throwNonExistingFetcher = abort "A `${backend}` fetcher does not exist";
      fetcherConfig = config.fetcher or { };
      npinRoot = fetcherConfig.npin.root or "npins";
      pins = import (dirOf path + "/${npinRoot}");

      impliedSrc =
        let
          file = mod.parse (baseNameOf path);
          len = l.stringLength file.name;
        in
        l.substring 0 (len - 1) file.name;

      src = l.seq id (atom.src or impliedSrc);

      mkExtern =
        depName: depConfig:
        let
          name = depConfig.name or depName;
          depIsImport = depConfig.import or false;
          depIsFlake = depConfig.flake or false;
          depIsLocal = depConfig.local or false;
          # Dependency is an atom by default
          depIsAtom = depConfig.atom or true;
          inputOverrides = depConfig.inputOverrides or [ ];
          depHasInputOverrides = inputOverrides != [ ];

          depIsOptional = depConfig.optional or false;
          featureIsEnabled = l.elem depName features;
          depIsEnabled = !depIsOptional || (depIsOptional && featureIsEnabled);

          depArgs = depConfig.args or [ ];
          depHasArgs = depArgs != [ ];

          # TODO how to handle features?
          mkAtom =
            srcRoot:
            let
              manifestFileName = "${name}@.toml";
              manifest = "${srcRoot}/${manifestFileName}";
            in
            importAtom { inherit system; } manifest;

          npinsDependency =
            let
              npinsSrc = "${pins.${name}}/${depConfig.subdir or ""}";

              applyNextArg =
                appliedFunction: nextArgument:
                let
                  argsFromDeps = depConfig.argsFromDeps or true && l.isAttrs nextArgument;
                  intersectedArgument = nextArgument // (l.intersectAttrs nextArgument extern);
                in
                if argsFromDeps then appliedFunction intersectedArgument else appliedFunction nextArgument;

              importedSrcWithArgs = l.foldl' applyNextArg (import npinsSrc) depArgs;

              importedSrc = if depHasArgs then importedSrcWithArgs else import npinsSrc;

              importedFlakeDep =
                assert (!depIsImport) || abort "Dependency ${depName} cannot enable both `flake` and `import`";
                let
                  flakeCompatResult = flakeCompatFn {
                    src = npinsSrc;
                    inherit system;
                  };
                  mkOverrideNV =
                    name:
                    let
                      missingInputError = abort "Manifest is missing input override `${name}`";
                      value = pins.${name};
                      result = { inherit name value; };
                    in
                    assert l.hasAttr name pins || missingInputError;
                    result;
                  overridesList = l.map mkOverrideNV inputOverrides;
                  overrides = l.listToAttrs overridesList;
                  resultWithoutOverrides = flakeCompatResult.defaultNix;
                  resultWithInputOverrides = resultWithoutOverrides.overrideInputs overrides;
                in
                if depHasInputOverrides then resultWithInputOverrides else resultWithoutOverrides;

              importedAtom = mkAtom npinsSrc;

            in
            if depIsFlake then
              importedFlakeDep
            else if depIsImport then
              importedSrc
            else if depIsAtom then
              importedAtom
            else
              npinsSrc;

          fetchedDependency =
            if fetcher == "npins" then
              npinsDependency
            else if fetcher == "native" then
              throwMissingNativeFetcher
            else
              throwNonExistingFetcher;

          localDependency = mkAtom root;

          dependency = if depIsLocal then localDependency else fetchedDependency;

        in
        if depIsEnabled then { "${depName}" = dependency; } else null;

      extern = mod.filterMap mkExtern config.fetch or { };

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
