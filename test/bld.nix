let
  mod =
    import ../. { }
      # added to test implicit path conversion when path is a string
      (builtins.toPath ./bld);
in
builtins.deepSeq mod mod
