<!-- Memory index for cog-lisp. One line per memory: - [Title](file.md) — hook.
     Memory files live beside this index. Durable project/user/feedback facts
     only; nothing the repo (code, CLAUDE.md, git history) already records. -->

- [North star vision](north-star-vision.md) — the image as an AI agent's body: LISP substrate, then the expert system, the model on top; local-assist's principles.
- [Phase 2 env-model decision](phase-2-env-model-decision.md) — lexical+global (locals→temps, closures→BlockClosures); why, and the escape hatch.
- [Lean on Pharo](lean-on-pharo.md) — design tenet: reuse Pharo's machinery (VM, blocks, Opal, image) rather than reinvent it.
- [Pure Lisp image goal](pure-lisp-image-goal.md) — no stock Pharo image; Phase 9 = language, Phase 11 = pure image (long); runtime in LISP; networking/graphics kept; complex numbers as a library.
- [Retain source](retain-source.md) — every compiled procedure keeps its exact source text, stored in the image.
- [Expert system goal](expert-system-goal.md) — later: forward (Rete) + backward (Prolog) chaining written in cog-lisp.
- [Examples become the manual](examples-become-manual.md) — keep one checked example per feature; they will form the user manual.
- [Skill eval model](skill-eval-model.md) — measure the agent skill with Ministral 3 8B reasoning on rojo, via Bionic private link.
- [Reuse lisp-expert code](reuse-lisp-expert.md) — build cog-lisp features (format, JSON) from lisp-expert's code, not from scratch.
