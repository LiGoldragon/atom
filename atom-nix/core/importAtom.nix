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
  mod ? (import ./mod.nix),
  flakeCompatFn ? (import (import ../npins).flake-compat),
  flakeInputsFn ? (import (import ../npins).flake-inputs),
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
  fetch = config.fetch or { };

  propagate = importAtomArgs.propagate || atom.propagate or false;

  features =
    let
      atomFeatures = importAtomArgs.features or null;
      featSet = config.features or { };
      default = featSet.default or [ ];
      argsHaveNoFeatures = atomFeatures == null;
      featIn = if argsHaveNoFeatures then default else atomFeatures;
    in
    mod.features.resolve featSet featIn;

  impliedSrc =
    let
      file = mod.parse (baseNameOf path);
      len = l.stringLength file.name;
    in
    l.substring 0 (len - 1) file.name;

  src = l.seq id (atom.src or impliedSrc);

  backend = config.backend or { };
  nix = backend.nix or { };
  fetcher = nix.fetcher or "native";
  fetcherConfig = config.fetcher or { };

  # TODO native doesn't exist yet
  throwMissingNativeFetcher = abort "Native fetcher isn't implemented yet";
  throwNonExistingFetcher = abort "A `${backend}` fetcher does not exist";

  npinRoot = fetcherConfig.npin.root or "npins";
  rawNpins = import (root + "/${npinRoot}");
  npinsInputs = rawNpins // (importAtomArgs.inputs or { });

  flakeLock = flakeInputsFn { inherit root; };
  flakeLockInputs = flakeLock // importAtomArgs.inputs;

  inputs =
    let
      inputsIndex = {
        npins = npinsInputs;
        flake-lock = flakeLockInputs;
        native = throwMissingNativeFetcher;
      };
    in
    inputsIndex.${fetcher} or throwNonExistingFetcher;

  mkInput = name: inputs.${name} or abort "Missing Input for: `${name}`";

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
      overrideInputs = l.getAttrs overrides inputs;
      optionalOverrides = if depHasInputOverrides then overrideInputs else { };
      optionalInputs = if propagate then inputs else optionalOverrides;
      args = {
        inputs = optionalInputs;
        inherit
          system
          importAtom
          mod
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

      overrides = l.getAttrs inputOverrides inputs;
      resultWithoutOverrides = flakeCompatResult.defaultNix;
      resultWithInputOverrides = resultWithoutOverrides.overrideInputs overrides;

      inputIsFlake = input._type == "flake";
      possiblyRawFlake = if inputIsFlake then input else flakeCompatFlake;
      flakeCompatFlake =
        if depHasInputOverrides then resultWithInputOverrides else resultWithoutOverrides;

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
          argsFromDeps = depConfig.argsFromDeps or true && l.isAttrs nextArgument;
          intersectedArgument = nextArgument // (l.intersectAttrs nextArgument extern);
        in
        if argsFromDeps then appliedFunction intersectedArgument else appliedFunction nextArgument;

      importedSrcWithArgs = l.foldl' applyNextArg (import rawSrc) depArgs;

    in
    if depHasArgs then importedSrcWithArgs else import rawSrc;

  mkSrc = depName: depConfig: mkInput (depConfig.name or depName);

  mkExtern =
    depName: depConfig:
    let
      type = depConfig.type or "atom";
      depIsOptional = depConfig.optional or false;
      featureIsEnabled = l.elem depName features;
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

  extern = mod.filterMap mkExtern fetch;

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
}
