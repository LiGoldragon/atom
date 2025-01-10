{
  manifest,
  noSystemManifest ? null,
  inputs ? { },
  propagateInputs ? false,
  features ? null,
  systems ? [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ],
}:

let
  npinsSrcs = import ../atom-nix/npins;
  lib = import (npinsSrcs."nixpkgs.lib" + "/lib");
  l = lib // builtins;

  importAtom = import ../atom-nix/core/importAtom.nix;

  mkNoSystemAtom = importAtom {
    inherit inputs propagateInputs features;
    _calledFromFlake = true;
  };

  noSystemAtom = mkNoSystemAtom noSystemManifest;

  verifySystemFeature =
    atomManifest:
    let
      atomConfig = l.fromTOML (l.readFile atomManifest);
      features = atomConfig.features.default or [ ];
    in
    l.elem "system" features;

  systemEnabledError = abort "No-System atom has `system` feature enabled";

  hasNoSystemAtom =
    assert !(verifySystemFeature noSystemManifest) || systemEnabledError;
    noSystemManifest != null;

  optionalNoSystemAtom =
    if (noSystemManifest == null) then
      { }
    else if hasNoSystemAtom then
      noSystemAtom
    else
      { };

  transformedAtomFromSystem =
    system:
    let
      mkAtom = importAtom {
        inherit inputs propagateInputs features;
        _calledFromFlake = true;
      };
      evaluatedAtom = mkAtom manifest;
      mkPerSystemValue = _: value: { ${system} = value; };
    in
    l.mapAttrs mkPerSystemValue evaluatedAtom;

  accumulate = accumulator: set: accumulator // set;
  combineSets = _: sets: l.foldl' accumulate { } sets;

  transformedAtoms = l.map transformedAtomFromSystem systems;

  combinedPerSystemAttributes = l.zipAttrsWith combineSets transformedAtoms;

in
optionalNoSystemAtom // combinedPerSystemAttributes
