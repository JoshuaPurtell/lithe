import Lithe.Core.Handler
import Lithe.Core.Error
import Lithe.Http.Request
import Lithe.Http.File
import Init.System.FilePath

namespace Lithe

structure StaticFilesConfig where
  root : System.FilePath
  indexFile : Option String := some "index.html"
  cacheControl : Option String := none
  chunkSize : Nat := 65536
  enableRange : Bool := true

namespace StaticFiles

private def hasUnsafeChar (s : String) : Bool :=
  s.toList.any (fun c => c == '\\' || c == ':' || c == Char.ofNat 0)

private def normalizeSegments (path : String) : Option (List String) :=
  let raw := if path.startsWith "/" then (path.drop 1).toString else path
  let segs := raw.splitOn "/"
  let rec go (rest : List String) (acc : List String) : Option (List String) :=
    match rest with
    | [] => some acc.reverse
    | seg :: tail =>
        let s := seg.trimAscii.toString
        if s.isEmpty || s = "." then
          go tail acc
        else if s = ".." then
          match acc with
          | [] => none
          | _ :: acc' => go tail acc'
        else if hasUnsafeChar s then
          none
        else
          go tail (s :: acc)
  go segs []

private def resolvePath (cfg : StaticFilesConfig) (reqPath : String) : Option System.FilePath :=
  match normalizeSegments reqPath with
  | none => none
  | some segs =>
      let path := segs.foldl (fun acc seg => acc / seg) cfg.root
      some path

def withConfig (cfg : StaticFilesConfig) : Handler :=
  fun ctx => do
    let path? := resolvePath cfg ctx.req.path
    match path? with
    | none => throw (HttpError.notFound "Not Found")
    | some path => do
        let path ←
          if (← path.isDir) then
            match cfg.indexFile with
            | some idx => pure (path / idx)
            | none => throw (HttpError.notFound "Not Found")
          else
            pure path
        let rangeHeader? := if cfg.enableRange then ctx.req.header? "range" else none
        let resp ← Response.fileWithRangeHeader path rangeHeader? cfg.chunkSize
        match cfg.cacheControl with
        | some v => pure (resp.withHeader "cache-control" v)
        | none => pure resp

@[inline] def handler (root : System.FilePath) : Handler :=
  withConfig { root := root }

end StaticFiles

end Lithe
