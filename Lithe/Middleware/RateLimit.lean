import Lithe.Core.Middleware
import Lithe.Core.Context
import Lithe.Core.Error
import Lithe.Http.Response
import Lithe.Http.Request
import Lithe.Prelude

namespace Lithe

structure RatePolicy where
  burst : Nat
  refillPerSec : Nat

structure RateLimitConfig where
  onLimit : HttpError := { status := 429, code := "rate_limited", message := "rate limit exceeded" }
  includeHeaders : Bool := true
  limitHeader : String := "x-rate-limit-limit"
  remainingHeader : String := "x-rate-limit-remaining"
  resetHeader : String := "x-rate-limit-reset"
  retryAfterHeader : String := "retry-after"
  keyPrefix : String := ""
  staleAfterMs : Option Nat := some 300_000

private structure Bucket where
  tokens : Nat
  lastNanos : Nat

initialize rateLimitRef : IO.Ref (Std.HashMap String Bucket) ←
  IO.mkRef Std.HashMap.emptyWithCapacity

private def policyKey (policy : RatePolicy) : String :=
  s!"{policy.burst}:{policy.refillPerSec}"

private def resetSeconds (policy : RatePolicy) (remaining : Nat) : Nat :=
  if policy.refillPerSec == 0 then
    0
  else
    let missing := if policy.burst > remaining then policy.burst - remaining else 0
    (missing + policy.refillPerSec - 1) / policy.refillPerSec

private def applyRateHeaders
    (resp : Response)
    (policy : RatePolicy)
    (remaining : Nat)
    (resetSec : Nat)
    (cfg : RateLimitConfig)
    (includeRetry : Bool) : Response :=
  let resp := resp
    |>.withHeader cfg.limitHeader (toString policy.burst)
    |>.withHeader cfg.remainingHeader (toString remaining)
    |>.withHeader cfg.resetHeader (toString resetSec)
  if includeRetry then
    resp.withHeader cfg.retryAfterHeader (toString resetSec)
  else
    resp

private def updateBucket
    (key : String)
    (now : Nat)
    (policy : RatePolicy)
    (cfg : RateLimitConfig) : IO (Bool × Nat × Nat) := do
  let m ← rateLimitRef.get
  let staleNanos? := cfg.staleAfterMs.map (fun ms => ms * 1_000_000)
  let bucket : Bucket :=
    match m.get? key with
    | none => { tokens := policy.burst, lastNanos := now }
    | some b =>
        match staleNanos? with
        | some maxAge =>
            if now > b.lastNanos && now - b.lastNanos > maxAge then
              { tokens := policy.burst, lastNanos := now }
            else
              b
        | none => b
  let elapsed := if now > bucket.lastNanos then now - bucket.lastNanos else 0
  let refill := if policy.refillPerSec == 0 then 0 else (elapsed * policy.refillPerSec) / 1_000_000_000
  let tokens := min policy.burst (bucket.tokens + refill)
  let allowed := tokens > 0
  let remaining := if allowed then tokens - 1 else 0
  let bucket' : Bucket := { tokens := remaining, lastNanos := now }
  rateLimitRef.set (m.insert key bucket')
  let resetSec := resetSeconds policy remaining
  pure (allowed, remaining, resetSec)

/--
Rate limit middleware using a token bucket per key.
- `keyFn` should return a stable string per client (e.g., IP, API key).
- `burst` is the max tokens.
- `refillPerSec` is tokens added per second.
-/
def rateLimit (keyFn : RequestCtx → IO String) (policy : RatePolicy) (cfg : RateLimitConfig := {}) : Middleware :=
  fun h ctx => do
    let baseKey ← keyFn ctx
    let key := s!"{cfg.keyPrefix}|{policyKey policy}|{baseKey}"
    let now ← IO.monoNanosNow
    let (allowed, remaining, resetSec) ← updateBucket key now policy cfg
    if allowed then
      let resp ← h ctx
      if cfg.includeHeaders then
        pure (applyRateHeaders resp policy remaining resetSec cfg false)
      else
        pure resp
    else
      let err := cfg.onLimit
      let resp := (Response.json (HttpError.toJson err)).withStatus err.status
      if cfg.includeHeaders then
        pure (applyRateHeaders resp policy remaining resetSec cfg true)
      else
        pure resp

@[inline] def rateLimitByRemote (policy : RatePolicy) (cfg : RateLimitConfig := {}) : Middleware :=
  rateLimit (fun ctx => pure (ctx.req.remote.getD "unknown")) policy cfg

@[inline] def rateLimitByHeader (header : String) (policy : RatePolicy) (cfg : RateLimitConfig := {}) : Middleware :=
  rateLimit (fun ctx => pure (ctx.req.header? header |>.getD "unknown")) policy cfg

@[inline] def rateLimitByKey (key : String) (policy : RatePolicy) (cfg : RateLimitConfig := {}) : Middleware :=
  rateLimit (fun _ => pure key) policy cfg

end Lithe
