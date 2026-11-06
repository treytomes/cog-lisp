---
name: cog-lisp
display-name: cog-lisp
description: Write, run and fix cog-lisp programs (.lisp files run by cog-lisp.sh or cog-lisp.bat), a Scheme-like LISP inside a Pharo image.
---

# cog-lisp

cog-lisp is **Scheme** (R7RS), not Common Lisp. It runs inside a Pharo
Smalltalk image and can send Smalltalk messages. Only the names in
`reference.md` (beside this file) exist; anything else is unbound.

## Run a program

Work in the cog-lisp folder: the one that holds `cog-lisp.sh` and
`cog-lisp.bat`. If you cannot find it, ask the user where cog-lisp is.

- Linux, or Git Bash on Windows: `./cog-lisp.sh program.lisp`
- Windows (cmd or PowerShell): `.\cog-lisp.bat program.lisp`

The program's output is printed. The exit code is 0 when it ran to the end.
An error stops it with exit code 1 and one line,
`file:line:column: error: message`. The position is the top-level form that
was running, so look inside that form too.

Never run `cog-lisp` without a file: that starts the REPL, which waits for
typing.

## Work in this loop

1. Write the program to a `.lisp` file.
2. Run it.
3. If there is an error, read the message, fix the form at that line, and run it
   again.
4. Unsure a name exists? Run `(display (documentation 'name))`: it prints the
   call form and what it does, or `#f` when there is no such name.

## Traps

Each one shows the wrong code, what it does, and the right code.

<!-- traps -->

## Examples

Every example below runs, and prints exactly the output shown.

<!-- example: hello -->
<!-- example: lists -->
<!-- example: helpers -->
<!-- example: loops -->
<!-- example: strings -->
<!-- example: hash-tables -->
<!-- example: errors -->
<!-- example: an-error -->
<!-- example: smalltalk -->
<!-- example: macros -->

## More

- `reference.md`, beside this file: every built-in, with its call form.
- In the cog-lisp folder: `docs/manual/` (the manual) and `examples/` (more
  programs, each with its output in a `.expected` file).
