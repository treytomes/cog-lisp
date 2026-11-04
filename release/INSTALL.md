# Installing cog-lisp

cog-lisp is an image-based LISP that runs on the Pharo virtual machine. This
bundle has everything it needs: the Pharo VM for your platform, the cog-lisp
image, the LISP library (`lib/`) and the examples (`examples/`). Nothing else
needs installing.

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
output it prints (`.expected`).

## VS Code

Install the extension from `cog-lisp-VERSION.vsix` (Extensions view, `...` menu,
*Install from VSIX...*), then open this folder. *cog-lisp: Run File* (the ▷
button) runs the file you are editing, errors show in *Problems*, and
*cog-lisp: Start REPL* opens the REPL in a terminal.

## Licenses

See `THIRD-PARTY-NOTICES.md` for the Pharo VM and image this bundle includes.
