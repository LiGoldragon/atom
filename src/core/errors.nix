let
  l = builtins;
  imap = scopedImport { std = builtins; } ../std/list/imap.nix;
  sublist = scopedImport { std = builtins; } ../std/list/sublist.nix;
  digits = n: l.stringLength (l.toString n);
  spaces = n: toString (l.genList (x: " ") n);
  warn = l.warn or l.trace;
  right =
    str:
    let
      match = l.match "^( *)[^ ].*" str;
    in
    if match == null then
      l.stringLength str # If the string is all spaces
    else
      l.stringLength (l.head match);

in
{
  import = abort "Importing arbitrary Nix files is forbidden. Declare your dependencies via the module system instead.";
  fetch = abort "Ad hoc fetching is illegal. Declare dependencies statically in the manifest instead.";
  system = abort "Accessing the current system is impure. Declare supported systems in the manifest.";
  time = warn "currentTime: Ignoring request for current time, returning: 0";
  nixPath = warn "nixPath: ignoring impure NIX_PATH request, returning: []";
  storePath = abort "Making explicit dependencies on store paths is illegal.";
  getEnv = warn "getEnv: ignoring request to access impure envvar, returning: \"\"";
  missingName =
    file:
    let
      name = baseNameOf file;
      contents = l.readFile file;
      lines = l.filter l.isString (l.split "\n" contents);
      l = l.length lines;
      num = imap (i: line: { inherit i line; }) lines;
      atom = l.filter (x: l.match ".*\\[atom].*" x.line != null) num;
      i =
        if atom != [ ] then
          (l.head atom).i
        else
          throw ''
            missing required `[atom]` section
             --> ${name}
          '';
      g = if l - i < 5 then num else sublist i 4 num;
    in
    throw ''
      missing required field `name`
       --> ${name}:${toString (i + 1)}:${toString ((right (l.elemAt lines i)) + 1)}

      ${l.concatStringsSep "\n" (
        map (
          x:
          let
            pad = spaces ((digits l) - (digits (x.i + 1)));
          in
          "${toString (x.i + 1)}${pad} | ${if x.i == i then "${x.line} <~~~" else x.line}"
        ) g
      )}
    '';
}
