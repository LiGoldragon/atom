{
  pkgs ? atom.pkgs,
}:
pkgs.mkShell {
  packages = with pkgs; [
    treefmt
    npins
    nixfmt-rfc-style
    shfmt
  ];
}
