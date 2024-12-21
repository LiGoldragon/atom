let
  inherit (use) std;
in
{
  Foo = 1;
  bar = atom.foo + 2;
  baz = mod.bar + 4;
  F = std.set.filterMap;
  File = std.readFile "${mod}/bum";
  Buzz = mod.buzz;
  Next = ./next; # should be a non-existant path: /nix/store/next
  Bar = mod.bar;
}
