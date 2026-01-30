import Tests.RouterTests
import Tests.MiddlewareTests
import Tests.Properties
import Tests.CodecTests
import Tests.StreamTests
import Tests.StreamQueueTests
import Tests.FeatureTests

open _root_.Tests.RouterTests
open _root_.Tests.MiddlewareTests
open _root_.Tests.Properties
open _root_.Tests.CodecTests
open _root_.Tests.StreamTests
open _root_.Tests.StreamQueueTests
open _root_.Tests.FeatureTests

def runTest (name : String) (test : IO Unit) : IO Unit := do
  IO.println s!"[test] {name}"
  test

def main : IO Unit := do
  let tests : List (String × IO Unit) :=
    [ ("router.parse", testRouteParse)
    , ("router.match.success", testRouteMatchSuccess)
    , ("router.match.failure", testRouteMatchFailure)
    , ("request.query.parse", testQueryParse)
    , ("middleware.identity", testIdentity)
    , ("middleware.compose.headers", testComposeAddsHeaders)
    , ("middleware.error.propagation", testErrorPropagation)
    , ("property.method.roundtrip", testMethodRoundTrip)
    , ("property.response.header", testResponseSetHeader)
    , ("codec.wire.request", testWireRequestRoundTrip)
    , ("codec.wire.response", testWireResponseRoundTrip)
    , ("codec.stream", testStreamMessageRoundTrip)
    , ("codec.websocket", testWebSocketMessageRoundTrip)
    , ("stream.queue", testBodyStreamQueue)
    , ("stream.cancel", testBodyStreamCancel)
    , ("writer.cancel", testBodyWriterCancel)
    , ("streamqueue.order", testStreamQueueOrder)
    , ("streamqueue.capacity", testStreamQueueCapacity)
    , ("streamqueue.close", testStreamQueueClose)
    , ("form.parse", testFormParse)
    , ("form.invalid", testFormInvalid)
    , ("multipart.parse", testMultipartParse)
    , ("multipart.missing_boundary", testMultipartMissingBoundary)
    , ("static.serve", testStaticFilesServe)
    , ("static.index", testStaticIndex)
    , ("static.traversal", testStaticTraversal)
    , ("file.range", testFileRange)
    , ("file.range.invalid", testFileRangeInvalid)
    , ("background.tasks", testBackgroundTasks)
    ]
  for (name, test) in tests do
    runTest name test
  IO.println "[test] all tests passed"
