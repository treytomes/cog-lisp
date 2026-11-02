---
name: north-star-vision
description: The project's ultimate goal — a LISP that feels like a Smalltalk world and can serve as the body for an AI agent to grow inside.
metadata:
  type: project
---

cog-lisp's north star (stated by the user 2026-11-02): a LISP **world** that
*feels* like a Smalltalk world — live, reflective, object-everything,
modifiable and persistent at runtime — and that can eventually serve as **the
body for an AI agent to grow inside of**.

**Why it matters:** this reframes cog-lisp from "a LISP that is fast" to "a LISP
that is a living habitat." Design decisions should be weighed against *liveness,
reflection, and persistence*, not only performance.

**How to apply:**
- Prefer designs where LISP definitions are first-class, inspectable, live image
  residents (compiling functions to real `CompiledMethod`s already serves this —
  it is more Smalltalk-like than a tree-walking interpreter, not less).
- Treat the image's persistence as a feature of the agent's "memory/body," not an
  implementation detail: accumulated definitions and state should survive a save.
- The [[phase-2-env-model-decision]] (lexical + global, locals→temps,
  closures→BlockClosures) was chosen for native speed, but the one thing it trades
  away — first-class runtime environments for reflection/`eval` — is recoverable
  **additively** later (the "Hybrid" option / Phase 7 reach) without changing how
  normal code compiles. Keep that escape hatch open when shaping Phases 3–4.
- Self-hosting (Phase 8) and rich reflection are not side-quests; they are
  directly in service of an agent that can read and rewrite its own body.
