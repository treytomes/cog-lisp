---
name: cog-lisp
display-name: cog-lisp
description: Write, run and fix cog-lisp programs (.lisp files run by cog-lisp.sh or cog-lisp.bat), a Scheme-like LISP inside a Pharo image.
---

# cog-lisp

cog-lisp is **Scheme** (R7RS), not Common Lisp. It runs inside a Pharo
Smalltalk image and can send Smalltalk messages. Only the names in
`reference.md` (beside this file) exist, a library's once it is required;
anything else is unbound.

**Always answer with a program that prints the result.** Asked to print the
squares of 1 to 3, write `(display (map (lambda (n) (* n n)) (list 1 2 3)))`,
never `(1 4 9)`: data written as code is a call, and fails.

## Run a program

`cog-lisp.sh` and `cog-lisp.bat` are in the cog-lisp folder, and run a program
from any folder; if you cannot find them, ask the user.

- Linux, or Git Bash on Windows: `./cog-lisp.sh program.lisp`
- Windows (cmd or PowerShell): `.\cog-lisp.bat program.lisp`

The program's output is printed. The exit code is 0 when it ran to the end.
An error stops it with exit code 1 and one line,
`file:line:column: error: message`. The position is the top-level form that
was running, so look inside that form too.

Never run `cog-lisp` without a file: its REPL waits for typing.

## Work in this loop

1. Write the program to a `.lisp` file.
2. Run it.
3. If there is an error, read the message, fix the form at that line, and run it
   again.
4. Unsure a name exists? Run `(display (documentation 'name))`: it prints the
   call form and what it does, or `#f` when there is no such name.

Have a `lisp_check` tool? Read `mcp.md` beside this file first.
Testing a program's prompts at a console? Read `console.md`.

## Traps

These hold for plain cog-lisp. `(require 'cl)` adds Common Lisp's `defun`,
`nil`, `first`, `last` and more (reference.md, under cl); its `last` answers
the last pair: `(last (list 1 2 3))` is `(3)`.

<!-- traps -->

## Examples

Each runs, and prints exactly what is shown.

<!-- example: hello -->
<!-- example: lists -->
<!-- example: list-tools -->
<!-- example: loops -->
<!-- example: strings -->
<!-- example: format -->
<!-- example: hash-tables -->
<!-- example: errors -->
<!-- example: an-error -->
<!-- example: smalltalk -->
<!-- example: macros -->

## More

`reference.md` (beside this file) lists every built-in, and each library's names. The cog-lisp folder
also has the manual (`docs/manual/`) and more programs (`examples/`).
