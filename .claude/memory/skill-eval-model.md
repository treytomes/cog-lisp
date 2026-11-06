---
name: skill-eval-model
description: "Evaluate the cog-lisp agent skill with Ministral 3 8B (reasoning) on the rojo machine, via Bionic's private link."
metadata:
  node_type: memory
  type: project
  originSessionId: 5dcb1131-e89e-4241-a508-976cd71439d3
  modified: 2026-11-06T20:26:36.201Z
---

The cog-lisp agent skill (Phase 10 step 10.7, `tools/skill-eval.js`) is measured
with the **Ministral 3 8B reasoning model**, served from the **`rojo`** desktop
(CUDA, much faster) through **Bionic's private link**. Not the 3B model the owner
first tried, and not a model loaded on this laptop. (Owner, 2026-11-06.)

**Why:** rojo has a GPU; runs there are much faster than on this laptop.

**How to apply:** when running the skill evaluation, point it at the endpoint and
model id the private link exposes (ask the owner for them if they are not known),
and record that model's name with the results. See [[north-star-vision]].
