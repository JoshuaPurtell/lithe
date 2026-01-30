# Making Lithe's Lean Basis Shine: Verification & Property-Based Testing

## Overview

Lithe is unique among web frameworks: it's written in **Lean 4**, a theorem prover and programming language. This gives us capabilities that no other web framework has:

- ✅ **Formal Verification**: Prove properties about routing, middleware, security
- ✅ **Property-Based Testing**: Generate test cases automatically
- ✅ **Type Safety**: Stronger guarantees than Rust/Go/TypeScript
- ✅ **Mathematical Proofs**: Guarantee correctness, not just "tested"
- ✅ **Dependent Types**: Express invariants in types

## Why This Matters

Most web frameworks rely on:
- Unit tests (cover specific cases)
- Integration tests (test happy paths)
- Manual code review

**Lithe can do better:**
- Prove properties hold for ALL inputs
- Generate test cases automatically
- Catch bugs at compile time
- Provide mathematical guarantees

## Verification Opportunities

### 1. Router Properties

**Properties to Prove:**

```lean
-- Route matching is deterministic
theorem route_match_deterministic (r : Router) (req : Request) :
  ∃! (h : Handler), matches r req h

-- Route priority (first match wins)
theorem route_priority (r : Router) (req : Request) :
  let routes := r.routes.filter (fun route => route.matches req)
  routes.length > 0 → matches r req routes[0].handler

-- Fallback only when no match
theorem fallback_only_when_no_match (r : Router) (req : Request) :
  matches r req r.fallback ↔ (∀ route ∈ r.routes, ¬route.matches req)

-- Path parameter extraction is safe
theorem path_param_safe (pattern : RoutePattern) (path : String) :
  match pattern.match path with
  | some params => params.keys ⊆ pattern.params
  | none => True

-- No duplicate routes (same method + path)
theorem no_duplicate_routes (r : Router) :
  ∀ r1 r2 ∈ r.routes, r1 ≠ r2 → 
    r1.method ≠ r2.method ∨ r1.pattern ≠ r2.pattern
```

**Property-Based Testing:**

```lean
-- Generate random routers and requests, verify properties
def test_router_properties : IO Unit := do
  let rng ← IO.stdGenRef.get
  for _ in [0:1000] do
    let (router, rng') := generateRouter rng
    let (request, rng'') := generateRequest rng'
    -- Verify deterministic matching
    assert (route_match_deterministic router request)
    IO.stdGenRef.set rng''
```

### 2. Middleware Properties

**Properties to Prove:**

```lean
-- Middleware composition is associative
theorem middleware_associative (m1 m2 m3 : Middleware) (h : Handler) :
  (m1.compose m2).compose m3 h = m1.compose (m2.compose m3) h

-- Identity middleware does nothing
theorem middleware_identity (h : Handler) :
  Middleware.identity h = h

-- Middleware stack order matters (last applied first)
theorem middleware_stack_order (mws : Array Middleware) (h : Handler) :
  Middleware.stack mws h = mws.foldr (fun m acc => m acc) h

-- Middleware preserves error handling
theorem middleware_preserves_errors (m : Middleware) (h : Handler) (ctx : RequestCtx) :
  let h' := m h
  match h ctx with
  | .error e => ∃ e', h' ctx = .error e'
  | .ok _ => True

-- Auth middleware enforces authentication
theorem auth_middleware_enforces (m : Middleware.Auth) (h : Handler) (ctx : RequestCtx) :
  ctx.auth.isNone → (m h) ctx = .error (HttpError.unauthorized "Authentication required")
```

**Property-Based Testing:**

```lean
-- Generate random middleware stacks, verify composition properties
def test_middleware_properties : IO Unit := do
  let rng ← IO.stdGenRef.get
  for _ in [0:1000] do
    let (mws, rng') := generateMiddlewareStack rng
    let (handler, rng'') := generateHandler rng'
    -- Verify associativity
    assert (middleware_associative mws[0] mws[1] mws[2] handler)
    IO.stdGenRef.set rng''
```

### 3. Security Properties

**Properties to Prove:**

```lean
-- CSRF protection works
theorem csrf_protection (m : Middleware.CSRF) (req : Request) :
  req.method = Method.POST →
    (req.hasValidCSRFToken ∨ req.isSafeMethod) →
      m.blocks req = false

-- Rate limiting prevents abuse
theorem rate_limit_enforced (m : Middleware.RateLimit) (reqs : List Request) :
  let (allowed, blocked) := m.process reqs
  blocked.length ≤ reqs.length ∧
  (∀ req ∈ blocked, m.isRateLimited req)

-- Auth scopes are enforced
theorem scope_enforcement (extractor : Extractor.requireScope) (ctx : RequestCtx) :
  ctx.auth.isSome →
    (extractor.requiredScope ∈ ctx.auth.get.scopes) →
      extractor.extract ctx = .ok ctx.auth.get

-- CORS headers are correct
theorem cors_headers_correct (m : Middleware.CORS) (req : Request) (resp : Response) :
  m.apply req resp →
    resp.hasHeader "access-control-allow-origin" →
      resp.header "access-control-allow-origin" = m.allowedOrigin req
```

### 4. Streaming Properties

**Properties to Prove:**

```lean
-- Stream chunks are non-empty (except last)
theorem stream_chunks_nonempty (stream : BodyStream) :
  ∀ chunk, chunk ∈ stream.chunks → chunk.length > 0 ∨ chunk.isLast

-- Stream cancellation works
theorem stream_cancellation (stream : BodyStream) (cancel : CancelToken) :
  cancel.isCanceled →
    stream.withCancel cancel = .error (HttpError.canceled)

-- Stream backpressure prevents overflow
theorem stream_backpressure (q : StreamQueue) (capacity : Nat) :
  q.length ≤ capacity

-- SSE events are properly formatted
theorem sse_event_format (event : SSEEvent) :
  SSEEvent.format event.endsWith "\n\n" ∧
  SSEEvent.format event.contains "data:"
```

### 5. Serialization Properties

**Properties to Prove:**

```lean
-- JSON encoding/decoding roundtrip
theorem json_roundtrip (j : Json) :
  Json.decode (Json.encode j) = .ok j

-- Wire protocol roundtrip
theorem wire_roundtrip (req : Request) :
  WireRequest.toRequest (WireRequest.ofRequest req) = req

-- Header encoding preserves semantics
theorem header_encoding (headers : Headers) :
  Headers.decode (Headers.encode headers) = .ok headers
```

### 6. Performance Properties

**Properties to Prove:**

```lean
-- Router lookup is O(n) where n = number of routes
theorem router_lookup_complexity (r : Router) (req : Request) :
  router_lookup_steps r req ≤ r.routes.length

-- Middleware stack application is O(m) where m = middleware count
theorem middleware_stack_complexity (mws : Array Middleware) (h : Handler) :
  middleware_apply_steps mws h ≤ mws.length

-- No memory leaks in streaming
theorem stream_memory_bounded (stream : BodyStream) (maxChunks : Nat) :
  stream.chunks.length ≤ maxChunks →
    stream.memoryUsage ≤ maxChunks * maxChunkSize
```

## Implementation Plan

### Phase 1: Property-Based Testing Infrastructure (Week 1)

**Goal**: Build generators for random test data

**Tasks:**

1. **Create `Lithe/Test/Generators.lean`**
   ```lean
   -- Generate random routers
   def generateRouter (rng : StdGen) : Router × StdGen
   
   -- Generate random requests
   def generateRequest (rng : StdGen) : Request × StdGen
   
   -- Generate random middleware stacks
   def generateMiddlewareStack (rng : StdGen) : Array Middleware × StdGen
   
   -- Generate random handlers
   def generateHandler (rng : StdGen) : Handler × StdGen
   ```

2. **Create `Lithe/Test/Properties.lean`**
   ```lean
   -- Property-based test runner
   def checkProperty (prop : Prop) (generator : Generator α) (trials : Nat) : IO Bool
   
   -- QuickCheck-style testing
   def quickCheck (prop : α → Prop) (generator : Generator α) : IO Unit
   ```

3. **Create example property tests**
   - Router properties
   - Middleware properties
   - Basic security properties

**Deliverables:**
- ✅ Generator infrastructure
- ✅ Property test runner
- ✅ Example tests

### Phase 2: Formal Verification (Week 2-3)

**Goal**: Prove key properties formally

**Tasks:**

1. **Router Verification**
   - Prove route matching is deterministic
   - Prove fallback behavior
   - Prove path parameter safety

2. **Middleware Verification**
   - Prove composition properties
   - Prove identity laws
   - Prove error preservation

3. **Security Verification**
   - Prove CSRF protection
   - Prove rate limiting
   - Prove auth enforcement

**Deliverables:**
- ✅ Formal proofs for core properties
- ✅ Documentation of proven properties
- ✅ Proof examples

### Phase 3: Integration & Documentation (Week 4)

**Goal**: Make verification accessible

**Tasks:**

1. **Documentation**
   - Guide to property-based testing
   - Guide to formal verification
   - List of proven properties

2. **Examples**
   - Property-based test examples
   - Proof examples
   - Verification workflow

3. **CI Integration**
   - Run property tests in CI
   - Verify proofs compile
   - Generate verification reports

**Deliverables:**
- ✅ Complete documentation
- ✅ Working examples
- ✅ CI integration

## Example: Router Verification

```lean
import Lithe.Router.Router
import Lithe.Test.Generators

namespace Lithe.Router

-- Property: Route matching is deterministic
theorem route_match_deterministic (r : Router) (req : Request) :
  ∃! (h : Handler), matches r req h := by
  -- Proof: Router.match returns exactly one handler
  -- Either a route matches (first one wins) or fallback is used
  sorry  -- TODO: Formal proof

-- Property: First match wins
theorem first_match_wins (r : Router) (req : Request) :
  let matching := r.routes.filter (fun route => route.pattern.matches req.path)
  matching.length > 0 →
    matches r req matching[0].handler := by
  -- Proof: Router.match iterates routes in order, returns first match
  sorry  -- TODO: Formal proof

-- Property-based test
def test_route_matching : IO Unit := do
  let rng ← IO.stdGenRef.get
  for _ in [0:10000] do
    let (router, rng') := generateRouter rng
    let (request, rng'') := generateRequest rng'
    -- Verify deterministic matching
    let handlers := router.match request
    assert (handlers.length ≤ 1) "Route matching should be deterministic"
    IO.stdGenRef.set rng''

end Lithe.Router
```

## Example: Middleware Verification

```lean
import Lithe.Core.Middleware

namespace Lithe.Middleware

-- Property: Composition is associative
theorem composition_associative (m1 m2 m3 : Middleware) (h : Handler) :
  (m1.compose m2).compose m3 h = m1.compose (m2.compose m3) h := by
  -- Proof: Function composition is associative
  simp [compose]
  rfl

-- Property: Identity does nothing
theorem identity_law (h : Handler) :
  identity h = h := by
  -- Proof: Identity function
  simp [identity]

-- Property-based test
def test_middleware_composition : IO Unit := do
  let rng ← IO.stdGenRef.get
  for _ in [0:1000] do
    let (mws, rng') := generateMiddlewareStack rng
    let (handler, rng'') := generateHandler rng'
    -- Verify associativity
    if mws.length ≥ 3 then
      let m1 := mws[0]
      let m2 := mws[1]
      let m3 := mws[2]
      let left := (m1.compose m2).compose m3 handler
      let right := m1.compose (m2.compose m3) handler
      assert (left = right) "Middleware composition should be associative"
    IO.stdGenRef.set rng''

end Lithe.Middleware
```

## Benefits

### For Developers

1. **Confidence**: Know your code is correct, not just "tested"
2. **Documentation**: Properties serve as executable specifications
3. **Refactoring**: Change code knowing properties still hold
4. **Debugging**: Properties help identify where bugs are

### For Users

1. **Reliability**: Mathematical guarantees, not just "we tested it"
2. **Security**: Proven security properties
3. **Performance**: Proven complexity bounds
4. **Correctness**: Properties hold for ALL inputs, not just test cases

### For Lithe

1. **Differentiation**: No other web framework has formal verification
2. **Marketing**: "Mathematically proven web framework"
3. **Quality**: Catch bugs before they reach production
4. **Research**: Contribute to verified systems research

## Comparison with Other Frameworks

| Framework | Testing | Verification | Property Testing |
|-----------|---------|--------------|------------------|
| Express.js | ✅ Unit tests | ❌ None | ❌ None |
| Axum | ✅ Unit tests | ❌ None | ❌ None |
| FastAPI | ✅ Unit tests | ❌ None | ❌ None |
| **Lithe** | ✅ Unit tests | ✅ **Formal proofs** | ✅ **Property-based** |

## Next Steps

1. ✅ Plan created
2. ⏳ Implement property-based testing infrastructure
3. ⏳ Write first property tests
4. ⏳ Prove first properties formally
5. ⏳ Document and share

## Resources

- [Lean 4 Documentation](https://leanprover.github.io/lean4/doc/)
- [Property-Based Testing](https://en.wikipedia.org/wiki/Property-based_testing)
- [Formal Verification](https://en.wikipedia.org/wiki/Formal_verification)
- [QuickCheck Paper](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf)
