import Lithe.Prelude
import Init.System.FilePath

namespace Lithe

namespace Mime

private def withUtf8 (s : String) : String :=
  s!"{s}; charset=utf-8"

def fromExtension (ext : String) : String :=
  match ext.trimAscii.toString.toLower with
  | "html" => withUtf8 "text/html"
  | "htm" => withUtf8 "text/html"
  | "css" => withUtf8 "text/css"
  | "js" => withUtf8 "application/javascript"
  | "mjs" => withUtf8 "application/javascript"
  | "json" => withUtf8 "application/json"
  | "txt" => withUtf8 "text/plain"
  | "md" => withUtf8 "text/markdown"
  | "xml" => withUtf8 "application/xml"
  | "csv" => withUtf8 "text/csv"
  | "svg" => withUtf8 "image/svg+xml"
  | "png" => "image/png"
  | "jpg" => "image/jpeg"
  | "jpeg" => "image/jpeg"
  | "gif" => "image/gif"
  | "webp" => "image/webp"
  | "ico" => "image/x-icon"
  | "bmp" => "image/bmp"
  | "pdf" => "application/pdf"
  | "wasm" => "application/wasm"
  | "zip" => "application/zip"
  | "gz" => "application/gzip"
  | "tgz" => "application/gzip"
  | "tar" => "application/x-tar"
  | "mp3" => "audio/mpeg"
  | "wav" => "audio/wav"
  | "ogg" => "audio/ogg"
  | "mp4" => "video/mp4"
  | "webm" => "video/webm"
  | _ => "application/octet-stream"

def forPath (path : System.FilePath) : String :=
  match path.extension with
  | some ext => fromExtension ext
  | none => "application/octet-stream"

end Mime

end Lithe
