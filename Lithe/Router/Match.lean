import Lithe.Router.Path

namespace Lithe

private def splitPath (path : String) : List String :=
  let parts := path.splitOn "/"
  parts.filter (fun s => s ≠ "")

private def matchSegments
    (segs : List Segment)
    (vals : List String)
    (acc : Std.HashMap String String) : Option (Std.HashMap String String) :=
  match segs, vals with
  | [], [] => some acc
  | Segment.Lit s :: rest, v :: vs =>
      if s = v then
        matchSegments rest vs acc
      else
        none
  | Segment.Param name :: rest, v :: vs =>
      matchSegments rest vs (acc.insert name v)
  | _, _ => none

/-- Match a request path against a pattern and return path params. -/
def matchRoute (pat : RoutePattern) (path : String) : Option (Std.HashMap String String) :=
  matchSegments pat.segments.toList (splitPath path) Std.HashMap.emptyWithCapacity

end Lithe
