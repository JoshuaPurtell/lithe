import Lake
open Lake DSL

package kitchen_sink where

require lithe from "../.."

@[default_target]
lean_lib KitchenSink
