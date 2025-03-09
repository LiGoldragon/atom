rawInputs: manifest:
let
  importAtom = import ../atom-nix/core/importAtom.nix;

  inputsHaveSystem = builtins.hasAttr "system" rawInputs;

  mkAtom = importAtom {
    inputs = builtins.removeAttrs rawInputs [ "system" ];
    system = if inputsHaveSystem then rawInputs.system.value else null;
    _calledFromFlake = true;
  };

in
mkAtom manifest
