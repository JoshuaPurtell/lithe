import Lithe.Prelude

namespace Lithe

inductive Segment
| Lit (s : String)
| Param (name : String)
  deriving BEq, DecidableEq, Repr

structure RoutePattern where
  segments : Array Segment
  deriving Repr

namespace RoutePattern

private def splitPath (path : String) : Array String :=
  let parts := path.splitOn "/"
  let parts := parts.filter (fun s => s ≠ "")
  parts.toArray

@[inline] def parse (path : String) : RoutePattern :=
  let segs := (splitPath path).map (fun s =>
    if s.startsWith ":" then
      Segment.Param ((s.drop 1).toString)
    else
      Segment.Lit s
  )
  { segments := segs }

@[inline] def prepend (pre : RoutePattern) (pat : RoutePattern) : RoutePattern :=
  { segments := pre.segments ++ pat.segments }

end RoutePattern

end Lithe
