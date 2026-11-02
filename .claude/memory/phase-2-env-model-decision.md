---
name: phase-2-env-model-decision
description: Why cog-lisp uses the lexical+global variable model (locals as Smalltalk temps, closures as BlockClosures, only the global env at runtime).
metadata:
  type: project
---

Phase 2 settled the variable/environment model as **lexical + global table**
(owner decision, 2026-11-02):
- Local/lambda variables compile to Smalltalk method temporaries and arguments.
- Closures become Smalltalk `BlockClosure`s.
- The only environment that exists at run time is the **global** one
  (`LispEnvironment`), holding top-level `define`s.

**Why:** it keeps variable access at native/JIT speed, which is the whole point
of the compile-to-bytecode architecture; a runtime frame-chain would add
indirection that fights that goal.

**How to apply:**
- Phase 3 emits temp/argument access for locals and `LispEnvironment` access for
  globals; the compile-time *lexical contour* (name → slot) is a Phase 3 compiler
  concern, not a runtime structure.
- The trade-off is no first-class runtime environments. This is acceptable because
  (a) `eval` of fresh code can invoke the compiler we already have, and (b)
  first-class environments can be added **additively** later (the "Hybrid"
  option) if the [[north-star-vision]] agent-body needs runtime scope reflection,
  without disturbing how ordinary code compiles. Do not quietly abandon that
  escape hatch.
