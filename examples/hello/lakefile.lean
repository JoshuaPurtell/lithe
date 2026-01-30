import Lake
open Lake DSL

package hello where

require lithe from "../.."

@[default_target]
lean_lib Hello
