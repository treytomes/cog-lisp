cog-lisp is a Scheme-like LISP that compiles each form to Smalltalk bytecode and
runs it inside a Pharo image, on the same just-in-time compiling VM that runs
Smalltalk. It follows R7RS closely, adds hygienic and non-hygienic macros,
conditions and restarts, and direct access to every Smalltalk object. Its reader
and compiler are written in cog-lisp, and the image builds itself.

## How to read this manual

Each chapter is a set of worked examples. Every example is a program in the
repository's `examples/` folder, and the output shown under it is checked by the
test suites on every change, so what you read is what cog-lisp does. Run any of
them yourself:

```text
./cog-lisp.sh examples/hello.lisp      (Linux, or Git Bash on Windows)
cog-lisp.bat examples\hello.lisp       (Windows)
```

The **[reference of the built-ins](../builtins.md)** lists every special form,
derived form and procedure with its call form and what it does. At the REPL,
`(documentation 'name)` answers the same text.

## Installing

A release bundle (from the project's GitHub releases) holds everything: the
Pharo VM, the cog-lisp image, the libraries, these examples and this manual.
Unpack it, and run the launcher in the unpacked folder. With no file it starts
the REPL; a file name runs that program, and anything after it is the
program's `(command-line)`.

In VS Code, the cog-lisp extension (the `.vsix` in the release) highlights
cog-lisp, runs files and the REPL, and shows each built-in's documentation when
you hover over its name.
