import Lithe.Prelude
import Lithe.Test.Generators

namespace Lithe

abbrev Property (α : Type) := α → Bool

structure CheckResult (α : Type) where
  success : Bool
  counterexample : Option α := none
  seed : Nat := 0
  size : Nat := 0

def checkProperty
  (prop : Property α)
  (gen : Generator α)
  (trials : Nat := 100)
  (seed : Nat := 0)
  : IO (CheckResult α) := do
  let rec loop (i : Nat) (currentSeed : Nat) : IO (CheckResult α) := do
    if i ≥ trials then
      return { success := true }
    else
      let size := i + 1
      let (value, nextSeed) := gen.run currentSeed size
      if prop value then
        loop (i + 1) nextSeed
      else
        return { success := false, counterexample := some value, seed := currentSeed, size := size }
  loop 0 seed

def checkPropertyProp
  (prop : α → Prop)
  [DecidablePred prop]
  (gen : Generator α)
  (trials : Nat := 100)
  (seed : Nat := 0)
  : IO (CheckResult α) :=
  checkProperty (fun a => decide (prop a)) gen trials seed

def quickCheck
  (prop : Property α)
  (gen : Generator α)
  (trials : Nat := 100)
  (seed : Nat := 0)
  [Repr α]
  : IO Unit := do
  let result ← checkProperty prop gen trials seed
  if result.success then
    pure ()
  else
    let detail :=
      match result.counterexample with
      | some value => s!" counterexample: {repr value}"
      | none => ""
    throw (IO.userError s!"Property failed (seed={result.seed}, size={result.size}).{detail}")

def quickCheckProp
  (prop : α → Prop)
  [DecidablePred prop]
  (gen : Generator α)
  (trials : Nat := 100)
  (seed : Nat := 0)
  [Repr α]
  : IO Unit := do
  let result ← checkPropertyProp prop gen trials seed
  if result.success then
    pure ()
  else
    let detail :=
      match result.counterexample with
      | some value => s!" counterexample: {repr value}"
      | none => ""
    throw (IO.userError s!"Property failed (seed={result.seed}, size={result.size}).{detail}")

end Lithe
