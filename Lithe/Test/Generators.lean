import Lithe.Prelude
import Lithe.Http.Method
import Lithe.Http.Request
import Lithe.Http.Response
import Lithe.Http.Status
import Lithe.Router.Router
import Lithe.Router.Path
import Lithe.Core.Handler
import Lithe.Core.Error
import Lithe.Core.Context
import Lithe.Core.Middleware

namespace Lithe

structure Generator (α : Type) where
  run : Nat → Nat → (α × Nat) -- seed → size → value × nextSeed

namespace Generator

def pure (a : α) : Generator α :=
  { run := fun seed _ => (a, seed) }

def map (f : α → β) (g : Generator α) : Generator β :=
  { run := fun seed size =>
      let (a, seed') := g.run seed size
      (f a, seed')
  }

def bind (g : Generator α) (f : α → Generator β) : Generator β :=
  { run := fun seed size =>
      let (a, seed') := g.run seed size
      (f a).run seed' size
  }

instance : Pure Generator := ⟨pure⟩
instance : Bind Generator := ⟨bind⟩
instance : Functor Generator where
  map := map
  mapConst := fun b g => map (fun _ => b) g

def sized (f : Nat → Generator α) : Generator α :=
  { run := fun seed size => (f size).run seed size }

def resize (n : Nat) (g : Generator α) : Generator α :=
  { run := fun seed _ => g.run seed n }

def size : Generator Nat :=
  { run := fun seed size => (size, seed) }

def modulus : Nat := 4294967296

def nextSeed (seed : Nat) : Nat :=
  (1664525 * seed + 1013904223) % modulus

def randNat (seed lo hi : Nat) : Nat × Nat :=
  let seed' := nextSeed seed
  if hi < lo then
    (lo, seed')
  else
    let range := (hi - lo) + 1
    (lo + (seed' % range), seed')

def chooseNat (lo hi : Nat) : Generator Nat :=
  { run := fun seed _ => randNat seed lo hi }

def chooseBool : Generator Bool :=
  map (fun n => n = 1) (chooseNat 0 1)

def chooseUInt8 : Generator UInt8 :=
  map UInt8.ofNat (chooseNat 0 255)

def oneOf (xs : Array α) (fallback : α) : Generator α :=
  { run := fun seed _ =>
      let hi := if xs.isEmpty then 0 else xs.size - 1
      let (idx, seed') := randNat seed 0 hi
      (xs.getD idx fallback, seed')
  }

def oneOfGen (gs : Array (Generator α)) (fallback : Generator α) : Generator α :=
  bind (oneOf gs fallback) (fun g => g)

def optionOf (g : Generator α) : Generator (Option α) :=
  bind chooseBool (fun take =>
    if take then
      map some g
    else
      pure none
  )

def chooseLen (minLen maxLen : Nat) : Generator Nat :=
  sized (fun size =>
    let maxLen' := if maxLen < minLen then minLen else maxLen
    let cap := Nat.min maxLen' (minLen + size)
    chooseNat minLen cap
  )

def arrayOf (g : Generator α) (minLen maxLen : Nat) : Generator (Array α) :=
  bind (chooseLen minLen maxLen) (fun len =>
    { run := fun seed size =>
        let rec loop (n : Nat) (seed' : Nat) (acc : Array α) : Array α × Nat :=
          if n = 0 then
            (acc, seed')
          else
            let (v, seed'') := g.run seed' size
            loop (n - 1) seed'' (acc.push v)
        loop len seed #[]
    }
  )

def listOf (g : Generator α) (minLen maxLen : Nat) : Generator (List α) :=
  map (fun arr => arr.toList) (arrayOf g minLen maxLen)

def stringOfChars (chars : Array Char) : String :=
  String.ofList chars.toList

def chooseCharFrom (chars : Array Char) (fallback : Char) : Generator Char :=
  map (fun idx => chars.getD idx fallback) (chooseNat 0 (chars.size - 1))

def chooseStringFrom (chars : Array Char) (fallback : Char) (minLen maxLen : Nat) : Generator String :=
  map stringOfChars (arrayOf (chooseCharFrom chars fallback) minLen maxLen)

def alphaChars : Array Char :=
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".toList.toArray

def alphaNumChars : Array Char :=
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".toList.toArray

def headerNameChars : Array Char :=
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".toList.toArray

def headerValueChars : Array Char :=
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_ .,:;/@()[]{}".toList.toArray

def identifier (minLen maxLen : Nat) : Generator String :=
  chooseStringFrom alphaNumChars 'a' minLen maxLen

def headerName : Generator String :=
  chooseStringFrom headerNameChars 'x' 1 16

def headerValue : Generator String :=
  chooseStringFrom headerValueChars ' ' 0 32

def headerPair : Generator (String × String) :=
  bind headerName (fun k =>
    map (fun v => (k, v)) headerValue
  )

def pathSegment : Generator String :=
  chooseStringFrom alphaNumChars 'a' 1 10

def path : Generator String :=
  bind (arrayOf pathSegment 1 4) (fun segs =>
    pure ("/" ++ String.intercalate "/" segs.toList)
  )

def queryPair : Generator (String × String) :=
  bind (chooseStringFrom alphaChars 'a' 1 8) (fun k =>
    map (fun v => (k, v)) (chooseStringFrom alphaNumChars 'a' 0 12)
  )

def queryString : Generator String :=
  bind (arrayOf queryPair 0 4) (fun pairs =>
    if pairs.isEmpty then
      pure ""
    else
      let parts := pairs.toList.map (fun (k, v) => s!"{k}={v}")
      pure (String.intercalate "&" parts)
  )

def headers : Generator Headers :=
  arrayOf headerPair 0 4

def bodyBytes (minLen maxLen : Nat) : Generator ByteArray :=
  map byteArrayOfNatArray (arrayOf (chooseNat 0 255) minLen maxLen)

def method : Generator Method :=
  oneOf #[Method.GET, Method.POST, Method.PUT, Method.PATCH, Method.DELETE, Method.OPTIONS, Method.HEAD] Method.GET

def statusCode : Generator UInt16 :=
  oneOf #[200, 201, 204, 400, 404, 500] 200

def response : Generator Response :=
  oneOfGen #[
    map (fun s => Response.text s) (chooseStringFrom headerValueChars ' ' 0 32),
    map (fun b => Response.bytes b) (bodyBytes 0 32),
    map (fun code => Response.empty code) statusCode
  ] (pure (Response.text ""))

def handler : Generator Handler :=
  oneOfGen #[
    map (fun s => Handler.pure (Response.text s)) (chooseStringFrom headerValueChars ' ' 0 32),
    map (fun code => Handler.pure (Response.empty code)) statusCode,
    pure (fun ctx => do
      return Response.text ctx.req.path)
  ] (pure (Handler.pure (Response.text "")))

def middlewareAddHeader (name value : String) : Middleware :=
  fun h ctx => do
    let resp ← h ctx
    return resp.withHeader name value

def middlewareSetStatus (code : UInt16) : Middleware :=
  fun h ctx => do
    let resp ← h ctx
    return resp.withStatus code

def middlewareShortCircuit (resp : Response) : Middleware :=
  fun _ => Handler.pure resp

def middleware : Generator Middleware :=
  oneOfGen #[
    pure Middleware.identity,
    map (fun (name, value) => middlewareAddHeader name value) headerPair,
    map middlewareSetStatus statusCode,
    map middlewareShortCircuit response
  ] (pure Middleware.identity)

def middlewareStack : Generator (Array Middleware) :=
  arrayOf middleware 0 4

def routeSegment : Generator String :=
  bind chooseBool (fun isParam =>
    if isParam then
      map (fun name => ":" ++ name) (chooseStringFrom alphaChars 'a' 1 8)
    else
      pathSegment
  )

def routePath : Generator String :=
  bind (arrayOf routeSegment 1 4) (fun segs =>
    pure ("/" ++ String.intercalate "/" segs.toList)
  )

def route : Generator Route :=
  bind method (fun m =>
    bind routePath (fun p =>
      map (fun h => { method := m, pattern := RoutePattern.parse p, handler := h }) handler
    )
  )

def router : Generator Router :=
  bind (arrayOf route 0 4) (fun routes =>
    let r := routes.foldl (fun acc rt => { acc with routes := acc.routes.push rt }) Router.empty
    pure r
  )

def request : Generator Request :=
  bind method (fun m =>
    bind path (fun p =>
      bind queryString (fun q =>
        bind headers (fun hs =>
          map (fun b =>
            { method := m, path := p, query := q, headers := hs, body := b }) (bodyBytes 0 64)
        )
      )
    )
  )

end Generator

end Lithe
