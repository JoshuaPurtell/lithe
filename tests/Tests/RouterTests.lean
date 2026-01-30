import Lithe.Router.Path
import Lithe.Router.Match
import Lithe.Http.Request
import Lithe.Http.Method
import Tests.Util

def testRouteParse : IO Unit := do
  let pat := Lithe.RoutePattern.parse "/users/:id"
  let segs := pat.segments.toList
  match segs with
  | [Lithe.Segment.Lit "users", Lithe.Segment.Param "id"] => pure ()
  | _ => throw (IO.userError "route parse did not produce expected segments")

def testRouteMatchSuccess : IO Unit := do
  let pat := Lithe.RoutePattern.parse "/users/:id"
  match Lithe.matchRoute pat "/users/123" with
  | some params =>
      match params.get? "id" with
      | some value => assertEqString value "123" "path param id"
      | none => throw (IO.userError "missing path param 'id'")
  | none => throw (IO.userError "route should have matched")

def testRouteMatchFailure : IO Unit := do
  let pat := Lithe.RoutePattern.parse "/users/:id"
  let result := Lithe.matchRoute pat "/users"
  assert (result.isNone) "route should not match missing param"

def testQueryParse : IO Unit := do
  let req : Lithe.Request :=
    { method := Lithe.Method.GET
    , path := "/search"
    , query := "q=lean&tag=web&tag=framework"
    , headers := #[]
    , body := ByteArray.empty
    }
  let params := Lithe.Request.queryParams req
  match params.get? "q" with
  | some values =>
      assertEqNat values.size 1 "query param q count"
      assertEqString values[0]! "lean" "query param q"
  | none => throw (IO.userError "missing query param q")
  match params.get? "tag" with
  | some values =>
      assertEqNat values.size 2 "query param tag count"
      assertEqString values[0]! "web" "query param tag[0]"
      assertEqString values[1]! "framework" "query param tag[1]"
  | none => throw (IO.userError "missing query param tag")
