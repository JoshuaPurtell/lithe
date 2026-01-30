import Lithe.Prelude
import Lithe.Http.Response
import Lithe.Http.BodyStream

def assert (cond : Bool) (msg : String) : IO Unit := do
  if cond then
    pure ()
  else
    throw (IO.userError msg)

def assertEqString (actual expected : String) (label : String := "string") : IO Unit := do
  assert (actual = expected) s!"{label} mismatch: expected '{expected}', got '{actual}'"

def assertEqNat (actual expected : Nat) (label : String := "number") : IO Unit := do
  assert (actual = expected) s!"{label} mismatch: expected {expected}, got {actual}"

def assertEqBytes (actual expected : ByteArray) (label : String := "bytes") : IO Unit := do
  let a := Lithe.byteArrayToNatArray actual
  let e := Lithe.byteArrayToNatArray expected
  assert (decide (a = e)) s!"{label} mismatch: expected {e}, got {a}"

def assertHeader (resp : Lithe.Response) (name expected : String) : IO Unit := do
  match resp.header? name with
  | some value => assertEqString value expected s!"header '{name}'"
  | none => throw (IO.userError s!"missing header '{name}'")

def bodyString (resp : Lithe.Response) : IO String := do
  match Lithe.bytesToString? resp.body with
  | some s => pure s
  | none => throw (IO.userError "response body is not valid UTF-8")

partial def readStreamAll (stream : Lithe.BodyStream) : IO ByteArray := do
  let rec loop (acc : ByteArray) : IO ByteArray := do
    let res ← stream.next.run
    match res with
    | .ok (some chunk) => loop (acc ++ chunk)
    | .ok none => pure acc
    | .error err => throw (IO.userError s!"stream error: {err.message}")
  loop ByteArray.empty

def responseBody (resp : Lithe.Response) : IO ByteArray := do
  match resp.bodyStream with
  | none => pure resp.body
  | some stream =>
      let rest ← readStreamAll stream
      pure (resp.body ++ rest)
