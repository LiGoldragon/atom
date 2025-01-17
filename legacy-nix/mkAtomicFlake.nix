flake:
let
  l = builtins;
  mkCustomAtomicFlake = import ./mkCustomAtomicFlake.nix;

  flakeRootDir = l.readDir flake.outPath;
  flakeRootFiles = l.attrNames flakeRootDir;

  matchManifestFile = string: std.match "(^.*@\.toml)" string;

  mkFileMatch =
    name:
    let
      match = matchManifestFile name;
    in
    if (match != null) then match else [ ];

  matchedFileNames = concatMap mkFileMatch flakeRootFiles;

in
mkCustomAtomicFlake {
  inherit manifest noSystemManifest inputs;
}
