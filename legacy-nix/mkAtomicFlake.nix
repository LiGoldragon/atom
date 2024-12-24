{
  manifest,
  noSystemManifest ? null,
  systems ? [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ],
}:

let
  npinsSrcs = import ../src/npins;
  lib = import (npinsSrcs."nixpkgs.lib" + "/lib");
  l = lib // builtins;

  importAtom = import ../src/core/importAtom.nix;

  noSystemAtom = importAtom { } noSystemManifest;

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
      evaluatedAtom = importAtom { inherit system; } manifest;
      mkPerSystemValue = _: value: { ${system} = value; };
    in
    l.mapAttrs mkPerSystemValue evaluatedAtom;

  accumulate = accumulator: set: accumulator // set;
  combineSets = _: sets: l.foldl' accumulate { } sets;

  transformedAtoms = l.map transformedAtomFromSystem systems;

  combinedPerSystemAttributes = l.zipAttrsWith combineSets transformedAtoms;

in
optionalNoSystemAtom // combinedPerSystemAttributes
