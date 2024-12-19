{
  manifest,
  noSystemManifest ? null,
  perSystemNames ? [
    "checks"
    "packages"
    "apps"
    "formatter"
    "devShells"
    "hydraJobs"
  ],
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

  noSystemAtom = importAtom { sytem = null; } noSystemManifest;
  hasNoSystemAtom = noSystemManifest != null;
  optionalNoSystemAtom = if hasNoSystemAtom then noSystemAtom else { };

  transformedAtomFromSystem =
    system:
    let
      evaluatedAtom = importAtom { inherit system; } manifest;
      perSystemAtomAttributes = l.getAttrs perSystemNames evaluatedAtom;
      mkPerSystemValue = _: value: { ${system} = value; };
    in
    l.mapAttrs mkPerSystemValue perSystemAtomAttributes;

  accumulate = accumulator: set: accumulator // set;
  combineSets = _: sets: l.foldl' accumulate { } sets;

  transformedAtoms = l.map transformedAtomFromSystem systems;

  combinedPerSystemAttributes = l.zipAttrsWith combineSets transformedAtoms;

in
optionalNoSystemAtom // combinedPerSystemAttributes
