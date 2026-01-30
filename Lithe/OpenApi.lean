import Lithe.Prelude
import Lithe.Http.Response
import Lithe.Core.Handler

namespace Lithe
namespace OpenApi

@[inline] def jsonObj (fields : Array (String × Lean.Json)) : Lean.Json :=
  Lean.Json.mkObj fields.toList

private def optField (name : String) (value : Option Lean.Json) : List (String × Lean.Json) :=
  match value with
  | some v => [(name, v)]
  | none => []

private def optStr (name : String) (value : Option String) : List (String × Lean.Json) :=
  match value with
  | some v => [(name, Lean.Json.str v)]
  | none => []

structure Info where
  title : String
  version : String
  description : Option String := none

namespace Info

@[inline] def toJson (info : Info) : Lean.Json :=
  let fields : List (String × Lean.Json) :=
    [ ("title", Lean.Json.str info.title)
    , ("version", Lean.Json.str info.version)
    ]
  let fields := fields ++ optStr "description" info.description
  Lean.Json.mkObj fields

end Info

/--
Schema helpers (minimal, override by providing raw JSON when needed).
-/
@[inline] def schema (typ : String) (format : Option String := none) : Lean.Json :=
  let fields : List (String × Lean.Json) :=
    [ ("type", Lean.Json.str typ) ]
  let fields := fields ++ optStr "format" format
  Lean.Json.mkObj fields

@[inline] def schemaString : Lean.Json := schema "string" none
@[inline] def schemaInt : Lean.Json := schema "integer" (some "int64")
@[inline] def schemaBool : Lean.Json := schema "boolean" none
@[inline] def schemaNumber : Lean.Json := schema "number" none

@[inline] def schemaArray (items : Lean.Json) : Lean.Json :=
  jsonObj #[("type", Lean.Json.str "array"), ("items", items)]

@[inline] def schemaObject (props : Array (String × Lean.Json)) (required : Array String := #[]) : Lean.Json :=
  let base : Array (String × Lean.Json) :=
    #[("type", Lean.Json.str "object"), ("properties", jsonObj props)]
  if required.isEmpty then
    jsonObj base
  else
    jsonObj (base.push ("required", Lean.Json.arr (required.map Lean.Json.str)))

structure MediaType where
  schema : Lean.Json
  exampleValue : Option Lean.Json := none

namespace MediaType

@[inline] def toJson (mt : MediaType) : Lean.Json :=
  let fields : List (String × Lean.Json) :=
    [ ("schema", mt.schema) ]
  let fields := fields ++ optField "example" mt.exampleValue
  Lean.Json.mkObj fields

end MediaType

structure Parameter where
  name : String
  location : String
  required : Bool := false
  description : Option String := none
  schema : Lean.Json := schemaString

namespace Parameter

@[inline] def toJson (p : Parameter) : Lean.Json :=
  let base : List (String × Lean.Json) :=
    [ ("name", Lean.Json.str p.name)
    , ("in", Lean.Json.str p.location)
    , ("required", Lean.Json.bool p.required)
    , ("schema", p.schema)
    ]
  let base := base ++ optStr "description" p.description
  Lean.Json.mkObj base

end Parameter

structure RequestBody where
  description : Option String := none
  required : Bool := false
  content : Array (String × MediaType) := #[]

namespace RequestBody

@[inline] def toJson (rb : RequestBody) : Lean.Json :=
  let content := jsonObj (rb.content.map (fun (k, v) => (k, v.toJson)))
  let base : List (String × Lean.Json) :=
    [ ("required", Lean.Json.bool rb.required)
    , ("content", content)
    ]
  let base := base ++ optStr "description" rb.description
  Lean.Json.mkObj base

end RequestBody

structure Response where
  description : String := ""
  content : Array (String × MediaType) := #[]

namespace Response

@[inline] def toJson (r : Response) : Lean.Json :=
  let base : List (String × Lean.Json) :=
    [ ("description", Lean.Json.str r.description) ]
  if r.content.isEmpty then
    Lean.Json.mkObj base
  else
    let content := jsonObj (r.content.map (fun (k, v) => (k, v.toJson)))
    Lean.Json.mkObj (base ++ [("content", content)])

end Response

structure Operation where
  summary : Option String := none
  description : Option String := none
  operationId : Option String := none
  tags : Array String := #[]
  parameters : Array Parameter := #[]
  requestBody : Option RequestBody := none
  responses : Array (String × Response) := #[]

namespace Operation

@[inline] def toJson (op : Operation) : Lean.Json :=
  let base : List (String × Lean.Json) := []
  let base := base ++ optStr "summary" op.summary
  let base := base ++ optStr "description" op.description
  let base := base ++ optStr "operationId" op.operationId
  let base := if op.tags.isEmpty then base else base ++ [("tags", Lean.Json.arr (op.tags.map Lean.Json.str))]
  let base := if op.parameters.isEmpty then base else base ++ [("parameters", Lean.Json.arr (op.parameters.map Parameter.toJson))]
  let base := base ++ optField "requestBody" (op.requestBody.map RequestBody.toJson)
  let responses := jsonObj (op.responses.map (fun (k, v) => (k, v.toJson)))
  let base := base ++ [("responses", responses)]
  Lean.Json.mkObj base

end Operation

structure PathItem where
  get? : Option Operation := none
  post? : Option Operation := none
  put? : Option Operation := none
  patch? : Option Operation := none
  delete? : Option Operation := none
  options? : Option Operation := none
  head? : Option Operation := none

namespace PathItem

@[inline] def toJson (p : PathItem) : Lean.Json :=
  let fields : List (String × Lean.Json) :=
    []
    ++ optField "get" (p.get?.map Operation.toJson)
    ++ optField "post" (p.post?.map Operation.toJson)
    ++ optField "put" (p.put?.map Operation.toJson)
    ++ optField "patch" (p.patch?.map Operation.toJson)
    ++ optField "delete" (p.delete?.map Operation.toJson)
    ++ optField "options" (p.options?.map Operation.toJson)
    ++ optField "head" (p.head?.map Operation.toJson)
  Lean.Json.mkObj fields

end PathItem

structure Spec where
  info : Info
  openapi : String := "3.0.3"
  servers : Array String := #[]
  paths : Array (String × PathItem) := #[]
  components : Option Lean.Json := none

namespace Spec

@[inline] def toJson (spec : Spec) : Lean.Json :=
  let base : List (String × Lean.Json) :=
    [ ("openapi", Lean.Json.str spec.openapi)
    , ("info", Info.toJson spec.info)
    ]
  let servers :=
    if spec.servers.isEmpty then
      []
    else
      let items := spec.servers.map (fun url => jsonObj #[("url", Lean.Json.str url)])
      [("servers", Lean.Json.arr items)]
  let paths := jsonObj (spec.paths.map (fun (k, v) => (k, v.toJson)))
  let base := base ++ servers ++ [("paths", paths)]
  let base := base ++ optField "components" spec.components
  Lean.Json.mkObj base

@[inline] def toResponse (spec : Spec) : Lithe.Response :=
  Lithe.Response.json (toJson spec)

end Spec

/--
Handler that serves an OpenAPI JSON spec.
-/
@[inline] def openApiHandler (spec : Spec) : Handler :=
  fun _ => pure (Spec.toResponse spec)

/--
Serve a Swagger UI page that points at the provided OpenAPI JSON path.
-/
@[inline] def swaggerUiHandler (openApiPath : String := "/openapi.json") : Handler :=
  fun _ =>
    let html := String.intercalate "\n"
      [ "<!DOCTYPE html>"
      , "<html lang=\"en\">"
      , "  <head>"
      , "    <meta charset=\"UTF-8\" />"
      , "    <title>Swagger UI</title>"
      , "    <link rel=\"stylesheet\" href=\"https://unpkg.com/swagger-ui-dist@5/swagger-ui.css\" />"
      , "  </head>"
      , "  <body>"
      , "    <div id=\"swagger-ui\"></div>"
      , "    <script src=\"https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js\"></script>"
      , "    <script>"
      , "      window.onload = function() {"
      , s!"        SwaggerUIBundle(\{ url: '{openApiPath}', dom_id: '#swagger-ui' });"
      , "      };"
      , "    </script>"
      , "  </body>"
      , "</html>"
      ]
    pure (Lithe.Response.html html)

end OpenApi
end Lithe
