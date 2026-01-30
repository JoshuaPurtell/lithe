import Lithe.Test.Generators
import Lithe.Test.Properties
import Lithe.Http.Method
import Lithe.Http.Response

def propMethodRoundTrip (m : Lithe.Method) : Bool :=
  Lithe.Method.ofString? (Lithe.Method.toString m) = some m

def testMethodRoundTrip : IO Unit := do
  Lithe.quickCheck propMethodRoundTrip Lithe.Generator.method 200

def propResponseSetHeader (pair : String × String) : Bool :=
  let (name, value) := pair
  let resp := Lithe.Response.text "ok"
  let resp' := Lithe.Response.setHeader resp name value
  resp'.header? name = some value

def testResponseSetHeader : IO Unit := do
  Lithe.quickCheck propResponseSetHeader Lithe.Generator.headerPair 200
