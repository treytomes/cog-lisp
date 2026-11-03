<!-- Memory index for cog-lisp. One line per memory: - [Title](file.md) — hook.
     Memory files live beside this index. Durable project/user/feedback facts
     only; nothing the repo (code, CLAUDE.md, git history) already records. -->

- [North star vision](north-star-vision.md) — cog-lisp as a living Smalltalk-like world, eventually a body for an AI agent to grow in.
- [Phase 2 env-model decision](phase-2-env-model-decision.md) — lexical+global (locals→temps, closures→BlockClosures); why, and the escape hatch.
- [Lean on Pharo](lean-on-pharo.md) — design tenet: reuse Pharo's machinery (VM, blocks, Opal, image) rather than reinvent it.
- [Pure Lisp image goal](pure-lisp-image-goal.md) — end state needs no stock Pharo image (Phase 9); no run-time dependency on it from Phase 5 on.
- [Retain source](retain-source.md) — every compiled procedure keeps its exact source text, stored in the image.
- [Expert system goal](expert-system-goal.md) — later: forward (Rete) + backward (Prolog) chaining written in cog-lisp.
