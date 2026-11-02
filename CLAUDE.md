# CLAUDE.md — cog-lisp

Project-specific guidance for Claude Code. Machine-level guidance lives in the
global `~/CLAUDE.md`; this file is only what is true for **this** repo.

## What this project is

An **image-based LISP** that compiles down to **Cog/Spur bytecode** and runs
JIT-native inside a Pharo image. LISP forms are compiled to `CompiledMethod`s
(via the Opal IR), installed into the image, and executed by the same VM that
runs Smalltalk — so the LISP is a first-class, persistable citizen of the image,
not an interpreter walking a tree.

- **Host dialect:** Pharo 14 (chosen for the Opal compiler / `IRBuilder`, the
  richest bytecode-generation on-ramp in the Smalltalk family).
- **VM:** OpenSmalltalk-derived **Cog + Spur** (Pharo's own VM fork), reported as
  `v12.0.6-beta`.
- **Architecture:** "Path A" — generate `CompiledMethod`s in the image and let
  Cog JIT them. We do **not** modify the VM/Slang. Exact bytecode control
  (`EncoderForSistaV1`) is a later option only if IRBuilder's abstraction gets in
  the way.

See `README.md` for the phased plan.

## Standing up the environment

The VM + image are **not** committed (see `.gitignore`). Regenerate them with:

```bat
bootstrap-pharo.bat
```

It downloads the stable 64-bit Windows VM + image into `pharo\`, extracts them,
and prints the VM and image versions. It is idempotent (cached zips are reused).

## Running Pharo headless

Use **`PharoConsole.exe`** (writes to stdout), not `Pharo.exe` (GUI, detaches):

```bat
pharo\PharoConsole.exe pharo\Pharo14.0-SNAPSHOT-64bit-58e29ca31d.image st poc\answer.st
```

`st <file>` files-in and runs a script; `eval "<expr>"` evaluates one expression
and prints its `printString`.

## Headless gotchas (learned the hard way)

- **Always end a script with `Smalltalk snapshot: false andQuit: true`.** Without
  an explicit quit the headless VM runs forever and the call hangs.
- **Print with `Stdio stdout`, not `Transcript`.** The headless Transcript is a
  `StThreadSafeTranscript` that does **not** understand `showln:`. Use:
  `Stdio stdout nextPutAll: aString; nextPut: Character lf; flush`.
- **A `.st` run via `st` is read as chunk format: double every literal `!` to
  `!!`.** A lone `!` is a chunk terminator, even inside a `'string'` or a
  `"comment"`; an un-doubled one splits the chunk mid-token (e.g. the symbol
  `set!` or a label containing it). The chunk reader turns `!!` back into `!`.
  Source files (`src/*.st`) that contain no `!` are unaffected; test files that
  mention `set!` are the usual place this bites.
- **A hung VM is killed with `taskkill /IM PharoConsole.exe /F`.** Never kill
  `Pharo.exe` — that is the user's interactive GUI image.
- **Two processes may read the same `.image` file** as long as neither saves;
  running a headless script while the GUI is open is fine.
- Scripts are run with `-I`-style isolation in mind: they must be self-contained
  and must not depend on image state from a previous run (the image is never
  saved).

## Verified Opal / IRBuilder API (Pharo 14, build 788)

Memory of this API is unreliable across versions — these were confirmed live:

- Builder class is **`OCIRBuilder`** (`IRBuilder new` returns one).
- **Finalize:** `(IRBuilder new … ; ir) compiledMethod`. Note `compiledMethod`
  is **not** on the builder — it is on the `IRMethod` returned by `ir`, and the
  cascade must be **parenthesized** (`… ; ir compiledMethod` is a *syntax error*,
  because the cascade sends `ir` and then chokes on `compiledMethod`).
- **Run a method with no install:** `m valueWithReceiver: nil arguments: #(…)`
  (defined on `CompiledMethod`, not `CompiledCode`).
- **Args + temps:** `numArgs: 2; addTemps: #(a b)` then push by **name**:
  `pushTemp: #a`. There is **no** `returnReceiver` (use `returnTop`).
- **Branching:** `jumpAheadTo: #label if: aBoolean` … `jumpAheadTarget: #label`
  (also `jumpBackTarget:` / `jumpBackTo:`). There is **no** `label:`.
- **Install into a class:** `aClass addSelectorSilently: #sel withMethod: m`.
- **Make a class:** `Object subclass: #Name` works; the old
  `subclass:instanceVariableNames:classVariableNames:package:` is **gone** in
  Pharo 14 (use the Fluid `Object << #Name …` form for a fuller definition).
- **Disassemble:** `m symbolic` returns the bytecode listing as a String.
- Smalltalk **temporaries are declared only at the top** of a method/block; a
  `| x |` in the middle is a syntax error.

## Spec-driven development

This project follows spec-driven development: **write the spec before the code.**

- Specs live in `specs/` — one document per phase/feature, each with explicit
  requirements and **acceptance criteria**.
- Every acceptance criterion should be mechanically checkable by a headless
  script, following the `poc/answer.st` convention: build, run, print
  `PASS`/`FAIL` per check, and a final `RESULT: n/n` line.
- Code changes reference the spec section they satisfy. If reality forces a
  deviation, update the spec first, then the code.
