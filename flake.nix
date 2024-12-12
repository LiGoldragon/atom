{
  description = "Composable Nix Modules";

  outputs = _: {
    core = import ./atom-nix/core/mod.nix;
    importAtom = import ./atom-nix/core/importAtom.nix;
  };
}
