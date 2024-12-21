let
  inherit (__internal) scope;
in
{
  Std = scope.use ? std;
  Lib = scope.use ? std && scope.use.std ? lib;
  CoreF = __atom.features.resolved.core;
  StdF = __atom.features.resolved.std;
  Sanity = scope.use.std.__internal.__isStd__;
}
