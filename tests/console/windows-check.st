"specs/29-console.md AC-4 and AC-5, on a real Windows console: run by
 tests\console\windows-check.bat, which starts it in a fresh conhost window and
 prints its log. It writes through the console library, reads the screen back,
 injects keys for read-event, and checks the console modes are restored.
 Not part of run-all: it needs a console, which a suite run has not."
| k log pass total check lisp out in omode imode buf rec inject readRow attrAt |
(Object << #ConsoleCheck) package: 'ConsoleCheck'; install.
k := Smalltalk at: #ConsoleCheck.
#(
'getStdHandle: n ^ self ffiCall: #(void* GetStdHandle(long n)) module: ''kernel32.dll'''
'getMode: h into: b ^ self ffiCall: #(int GetConsoleMode(void* h, void* b)) module: ''kernel32.dll'''
'readChars: h buffer: b count: c at: xy into: r ^ self ffiCall: #(int ReadConsoleOutputCharacterW(void* h, void* b, uint32 c, uint32 xy, void* r)) module: ''kernel32.dll'''
'readAttrs: h buffer: b count: c at: xy into: r ^ self ffiCall: #(int ReadConsoleOutputAttribute(void* h, void* b, uint32 c, uint32 xy, void* r)) module: ''kernel32.dll'''
'writeInput: h records: b count: c into: w ^ self ffiCall: #(int WriteConsoleInputW(void* h, void* b, uint32 c, void* w)) module: ''kernel32.dll'''
) do: [:src | k class compile: src].
log := WriteStream on: String new.
pass := 0. total := 0.
check := [:name :ok | total := total + 1. ok == true ifTrue: [pass := pass + 1].
	log nextPutAll: (ok == true ifTrue: ['  PASS  '] ifFalse: ['  FAIL  ']); nextPutAll: name; lf].
lisp := [:source | LispCompiler new evalAll: source].
out := k getStdHandle: -11.
in := k getStdHandle: -10.
readRow := [:row :len | | b rd | b := ByteArray new: len * 2. rd := ByteArray new: 4.
	k readChars: out buffer: b count: len at: (row bitShift: 16) into: rd.
	(ZnCharacterEncoder newForEncoding: 'utf-16le') decodeBytes: b].
attrAt := [:col :row | | b rd | b := ByteArray new: 2. rd := ByteArray new: 4.
	k readAttrs: out buffer: b count: 1 at: (row bitShift: 16) + col into: rd. b unsignedShortAt: 1].
inject := [:vk :ch :ctrl | | b | b := ByteArray new: 20.
	b unsignedShortAt: 1 put: 1. b unsignedLongAt: 5 put: 1. b unsignedShortAt: 9 put: 1.
	b unsignedShortAt: 11 put: vk. b unsignedShortAt: 15 put: ch. b unsignedLongAt: 17 put: ctrl.
	k writeInput: in records: b count: 1 into: (ByteArray new: 4)].
buf := ByteArray new: 4. k getMode: in into: buf. imode := buf unsignedLongAt: 1.
buf := ByteArray new: 4. k getMode: out into: buf. omode := buf unsignedLongAt: 1.
log nextPutAll: '== cog-lisp : the console library on a Windows console (specs/29-console.md AC-4, AC-5) =='; lf.

[LispCurrentUnit value: LispUnit session during: [
	"the library path, which a program run sets at its start (doubled: this file is chunk format)"
	lisp value: '(%env-start!!)'.
	lisp value: '(require ''console)'.
	check value: 'R-1 a console: a terminal, interactive, truecolor, its size'
		value: (lisp value: '(let ((c (console-capabilities))) (and (hash-table-ref c ''terminal?) (hash-table-ref c ''interactive?) (eq? (hash-table-ref c ''colors) ''truecolor) (> (hash-table-ref c ''width) 0)))').
	lisp value: '(display (string (integer->char 27) #\[ #\2 #\J (integer->char 27) #\[ #\H)) (print-markup "[red]RED[/] [bold blue]B[/]") (%terminal-flush)'.
	check value: 'R-4 markup shows on the screen as text' value: (readRow value: 0 value: 5) = 'RED B'.
	check value: 'R-4 red is red (attribute 4)' value: ((attrAt value: 0 value: 0) bitAnd: 15) = 4.
	check value: 'R-4 bold blue is bright blue (attribute 9)' value: ((attrAt value: 4 value: 0) bitAnd: 15) = 9.
	"keys: down, x, Ctrl+Left (left ctrl 8), Escape, Enter"
	inject value: 16r28 value: 0 value: 0.
	inject value: 16r58 value: 120 value: 0.
	inject value: 16r25 value: 0 value: 8.
	check value: 'R-19 down arrives as down' value: (lisp value: '(key-event? (read-event 2000) ''down)').
	check value: 'R-19 x arrives as x' value: (lisp value: '(key-event? (read-event 2000) #\x)').
	check value: 'R-19 Ctrl+Left arrives as left with ctrl' value: (lisp value: '(key-event? (read-event 2000) ''left ''ctrl)').
	"Escape alone: typed, it has nothing right behind it (ESC with a key at once behind it is Alt and that key)"
	inject value: 16r1B value: 27 value: 0.
	check value: 'R-19 Escape alone arrives as escape' value: (lisp value: '(key-event? (read-event 2000) ''escape)').
	inject value: 16r0D value: 13 value: 0.
	check value: 'R-19 Enter arrives as enter' value: (lisp value: '(key-event? (read-event 2000) ''enter)').
	inject value: 16r1B value: 27 value: 0.
	inject value: 16r0D value: 13 value: 0.
	check value: 'R-19 Escape with Enter at once behind it is Alt+Enter' value: (lisp value: '(key-event? (read-event 2000) ''enter ''alt)').
	check value: 'R-20 with nothing typed, read-event answers #f after its timeout' value: (lisp value: '(not (read-event 100))').
	buf := ByteArray new: 4. k getMode: in into: buf.
	check value: 'AC-5 after read-event, the input mode is as it was' value: (buf unsignedLongAt: 1) = imode.
	"an error inside raw mode, and nested raw mode"
	lisp value: '(guard (e (#t #f)) (with-raw-mode (lambda () (with-raw-mode (lambda () (error "stop"))))))'.
	buf := ByteArray new: 4. k getMode: in into: buf.
	check value: 'AC-5 after an error in nested raw mode, the input mode is as it was' value: (buf unsignedLongAt: 1) = imode.
	lisp value: '(display (string (integer->char 27) #\[ #\H)) (display "MAIN") (%terminal-flush) (with-alternate-screen (lambda () (display "OTHER") (%terminal-flush)))'.
	check value: 'R-21 the alternate screen leaves the main one as it was' value: ((readRow value: 0 value: 4) = 'MAIN')]]
	on: Error do: [:e | log nextPutAll: '  ERROR  '; nextPutAll: e messageText asString; lf].
log nextPutAll: '== RESULT: '; print: pass; nextPut: $/; print: total; nextPutAll: ' checks passed =='; lf.
(FileLocator temp / 'cog-lisp-console-check.log') ensureDelete; writeStreamDo: [:s | s nextPutAll: log contents].
Smalltalk exit: (pass = total ifTrue: [0] ifFalse: [1]).
!
