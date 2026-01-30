import Lithe.Prelude
import Lithe.Http.Method
import Lithe.Http.Request
import Lithe.Http.Response
import Lithe.Http.Status

namespace Lithe

def wireVersion : UInt8 := 1
def streamWireVersion : UInt8 := 1

private def byteArrayOfList (xs : List UInt8) : ByteArray :=
  xs.foldl (fun acc b => acc.push b) ByteArray.empty

structure Writer where
  buf : ByteArray

namespace Writer

@[inline] def empty : Writer := { buf := ByteArray.empty }

@[inline] def writeU8 (w : Writer) (b : UInt8) : Writer :=
  { buf := w.buf.push b }

private def u16Bytes (n : UInt16) : UInt8 × UInt8 :=
  let v := n.toNat
  (UInt8.ofNat (v / 256), UInt8.ofNat (v % 256))

private def u32Bytes (n : UInt32) : UInt8 × UInt8 × UInt8 × UInt8 :=
  let v := n.toNat
  let b1 := UInt8.ofNat (v / 16777216)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 256) % 256)
  let b4 := UInt8.ofNat (v % 256)
  (b1, b2, b3, b4)

@[inline] def writeU16 (w : Writer) (n : UInt16) : Writer :=
  let (b1, b2) := u16Bytes n
  (w.writeU8 b1).writeU8 b2

@[inline] def writeU32 (w : Writer) (n : UInt32) : Writer :=
  let (b1, b2, b3, b4) := u32Bytes n
  ((w.writeU8 b1).writeU8 b2 |>.writeU8 b3).writeU8 b4

@[inline] def writeRaw (w : Writer) (b : ByteArray) : Writer :=
  { buf := b.toList.foldl (fun acc x => acc.push x) w.buf }

@[inline] def writeBytes (w : Writer) (b : ByteArray) : Writer :=
  (w.writeU32 (UInt32.ofNat b.size)).writeRaw b

@[inline] def writeString (w : Writer) (s : String) : Writer :=
  w.writeBytes (stringToBytes s)

@[inline] def writeOptString (w : Writer) (s : Option String) : Writer :=
  match s with
  | none => w.writeU8 0
  | some v => (w.writeU8 1).writeString v

end Writer

structure Reader where
  rest : List UInt8

namespace Reader

@[inline] def ofByteArray (b : ByteArray) : Reader :=
  { rest := b.toList }

@[inline] def readU8 (r : Reader) : Except String (UInt8 × Reader) :=
  match r.rest with
  | [] => throw "unexpected eof"
  | b :: rest => pure (b, { rest := rest })

@[inline] def readU16 (r : Reader) : Except String (UInt16 × Reader) := do
  let (b1, r) ← readU8 r
  let (b2, r) ← readU8 r
  let v := b1.toNat * 256 + b2.toNat
  pure (UInt16.ofNat v, r)

@[inline] def readU32 (r : Reader) : Except String (UInt32 × Reader) := do
  let (b1, r) ← readU8 r
  let (b2, r) ← readU8 r
  let (b3, r) ← readU8 r
  let (b4, r) ← readU8 r
  let v := b1.toNat * 16777216 + b2.toNat * 65536 + b3.toNat * 256 + b4.toNat
  pure (UInt32.ofNat v, r)

private partial def takeN? (n : Nat) (xs : List UInt8) : Option (List UInt8 × List UInt8) :=
  if n = 0 then
    some ([], xs)
  else
    match xs with
    | [] => none
    | x :: rest =>
        match takeN? (n - 1) rest with
        | some (taken, remaining) => some (x :: taken, remaining)
        | none => none

@[inline] def readRaw (n : Nat) (r : Reader) : Except String (ByteArray × Reader) :=
  match takeN? n r.rest with
  | some (taken, rest) => pure (byteArrayOfList taken, { rest := rest })
  | none => throw "unexpected eof"

@[inline] def readBytes (r : Reader) : Except String (ByteArray × Reader) := do
  let (len, r) ← readU32 r
  readRaw len.toNat r

@[inline] def readString (r : Reader) : Except String (String × Reader) := do
  let (bytes, r) ← readBytes r
  match bytesToString? bytes with
  | some s => pure (s, r)
  | none => throw "invalid utf-8"

@[inline] def readOptString (r : Reader) : Except String (Option String × Reader) := do
  let (flag, r) ← readU8 r
  if flag == 0 then
    pure (none, r)
  else if flag == 1 then
    let (s, r) ← readString r
    pure (some s, r)
  else
    throw "invalid option flag"

private partial def readHeadersLoop
    (n : Nat) (r : Reader) (acc : Array (String × String)) :
    Except String (Array (String × String) × Reader) := do
  if n = 0 then
    pure (acc, r)
  else
    let (k, r) ← readString r
    let (v, r) ← readString r
    readHeadersLoop (n - 1) r (acc.push (k, v))

@[inline] def readHeaders (n : Nat) (r : Reader) : Except String (Array (String × String) × Reader) :=
  readHeadersLoop n r #[]

end Reader

structure WireRequest where
  method  : Method
  path    : String
  query   : String
  headers : Array (String × String)
  body    : ByteArray
  remote  : Option String := none

structure WireResponse where
  status  : Nat
  headers : Array (String × String)
  body    : ByteArray

namespace WireRequest

@[inline] def toRequest (wr : WireRequest) : Request :=
  { method := wr.method
  , path := wr.path
  , query := wr.query
  , headers := wr.headers
  , body := wr.body
  , remote := wr.remote
  }

end WireRequest

namespace WireResponse

@[inline] def ofResponse (resp : Response) : WireResponse :=
  { status := resp.status.code.toNat
  , headers := resp.headers
  , body := resp.body
  }

@[inline] def toResponse (wr : WireResponse) : Response :=
  { status := Status.ofCode (UInt16.ofNat wr.status)
  , headers := wr.headers
  , body := wr.body
  }

end WireResponse

@[inline] def encodeWireRequest (req : WireRequest) : ByteArray :=
  let w := Writer.empty
  let w := w.writeU8 wireVersion
  let w := w.writeU8 req.method.toUInt8
  let w := w.writeString req.path
  let w := w.writeString req.query
  let w := w.writeU32 (UInt32.ofNat req.headers.size)
  let w := req.headers.foldl (init := w) (fun acc h =>
    acc.writeString h.fst |>.writeString h.snd
  )
  let w := w.writeBytes req.body
  let w := w.writeOptString req.remote
  w.buf

@[inline] def decodeWireRequest (bytes : ByteArray) : Except String WireRequest := do
  let r := Reader.ofByteArray bytes
  let (ver, r) ← Reader.readU8 r
  if ver != wireVersion then
    throw s!"unsupported wire version {ver.toNat}"
  let (methodByte, r) ← Reader.readU8 r
  let method ←
    match Method.ofUInt8? methodByte with
    | some m => pure m
    | none => throw s!"unknown method {methodByte.toNat}"
  let (path, r) ← Reader.readString r
  let (query, r) ← Reader.readString r
  let (count, r) ← Reader.readU32 r
  let (headers, r) ← Reader.readHeaders count.toNat r
  let (body, r) ← Reader.readBytes r
  let (remote, _r) ← Reader.readOptString r
  pure
    { method := method
    , path := path
    , query := query
    , headers := headers
    , body := body
    , remote := remote
    }

@[inline] def encodeWireResponse (resp : WireResponse) : ByteArray :=
  let w := Writer.empty
  let w := w.writeU8 wireVersion
  let w := w.writeU16 (UInt16.ofNat resp.status)
  let w := w.writeU32 (UInt32.ofNat resp.headers.size)
  let w := resp.headers.foldl (init := w) (fun acc h =>
    acc.writeString h.fst |>.writeString h.snd
  )
  let w := w.writeBytes resp.body
  w.buf

@[inline] def decodeWireResponse (bytes : ByteArray) : Except String WireResponse := do
  let r := Reader.ofByteArray bytes
  let (ver, r) ← Reader.readU8 r
  if ver != wireVersion then
    throw s!"unsupported wire version {ver.toNat}"
  let (status, r) ← Reader.readU16 r
  let (count, r) ← Reader.readU32 r
  let (headers, r) ← Reader.readHeaders count.toNat r
  let (body, _r) ← Reader.readBytes r
  pure
    { status := status.toNat
    , headers := headers
    , body := body
    }

inductive StreamMsg where
  | head (status : Nat) (headers : Array (String × String)) (isStream : Bool) (body : ByteArray)
  | chunk (body : ByteArray)
  | finish

@[inline] def encodeStreamHead (status : UInt16) (headers : Array (String × String)) (isStream : Bool) (body : ByteArray) : ByteArray :=
  let w := Writer.empty
  let w := w.writeU8 streamWireVersion
  let w := w.writeU8 1
  let w := w.writeU16 status
  let w := w.writeU8 (if isStream then 1 else 0)
  let w := w.writeU32 (UInt32.ofNat headers.size)
  let w := headers.foldl (init := w) (fun acc h =>
    acc.writeString h.fst |>.writeString h.snd
  )
  let w := w.writeBytes body
  w.buf

@[inline] def encodeStreamChunk (body : ByteArray) : ByteArray :=
  let w := Writer.empty
  let w := w.writeU8 streamWireVersion
  let w := w.writeU8 2
  let w := w.writeBytes body
  w.buf

@[inline] def encodeStreamEnd : ByteArray :=
  let w := Writer.empty
  let w := w.writeU8 streamWireVersion
  let w := w.writeU8 3
  w.buf

@[inline] def decodeStreamMsg (bytes : ByteArray) : Except String StreamMsg := do
  let r := Reader.ofByteArray bytes
  let (ver, r) ← Reader.readU8 r
  if ver != streamWireVersion then
    throw s!"unsupported stream wire version {ver.toNat}"
  let (kind, r) ← Reader.readU8 r
  match kind.toNat with
  | 1 =>
      let (status, r) ← Reader.readU16 r
      let (isStreamByte, r) ← Reader.readU8 r
      let isStream := isStreamByte != 0
      let (count, r) ← Reader.readU32 r
      let (headers, r) ← Reader.readHeaders count.toNat r
      let (body, _r) ← Reader.readBytes r
      pure (StreamMsg.head status.toNat headers isStream body)
  | 2 =>
      let (body, _r) ← Reader.readBytes r
      pure (StreamMsg.chunk body)
  | 3 =>
      pure StreamMsg.finish
  | _ =>
      throw s!"unknown stream message type {kind.toNat}"

end Lithe
