{
  bar = 3;
  buzz = {
    fuzz = {
      bar = 5;
    };
  };
  f = scopedImport { std = builtins; } "${../std/set/filterMap.nix}";
  file = builtins.readFile ./bld/bum;
  foo = 1;
  next = /nix/store/next;
}
