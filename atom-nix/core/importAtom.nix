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
importAtomArgs@{
  features ? null,
  __internal__test ? false,
}:
path':
let
  core = import ./mod.nix;

  path = core.prepDir path';

  file = builtins.readFile path;
  config = builtins.fromTOML file;
  atom = config.atom or { };

  # Here, `seq` ensures that `version` is set
  id = builtins.seq version (atom.id or (core.errors.missingAtom path' "id"));
  version = atom.version or (core.errors.missingAtom path' "version");

  coreConfig = config.core or { };
  std = config.std or { };

  features =
    let
      atomFeatures = importAtomArgs.features or null;
      featSet = config.features or { };
      default = featSet.default or [ ];
      argsHaveNoFeatures = atomFeatures == null;
      featIn = if argsHaveNoFeatures then default else atomFeatures;
    in
    core.features.resolve featSet featIn;

  backend = config.backend or { };
  nix = backend.nix or { };

  root = core.prepDir (dirOf path);

  src =
    let
      file = core.parse (baseNameOf path);
      len = builtins.stringLength file.name;
      impliedSrc = builtins.substring 0 (len - 1) file.name;
    in
    # Here, `seq` ensures that `id` is set
    builtins.seq id (atom.src or impliedSrc);

  extern =
    let
      fetcher = nix.fetcher or "native"; # native doesn't exist yet
      throwMissingNativeFetcher = abort "Native fetcher isn't implemented yet";

      fetcherConfig = config.fetcher or { };
      npinRoot = fetcherConfig.npin.root or "npins";
      rawNpins = import (dirOf path + "/${npinRoot}");

      fetchEnabledNpinsDep =
        depName: depConfig:
        let
          depIsEnabled =
            (depConfig.optional or false && builtins.elem depName features) || (!depConfig.optional or false);

          npinSrc = "${rawNpins.${depConfig.name or depName}}/${depConfig.subdir or ""}";

          applyArguments =
            appliedFunction: nextArgument:
            let
              argsFromDeps = depConfig.argsFromDeps or true && builtins.isAttrs nextArgument;
              argIntersectedwithDeps = nextArgument // (builtins.intersectAttrs nextArgument extern);
            in
            if argsFromDeps nextArgument then
              appliedFunction argIntersectedwithDeps
            else
              appliedFunction nextArgument;

          dependency =
            if depConfig.import or false then
              if depConfig.args or [ ] != [ ] then
                builtins.foldl' applyArguments (import npinSrc) depConfig.args
              else
                import npinSrc
            else
              npinSrc;
        in
        if depIsEnabled then { "${depName}" = dependency; } else null;

      npinsDeps = core.filterMap fetchEnabledNpinsDep config.fetch or { };

    in
    if fetcher == "npins" then
      npinsDeps
    else if fetcher == "native" then
      throwMissingNativeFetcher
    else
      { };

  meta = atom.meta or { };

in
core.compose {
  inherit
    extern
    __internal__test
    config
    root
    src
    features
    ;
  coreFeatures =
    let
      feat = coreConfig.features or core.coreToml.features.default;
    in
    core.features.resolve core.coreToml.features feat;
  stdFeatures =
    let
      feat = std.features or core.stdToml.features.default;
    in
    core.features.resolve core.stdToml.features feat;

  __isStd__ = meta.__is_std__ or false;
}
