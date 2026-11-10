# Installing cog-lisp

cog-lisp is an image-based LISP that runs on the Pharo virtual machine. This
bundle has everything it needs: the Pharo VM for your platform, the cog-lisp
image, the LISP library (`lib/`) and the examples (`examples/`). Nothing else
needs installing, except for one thing on Linux: HTTP and HTTPS (`http-get`,
`http-request`) use the system's `curl`, which most distributions include
(`apt install curl` if yours does not). Windows has its own.

## Linux (x86-64)

```sh
tar -xzf cog-lisp-VERSION-linux-x86_64.tar.gz
cd cog-lisp-VERSION
./cog-lisp.sh                          # the REPL; end it with (exit) or Ctrl+D
./cog-lisp.sh examples/hello.lisp      # run a program
```

## Windows (x86-64)

Unzip `cog-lisp-VERSION-windows-x86_64.zip`, then in a console (Windows
Terminal, PowerShell, or cmd) in the unzipped folder:

```bat
cog-lisp.bat                           & rem the REPL; end it with (exit) or Ctrl+Z, Enter
cog-lisp.bat examples\hello.lisp       & rem run a program
```

`cog-lisp.sh` works too, from Git Bash in a console terminal.

## Running programs

`cog-lisp program.lisp arg ...` runs a program and exits: 0 on success, 1 on an
uncaught error (reported as `path:line:col: error: message`), or the number given
to `(exit n)`. `(command-line)` answers the program and its arguments.

The `examples/` folder has one runnable example per feature, each with the
output it prints (`.expected`). The libraries in `lib/` load from any folder
with `(require 'name)`: `cl` (Common Lisp names), `test`, `datetime`, `pretty`
and `format-source`; `format`, JSON and HTTP are built in.

## VS Code

Install the extension from `cog-lisp-VERSION.vsix` (Extensions view, `...` menu,
*Install from VSIX...*), then open this folder. *cog-lisp: Run File* (the ▷
button) runs the file you are editing, errors show in *Problems*, and
*cog-lisp: Start REPL* opens the REPL in a terminal. Hover over a name for its
documentation; the image serves a language server for completion, *Go to
Definition*, errors as you type, *cog-lisp: Expand Macro* and *Format
Document*.

## Documentation

The documentation of the latest release is also on the web, at
<https://treytomes.github.io/cog-lisp/>.

`docs/manual/README.md` is the manual: the language chapter by chapter, through
the examples in `examples/`. `docs/builtins.md` lists every built-in with its
call form and what it does; at the REPL, `(documentation 'name)` answers the
same.

## AI agents (a skill)

`.agents/skills/cog-lisp/` is a skill: instructions an AI agent reads when a task
is about cog-lisp. They cover how to run programs and read their errors, the
mistakes a model used to other Lisps makes, and checked examples, with a terse
list of every built-in beside them. It is written for small local models.

In Bionic (LM Studio's agent app), either:
- open this folder as a project, and the skill is active there; or
- ask Bionic's agent to install the skill from `cog-lisp-skill-VERSION.zip` (a
  release download) or from the `.agents/skills/cog-lisp` folder, for every
  project.

Other agent tools that read `SKILL.md` skills can use the same folder.

## Licenses

cog-lisp is released under the MIT license (`LICENSE`). See
`THIRD-PARTY-NOTICES.md` for the Pharo image, the Pharo VM and the libraries
this bundle includes; their license texts are in `licenses/`.
