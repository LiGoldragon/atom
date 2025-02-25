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
  system ? null,
  features ? null,
  inputs ? { },
  propagate ? false,
  _calledFromFlake ? false,
  __internal__test ? false,
  # Passed to further `importAtom`s
  importAtom ? (import ./importAtom.nix),
  core ? (import ./mod.nix),
  flakeCompatFn ? (import (import ../npins).flake-compat),
  flakeInputsFn ? (import (import ../npins).flake-inputs),
}:
path':
let
  path = core.prepDir path';

  file = builtins.readFile path;
  config = builtins.fromTOML file;
  atom = config.atom or { };

  # Here, `seq` ensures that `version` is set
  id = builtins.seq version (atom.id or (core.errors.missingAtom path' "id"));
  version = atom.version or (core.errors.missingAtom path' "version");

  coreConfig = config.core or { };
  std = config.std or { };
  fetch = config.fetch or { };

  propagate = importAtomArgs.propagate or false || atom.propagate or false;

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

  extern = core.filterMap mkExtern fetch;

  mkExtern =
    depName: depConfig:
    let
      type = depConfig.type or "atom";
      depIsOptional = depConfig.optional or false;
      featureIsEnabled = builtins.elem depName features;
      depIsEnabled = !depIsOptional || (depIsOptional && featureIsEnabled);
      typeError = abort "Dependency `${depName}` declares type `${type}` which does not exist";

      makeIndex = {
        atom = mkAtom;
        flake = mkFlake;
        import = mkImport;
        lib = mkImport;
        local = mkAtom;
        src = mkSrc;
      };

      dependency = (makeIndex.${type} or typeError) depName depConfig;

    in
    if depIsEnabled then { "${depName}" = dependency; } else null;

  fetcher = nix.fetcher or "native";
  fetcherConfig = config.fetcher or { };

  # TODO native doesn't exist yet
  throwMissingNativeFetcher = abort "Native fetcher isn't implemented yet";
  throwNonExistingFetcher = abort "A `${backend}` fetcher does not exist";

  npinRoot = fetcherConfig.npin.root or "npins";
  rawNpins = import (root + "/${npinRoot}");
  npinsInputs = rawNpins // (importAtomArgs.inputs or { });

  flakeLock = flakeInputsFn { inherit root; };
  flakeLockAndInputs = flakeLock // importAtomArgs.inputs;

  # Nix flakes already have their inputs
  flakeLockInputs = if _calledFromFlake then importAtomArgs.inputs else flakeLockAndInputs;

  inputs =
    let
      inputsIndex = {
        npins = npinsInputs;
        flake-lock = flakeLockInputs;
        native = throwMissingNativeFetcher;
      };
    in
    inputsIndex.${fetcher} or throwNonExistingFetcher;

  mkInput = name: inputs.${name};

  # TODO how to handle features?
  mkAtom =
    depName: depConfig:
    let
      name = depConfig.name or depName;
      type = depConfig.type or "atom";
      srcRoot = if type == "local" then root else inputs.${name};
      # TODO this will obviously evolve
      manifestFileName = "${name}@.toml";
      manifest = "${srcRoot}/${manifestFileName}";
      overrides = depConfig.inputOverrides or [ ];
      depHasInputOverrides = overrides != [ ];
      overrideInputs = builtins.getAttrs overrides inputs;
      optionalOverrides = if depHasInputOverrides then overrideInputs else { };
      optionalInputs = if propagate then inputs else optionalOverrides;
      args = {
        inputs = optionalInputs;
        inherit
          system
          importAtom
          core
          flakeCompatFn
          flakeInputsFn
          propagate
          ;
      };
    in
    importAtom args manifest;

  mkFlake =
    depName: depConfig:
    let
      name = depConfig.name or depName;
      inputOverrides = depConfig.inputOverrides or [ ];
      depHasInputOverrides = inputOverrides != [ ];
      input = inputs.${name};

      flakeCompatResult = flakeCompatFn {
        src = input;
        inherit system;
      };

      overrides = builtins.getAttrs inputOverrides inputs;
      resultWithoutOverrides = flakeCompatResult.defaultNix;
      resultWithInputOverrides = resultWithoutOverrides.overrideInputs overrides;

      flakeCompatFlake =
        if depHasInputOverrides then resultWithInputOverrides else resultWithoutOverrides;

      inputIsFlake = input._type == "flake";
      possiblyRawFlake = if inputIsFlake then input else flakeCompatFlake;

    in
    if _calledFromFlake then possiblyRawFlake else flakeCompatFlake;

  mkImport =
    depName: depConfig:
    let
      name = depConfig.name or depName;
      input = inputs.${name};
      inputIsFlake = input._type == "flake";
      srcRootFromFlake = if inputIsFlake then input.outPath else input;
      rawSrcRoot = if _calledFromFlake then srcRootFromFlake else input;
      rawSrc = "${rawSrcRoot}/${depConfig.subdir or ""}";
      depArgs = depConfig.args or [ ];
      depHasArgs = depArgs != [ ];

      applyNextArg =
        appliedFunction: nextArgument:
        let
          argsFromDeps = depConfig.argsFromDeps or true && builtins.isAttrs nextArgument;
          intersectedArgument = nextArgument // (builtins.intersectAttrs nextArgument extern);
        in
        if argsFromDeps then appliedFunction intersectedArgument else appliedFunction nextArgument;

      importedSrcWithArgs = builtins.foldl' applyNextArg (import rawSrc) depArgs;

    in
    if depHasArgs then importedSrcWithArgs else import rawSrc;

  mkSrc = depName: depConfig: mkInput (depConfig.name or depName);

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
    system
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
