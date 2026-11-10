;;; chapters.lisp -- the chapters of the cog-lisp manual, in order
;;; (specs/16-phase-10-documentation-and-editor.md step 10.4)
;;;
;;; (chapter slug title introduction example ...): each example is a file of
;;; examples/ (without .lisp) or a folder of them, shown with its explanation, its
;;; code and the output the test suites check. An example without an .expected
;;; file (a library another example loads) is shown as code alone. Every example
;;; is in a chapter. tools/generate-docs.lisp writes the manual from this list.

(chapter "getting-started" "Getting started"
  "A cog-lisp program is a file of forms, run from top to bottom by the cog-lisp
launcher: `./cog-lisp.sh hello.lisp` on Linux, `cog-lisp.bat hello.lisp` on
Windows. With no file, the launcher starts the REPL."
  "hello" "factorial")

(chapter "lists-and-procedures" "Lists and procedures"
  "Lists are made of pairs, and procedures are values that keep the variables
they were made with."
  "lists" "places" "closures")

(chapter "numbers" "Numbers"
  "Exact integers of any size, exact rationals, and inexact reals, with the
procedures of R7RS."
  "numbers")

(chapter "text-and-vectors" "Strings, characters and vectors"
  "Strings are mutable sequences of Unicode characters; vectors are fixed-size,
indexed sequences of anything."
  "strings" "escapes" "format" "vectors")

(chapter "hash-tables" "Hash tables"
  "Tables from keys to values, compared with eq?, eqv? or equal?."
  "hash-tables")

(chapter "input-and-output" "Input and output"
  "Ports read and write strings, files, and the standard streams; a program can be
spread over several files, and can load cog-lisp's own libraries from anywhere;
JSON is read and written, and pages fetched over HTTP and HTTPS."
  "string-ports" "files" "echo" "program" "libraries" "json" "http")

(chapter "console" "The console"
  "The console library, (require 'console), writes styled text with the colors a
terminal has and none to a pipe, measures and wraps it in cells, reads keys as
events, lays text out in rules, panels, tables and trees, asks questions and
offers choices, and tests what a program draws on a pretend terminal."
  "console" "console-renderables" "console-prompts")

(chapter "namespaces" "Libraries and namespaces"
  "A library exports some of its names and keeps the rest; each file chooses how
to bring them in: unqualified, under a prefix, or a few under other names. Names
from different libraries never collide, and a full name such as shapes:area
always works."
  "namespaces" "namespaces-prefix" "namespaces-choose" "namespaces-private"
  "namespaces-files" "namespaces-conflicts")

(chapter "errors" "Errors, conditions and restarts"
  "Errors are conditions that handlers catch; restarts let a handler choose how to
go on without unwinding first."
  "conditions-basics" "conditions-handlers" "restarts")

(chapter "macros" "Macros"
  "Macros extend the language. syntax-rules macros are hygienic: their names
cannot capture a program's, nor be captured by them. define-macro macros work on
the forms directly."
  "syntax-rules" "shadowing" "macros")

(chapter "documentation" "Documentation"
  "Every built-in is documented in the image, and a definition can be too. The
reference of the built-ins is generated from that documentation."
  "documentation")

(chapter "shared-structure" "Shared and circular structure"
  "Data can share parts, or point back at itself; the reader and the printer
show it with datum labels."
  "cycles")

(chapter "smalltalk" "Smalltalk interop"
  "cog-lisp runs inside a Pharo image, and every Smalltalk object and message is
within reach: send a message with [receiver selector arg ...]."
  "interop-send" "interop-values" "interop-collections" "interop-streams" "interop-callbacks")

(chapter "new-numbers" "Adding a kind of number"
  "Numbers are Smalltalk objects that answer cog-lisp's number protocol, so a
library can add a new kind, with its own read syntax."
  "dual" "new-number-type")

(chapter "common-lisp-style" "Common Lisp style"
  "lib/cl.lisp gives cog-lisp the names of Common Lisp: defun, defmacro, handler-case
and their kin."
  "cl-style" "conditions-cl")

(chapter "lisp-in-lisp" "cog-lisp in cog-lisp"
  "cog-lisp's reader and compiler are written in cog-lisp, compile themselves, and
are part of the running image, where a program can use and extend them."
  "tiny-reader" "read-yourself" "compile-yourself" "extend-the-compiler" "bootstrap"
  "sealed-compiler" "seeded-build" "big-code")
