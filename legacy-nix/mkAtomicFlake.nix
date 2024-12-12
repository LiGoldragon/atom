inputs: manifest:
let
  mkCustomAtomicFlake = import ./mkCustomAtomicFlake.nix;

in
mkCustomAtomicFlake {
  inherit inputs manifest;
}
