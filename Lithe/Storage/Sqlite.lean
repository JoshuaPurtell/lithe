import SQLite

namespace Lithe.Storage.Sqlite

/-!
First-class SQLite helpers for Lithe services.
These wrap leansqlite with a small, stable surface area.
-/

structure SqliteConfig where
  path : System.FilePath
  flags : SQLite.OpenFlags := { mode := .readWriteCreate, threading := some .fullmutex }
  busyTimeoutMs : Int32 := 5000
deriving Repr

structure SqliteDb where
  config : SqliteConfig
  db : SQLite
deriving Repr

def «open» (config : SqliteConfig) : IO SqliteDb := do
  let db ← SQLite.openWith config.path config.flags
  db.busyTimeout config.busyTimeoutMs
  pure { config, db }

def exec (db : SqliteDb) (sql : String) : IO Unit :=
  db.db.exec sql

def prepare (db : SqliteDb) (sql : String) : IO SQLite.Stmt :=
  db.db.prepare sql

def lastInsertRowId (db : SqliteDb) : IO Int64 :=
  db.db.lastInsertRowId

def changes (db : SqliteDb) : IO Int64 :=
  db.db.changes

