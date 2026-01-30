import Lithe.Middleware.Metrics
import Std.Data.HashMap
import Lean.Data.Json

namespace Lithe

structure MetricsSnapshot where
  total : Nat
  totalMs : Nat
  maxMs : Nat
  totalBytes : Nat
  byStatus : Std.HashMap Nat Nat
  byErrorCode : Std.HashMap String Nat

namespace MetricsSnapshot

@[inline] def empty : MetricsSnapshot :=
  { total := 0
  , totalMs := 0
  , maxMs := 0
  , totalBytes := 0
  , byStatus := Std.HashMap.emptyWithCapacity
  , byErrorCode := Std.HashMap.emptyWithCapacity
  }

private def incNat (m : Std.HashMap Nat Nat) (k : Nat) : Std.HashMap Nat Nat :=
  let v := m.getD k 0
  m.insert k (v + 1)

private def incStr (m : Std.HashMap String Nat) (k : String) : Std.HashMap String Nat :=
  let v := m.getD k 0
  m.insert k (v + 1)

@[inline] def record (s : MetricsSnapshot) (e : MetricsEvent) : MetricsSnapshot :=
  let total := s.total + 1
  let totalMs := s.totalMs + e.durationMs
  let maxMs := if e.durationMs > s.maxMs then e.durationMs else s.maxMs
  let totalBytes := s.totalBytes + (e.responseBytes.getD 0)
  let byStatus := incNat s.byStatus e.status
  let byErrorCode :=
    match e.errorCode with
    | some code => incStr s.byErrorCode code
    | none => s.byErrorCode
  { total := total
  , totalMs := totalMs
  , maxMs := maxMs
  , totalBytes := totalBytes
  , byStatus := byStatus
  , byErrorCode := byErrorCode
  }

private def mapToJson (m : Std.HashMap String Nat) : Lean.Json :=
  let fields := m.toList.map (fun (k, v) => (k, (toString v : Lean.Json)))
  Lean.Json.mkObj fields

private def mapNatToJson (m : Std.HashMap Nat Nat) : Lean.Json :=
  let fields := m.toList.map (fun (k, v) => (toString k, (toString v : Lean.Json)))
  Lean.Json.mkObj fields

@[inline] def toJson (s : MetricsSnapshot) : Lean.Json :=
  let avg := if s.total == 0 then 0 else s.totalMs / s.total
  let base : List (String × Lean.Json) :=
    [ ("total", (toString s.total : Lean.Json))
    , ("total_ms", (toString s.totalMs : Lean.Json))
    , ("avg_ms", (toString avg : Lean.Json))
    , ("max_ms", (toString s.maxMs : Lean.Json))
    , ("total_bytes", (toString s.totalBytes : Lean.Json))
    , ("by_status", mapNatToJson s.byStatus)
    , ("by_error_code", mapToJson s.byErrorCode)
    ]
  Lean.Json.mkObj base

end MetricsSnapshot

structure MetricsStore where
  ref : IO.Ref MetricsSnapshot

namespace MetricsStore

@[inline] def new : IO MetricsStore := do
  let ref ← IO.mkRef MetricsSnapshot.empty
  pure { ref := ref }

@[inline] def record (store : MetricsStore) (e : MetricsEvent) : IO Unit :=
  store.ref.modify (fun s => s.record e)

@[inline] def snapshot (store : MetricsStore) : IO MetricsSnapshot :=
  store.ref.get

@[inline] def middleware (store : MetricsStore) (cfg : MetricsConfig := {}) : Middleware :=
  metrics { cfg with onResult := fun e => store.record e }

end MetricsStore

end Lithe
