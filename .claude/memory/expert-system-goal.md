---
name: expert-system-goal
description: "Owner wants to build an expert system in cog-lisp later — forward chaining (NRules/CLIPS, Rete) and backward chaining (Prolog-style)."
metadata:
  node_type: memory
  type: project
  originSessionId: 5dcb1131-e89e-4241-a508-976cd71439d3
  modified: 2026-11-03T21:52:45.404Z
---

After the language phases, the owner wants to build an expert system *in* cog-lisp together: forward chaining in the NRules/CLIPS style (working memory, Rete matching) and backward chaining in the Prolog style (unification, backtracking). Raised 2026-11-03; tracked in README "Later: an expert system in cog-lisp".

**Why:** a first large program written in the language, and a natural fit for the image-as-knowledge-base and agent-body vision [[north-star-vision]].

**How to apply:** when designing 7.8 (hash tables, vectors), conditions/restarts, and macros, keep rule-engine needs in mind (fact indexing, fast matching, rule DSL macros). The ANSI Common Lisp book's inference chapter (the owner is working through it) is a good starting point for the backward chainer.
