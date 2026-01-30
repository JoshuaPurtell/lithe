import Lake
open Lake DSL

package lithe where
  version := v!"0.1.0"

require std from git "https://github.com/leanprover/std4" @ "v4.27.0"
require SQLite from git "https://github.com/leanprover/leansqlite" @ "main"

@[default_target]
lean_lib Lithe

lean_lib Tests where
  srcDir := "tests"

lean_exe lithe_tests where
  root := `Tests.Main
  srcDir := "tests"
