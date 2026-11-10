# cog-lisp

[![CI](https://github.com/treytomes/cog-lisp/actions/workflows/ci.yml/badge.svg)](https://github.com/treytomes/cog-lisp/actions/workflows/ci.yml)

**cog-lisp is a Scheme-like LISP that compiles to Smalltalk bytecode and runs
inside a live Pharo image**, on the same Cog virtual machine and JIT compiler that
run Smalltalk itself.

Each definition is compiled into a real `CompiledMethod`, the object Smalltalk's
own compiler makes, and the JIT turns it into machine code. Nothing walks a syntax
tree. Your procedures live in the image beside everything else: you can inspect
them, ask for their source, and save the image; when you start it again, every
definition is still there.

The reader and the compiler are written in cog-lisp, and the compiler compiles
itself. The manual, the reference and a language server for VS Code are all
generated from the documentation each definition carries in the image.

```lisp
(define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))
(display (fact 30))                                 ; 265252859812191058636308480000000

(display (map (lambda (x) (* x x)) (iota 5)))       ; (0 1 4 9 16)

(define-syntax swap!                                ; hygienic macros
  (syntax-rules ()
    ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))

(display (format #f "~a is about ~,2F" 'pi 3.14159)) ; pi is about 3.14
(display (/ 1 3))                                   ; 1/3, an exact rational
(display [3 + 4])                                   ; 7: a message sent to a Smalltalk object
(display (procedure-source fact))                   ; every procedure keeps its source
```

## What it has

- **A Scheme close to R7RS:** lexical closures, proper tail calls, `define-syntax`
  and `syntax-rules` (hygienic) as well as `define-macro`, the numeric tower
  (exact rationals, `+inf.0`, `#x` and `#e`), multiple values, `parameterize`,
  and R7RS's and SRFI 1's list procedures.
- **Conditions and restarts:** `guard`, `with-exception-handler` and
  `restart-case`. An error at the console opens a break loop inside the
  computation that failed, and offers ways to go on.
- **Smalltalk interop:** `[obj selector: arg]` sends a message, and
  `(smalltalk Dictionary)` reaches any class, so all of Pharo is within reach;
  a LISP procedure can stand in as a Smalltalk block.
- **Batteries:** Common Lisp's `format`, JSON (`json-read`, `json-write`), HTTP
  and HTTPS (`http-get`, `http-request`, with certificates always checked), file
  and string ports, and libraries to `require`: `cl` (Common Lisp names),
  `test`, `datetime`, `pretty` and `format-source`.
- **Tools:** a REPL, program arguments and exit codes, `disassemble`, code
  coverage, and a source formatter (`tools/format.lisp`).
- **A VS Code extension**, with highlighting, a REPL in the terminal, hover help
  and completion, go to definition, diagnostics as you type, macro expansion,
  Format Document, and cog-lisp's names in the spell checker. The language
  server is written in cog-lisp and served by the image.
- **Windows and Linux**, from one image.

## Installing a release

Each [release](https://github.com/treytomes/cog-lisp/releases) has a bundle for
Linux and one for Windows (x86-64), with the Pharo VM, the cog-lisp image, the
libraries and the examples. Unpack it and run `./cog-lisp.sh` (Linux) or
`cog-lisp.bat` (Windows). `INSTALL.md` in the bundle has the details. The VS Code
extension is the release's `.vsix`. HTTP and HTTPS use the system's `curl`, which
Windows includes; most Linux distributions do too.

## Getting started

Start the REPL by running `cog-lisp.bat` (or `./cog-lisp.sh`) with no arguments:

```
> (define (sq n) (* n n))
> (sq 12)
144
> (procedure-source sq)
"(define (sq n) (* n n))"
> (save-image)
```

`(save-image)` writes your definitions into the image, so they are there the next
time you start it. End a session with `(exit)`.

At a console, an error does not throw your work away: it opens a **break loop**
inside the computation that failed, and lists the ways to recover:

```
> (+ undefined-var 1)
error: unbound variable: undefined-var
restarts: use-value store-value abort
1> (use-value 41)
42
```

`(store-value 5)` would define the variable and go on; `(abort)` returns to `>`.

Run a program, with any arguments it takes:

```bat
cog-lisp.bat examples\factorial.lisp
```

A program's exit code is 0 on success, 1 on an uncaught error (reported on
stderr as `path:line:col: error: …`), or whatever it passes to `(exit n)`. The
programs in [`examples/`](examples/) are a good place to start: each is a section
of the manual.

## Documentation

- **[The manual](docs/manual/README.md)** teaches the language chapter by chapter,
  through the examples, with each one's explanation, code and checked output.
- **[The reference](docs/builtins.md)** lists every special form, derived form and
  built-in procedure, with its call form and what it does. At the REPL,
  `(documentation 'name)` answers the same.
- **Both are on the web** for the latest release, at
  **<https://treytomes.github.io/cog-lisp/>**.
- **[The VS Code extension](vscode/README.md)**: what it does, and how to build and
  install it (`build-ext.bat`, `load-ext.bat`).
- **[A skill for coding agents](.agents/skills/cog-lisp/SKILL.md)**: how to write,
  run and fix cog-lisp programs, and the traps for anyone used to another Lisp.
- **[The project plan](PROJECT-PLAN.md)**: what has been built, phase by phase,
  and what comes next.

## Building from source

On Windows, or on Linux with the `.sh` equivalent of each script
(`bootstrap-pharo.sh`, `build-image.sh`, `cog-lisp.sh`, `tests/run-all.sh`).
First download the pinned Pharo VM and the seed, then build the image:

```bat
bootstrap-pharo.bat
build-image.bat
```

Rebuild after changing anything in `src/` or in the libraries the build compiles
(`lib/core.lisp`, `lib/format.lisp`, `lib/json.lisp`, `lib/http.lisp`,
`lib/coverage.lisp`, `lib/compiler/`).

**Pinned builds.** cog-lisp builds against one exact Pharo: the Pharo 14 image
build 788 (`58e29ca31d`) and the Pharo VM v12.0.6-beta (`bebdbac`), pinned with
their SHA-256 checksums in [`pharo.pins`](pharo.pins). The image is built from a
**seed**, an earlier cog-lisp release pinned the same way: the seed's compiler
compiles the new compiler, which then compiles itself to a fixpoint.
`(image-build-info)` shows how the running image was built. If a seed is ever
lost, `scripts/rebuild-seed.sh` rebuilds it from its tagged source; CI does that
on every push.

**Tests.** Run every suite with `tests\run-all.bat` (or `tests/run-all.sh`). Most
are written in cog-lisp, in [`tests/lisp/`](tests/lisp/); the rest check what LISP
cannot check about itself, from Smalltalk and from the command line. GitHub
Actions runs them all on every push, on Linux and on Windows; pushing a tag
`vMAJOR.MINOR.PATCH` builds and publishes a release. The benchmarks
(`bench\run-benchmarks.bat`) compare compiled cog-lisp with a tree-walking
interpreter and hand-written Smalltalk ([results](bench/results.md)).

**How it is developed.** Every feature starts as a specification in
[`specs/`](specs/) with acceptance criteria, each one checked by a test, and the
code follows the spec. [`CLAUDE.md`](CLAUDE.md) holds the verified Pharo
mechanisms and the conventions the code relies on.

## Why Pharo, why bytecode

The modern Smalltalk VM is **Cog**, a JIT compiler, over **Spur**, its object
memory, from the OpenSmalltalk-VM lineage. Pharo ships its own fork of that VM,
and an image full of tools for building compilers. cog-lisp began by emitting
Opal's intermediate representation and letting Opal assemble the bytecode; its
compiler, now written in cog-lisp, writes the bytecode itself (through Pharo's
`EncoderForSistaV1`), and Cog runs it native. cog-lisp never changes the VM.

## License

cog-lisp is released under the [MIT license](LICENSE). Release bundles also carry
the Pharo image (MIT, with parts under Apache 2.0), the Pharo VM (MIT), libffi
(MIT) and, on Windows, winpthreads (MIT and BSD), each with its full license text
in the bundle's `licenses/` folder. See the
[third-party notices](release/THIRD-PARTY-NOTICES.md) and
[how the bundled files were chosen](release/licenses/README.md).
