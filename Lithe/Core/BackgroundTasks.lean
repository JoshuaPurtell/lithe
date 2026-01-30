import Lithe.Prelude

namespace Lithe

structure BackgroundTasks where
  tasks : Array (IO Unit) := #[]

namespace BackgroundTasks

@[inline] def empty : BackgroundTasks := {}

@[inline] def add (bg : BackgroundTasks) (task : IO Unit) : BackgroundTasks :=
  { bg with tasks := bg.tasks.push task }

@[inline] def addAll (bg : BackgroundTasks) (tasks : Array (IO Unit)) : BackgroundTasks :=
  { bg with tasks := bg.tasks ++ tasks }

@[inline] def merge (a b : BackgroundTasks) : BackgroundTasks :=
  { tasks := a.tasks ++ b.tasks }

def run (bg : BackgroundTasks) : IO Unit := do
  if bg.tasks.isEmpty then
    pure ()
  else
    let _ ← IO.asTask <| do
      for task in bg.tasks do
        try
          task
        catch _ =>
          pure ()
    pure ()

end BackgroundTasks

end Lithe
