"============================================================================
 cog-lisp : benchmarks  (specs/phase-6-optimization.md section 6, AC-14..17)
 Run by bench\run-benchmarks.bat against pharo\cog-lisp.image (never saved).
 Each benchmark runs as compiled cog-lisp (all optimizations on, then with each
 one off), on the tree-walking interpreter, and as hand-written Smalltalk.
 Every measurement is the median of 5 timed runs after a warm-up run, and
 excludes compile time. Results print as a table and go to bench/results.md.
 ============================================================================"

"--- Chunk 1: load the tree-walker; define the Smalltalk versions ------------"
| benchDir st |
benchDir := Smalltalk imageDirectory parent / 'bench'.
[(benchDir / 'tree-walker.st') fileIn.
 st := (Object << #CogLispBenchSmalltalk) sharedVariables: { #G1. #G2. #G3 }; package: 'CogLisp-Bench'; install.
 st class compile: 'fib: n
	^ n < 2 ifTrue: [n] ifFalse: [(self fib: n - 1) + (self fib: n - 2)]' classified: 'bench'.
 st class compile: 'tak: x y: y z: z
	^ y < x
		ifTrue: [self tak: (self tak: x - 1 y: y z: z) y: (self tak: y - 1 y: z z: x) z: (self tak: z - 1 y: x z: y)]
		ifFalse: [z]' classified: 'bench'.
 st class compile: 'countLoop: n
	| acc i |
	acc := 0. i := n.
	[i = 0] whileFalse: [i := i - 1. acc := acc + 1].
	^ acc' classified: 'bench'.
 st class compile: 'isEven: n
	^ n = 0 ifTrue: [true] ifFalse: [self isOdd: n - 1]' classified: 'bench'.
 st class compile: 'isOdd: n
	^ n = 0 ifTrue: [false] ifFalse: [self isEven: n - 1]' classified: 'bench'.
 st class compile: 'listBench: n
	^ ((1 to: n) asOrderedCollection collect: [:x | x * 2]) inject: 0 into: [:a :b | a + b]' classified: 'bench'.
 st class compile: 'globalsLoop: n
	| acc i |
	G1 := 1. G2 := 2. G3 := 3.
	acc := 0. i := n.
	[i = 0] whileFalse: [i := i - 1. acc := acc + G1 + G2 + G3].
	^ acc' classified: 'bench'.
] on: Error do: [:e |
	Stdio stdout nextPutAll: 'BENCH SETUP FAILED: ' , e messageText printString; nextPut: Character lf; flush.
	Smalltalk exit: 1].
!

"--- Chunk 2: run, report, check -------------------------------------------"
| out benches configs median compiledRun walkerRun stRun rows report checks pass total check fmt ratio file sizeNote sendTimes placeTimes compileForms compileMs readText readMs |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
LispPrimitives installDefault.
"Reinstalling the primitives makes new procedure objects, and the setters of
 generalized set (Phase 9 step 9.4) are keyed by the old ones: load lib/core.lisp
 again so (setter car) knows the car in use."
LispCompiler new evalFile: (Smalltalk imageDirectory parent / 'lib' / 'core.lisp') fullName.

benches := {
	{ 'fib 22'. '(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))'. '(fib 22)'. 17711.
		[CogLispBenchSmalltalk fib: 22]. #(#fastCalls #inlinePrimitives) }.
	{ 'tak 18 12 6'. '(define (tak x y z) (if (not (< y x)) z (tak (tak (- x 1) y z) (tak (- y 1) z x) (tak (- z 1) x y))))'. '(tak 18 12 6)'. 7.
		[CogLispBenchSmalltalk tak: 18 y: 12 z: 6]. #(#fastCalls #inlinePrimitives) }.
	{ 'loop 100000'. '(define (count-loop n acc) (if (= n 0) acc (count-loop (- n 1) (+ acc 1))))'. '(count-loop 100000 0)'. 100000.
		[CogLispBenchSmalltalk countLoop: 100000]. #(#tailCalls) }.
	{ 'even?/odd? 20000'. '(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1)))) (define (my-odd? n) (if (= n 0) #f (my-even? (- n 1))))'. '(my-even? 20000)'. true.
		[CogLispBenchSmalltalk isEven: 20000]. #() }.
	{ 'list 20000'. '(define (iota n acc) (if (= n 0) acc (iota (- n 1) (cons n acc)))) (define (sum-list lst acc) (if (null? lst) acc (sum-list (cdr lst) (+ acc (car lst)))))'.
		'(sum-list (map (lambda (x) (* x 2)) (iota 20000 (list))) 0)'. 400020000.
		[CogLispBenchSmalltalk listBench: 20000]. #() }.
	{ 'globals 50000'. '(define g1 1) (define g2 2) (define g3 3) (define (gloop n acc) (if (= n 0) acc (gloop (- n 1) (+ acc g1 g2 g3))))'. '(gloop 50000 0)'. 300000.
		[CogLispBenchSmalltalk globalsLoop: 50000]. #(#globalCells) } }.

"configurations of the compiler: a label and the options switched off"
configs := { { 'all on'. #() } } , (LispCompiler allOptions collect: [:opt | { 'no ' , opt. { opt } }]).

"Milliseconds per run: the median of 5 timed samples after a warm-up run, checking
 the result first. The clock ticks in whole milliseconds, so each sample repeats
 the run enough times to take at least 100 ms, and the time is divided by that."
median := [:label :expected :blk | | result reps sample times |
	result := blk value.
	(LispCore equal: result with: expected) ifFalse: [
		Error signal: label , ' gave ' , (LispPrinter writeString: result) , ', expected ' , (LispPrinter writeString: expected)].
	sample := [:n | | t0 | t0 := Time millisecondClockValue. n timesRepeat: [blk value]. Time millisecondClockValue - t0].
	"start every series from a clean heap, so one series does not pay for another's garbage"
	Smalltalk garbageCollect.
	reps := 1.
	[(sample value: reps) < 100] whileTrue: [reps := reps * 2].
	times := (1 to: 5) collect: [:i | sample value: reps].
	(times asSortedCollection asArray at: 3) / reps asFloat].
compiledRun := [:b :offs | | thunk |
	LispCompiler withoutOptions: offs do: [
		LispCompiler new evalAll: (b at: 2).
		thunk := LispCompiler new compile: (LispReader read: (b at: 3))].
	median value: (b at: 1) value: (b at: 4) value: [thunk valueWithReceiver: nil arguments: #()]].
walkerRun := [:b | | tw form |
	tw := LispTreeWalker new.
	tw evalAll: (b at: 2).
	form := LispReader read: (b at: 3).
	median value: (b at: 1) , ' (tree-walker)' value: (b at: 4) value: [tw eval: form in: nil]].
stRun := [:b | median value: (b at: 1) , ' (Smalltalk)' value: (b at: 4) value: (b at: 5)].

fmt := [:ms | ms printShowingDecimalPlaces: (ms < 10 ifTrue: [2] ifFalse: [1])].
ratio := [:a :b | ((a / b) printShowingDecimalPlaces: 1) , 'x'].
pass := 0. total := 0.
checks := OrderedCollection new.
check := [:label :ok |
	total := total + 1.
	ok ifTrue: [pass := pass + 1].
	checks add: (ok ifTrue: ['PASS  '] ifFalse: ['FAIL  ']) , label].

[
out value: '== cog-lisp benchmarks (median of 5 warm runs, ms) =='.
"Whatever runs first in the process measured consistently slower (heap growth,
 JIT), which skewed the first configuration of each benchmark. So run the whole
 matrix once as a warm-up and discard it, then measure."
out value: '  warm-up pass over every benchmark and configuration ...'.
benches do: [:b |
	configs do: [:c | compiledRun value: b value: (c at: 2)].
	walkerRun value: b.
	stRun value: b].
rows := benches collect: [:b | | times tw stm |
	out value: '  running ' , (b at: 1) , ' ...'.
	times := configs collect: [:c | compiledRun value: b value: (c at: 2)].
	tw := walkerRun value: b.
	stm := stRun value: b.
	{ b. times. tw. stm }].

"AC-15: compiled beats the tree-walker everywhere"
rows do: [:r | check value: 'AC-15 compiled faster than the tree-walker: ' , ((r at: 1) at: 1) value: (r at: 2) first < (r at: 3)].
"AC-16: each optimization beats its own switched-off version on its target benchmark"
rows do: [:r | ((r at: 1) at: 6) do: [:opt | | offTime |
	offTime := (r at: 2) at: (configs findFirst: [:c | (c at: 2) = { opt }]).
	check value: 'AC-16/24 ' , opt , ' makes ' , ((r at: 1) at: 1) , ' faster (' , (ratio value: offTime value: (r at: 2) first) , ')'
		value: (r at: 2) first < offTime]].

"Phase 7.6 AC-20: a send to Smalltalk costs what the LISP call it replaces costs.
 Not in the table: the tree-walker has no send."
out value: '  running send 1000000 ...'.
sendTimes := {
	compiledRun value: { 'send 1000000'. '(define (send-loop n acc) (if (= n 0) acc (send-loop (- n 1) (send acc + 1))))'. '(send-loop 1000000 0)'. 1000000 } value: #().
	compiledRun value: { 'plus 1000000'. '(define (plus-loop n acc) (if (= n 0) acc (plus-loop (- n 1) (+ acc 1))))'. '(plus-loop 1000000 0)'. 1000000 } value: #() }.
check value: 'Phase 7.6 AC-20 (send acc + 1) within 1.5x of (+ acc 1) (' , (ratio value: sendTimes first value: sendTimes last) , ')'
	value: sendTimes first <= (1.5 * sendTimes last).

"Phase 9 step 9.4b: generalized set!! against the setter it calls. (setter car) is
 looked up on every assignment; a compile-time shortcut is built only if this is
 more than 1.5 times slower. Each loop ends having stored 1."
out value: '  running set!! of a place ...'.
placeTimes := {
	compiledRun value: { 'set-car!! 1000000'. '(define bp (list 0)) (define (sc-loop n) (if (= n 0) (car bp) (begin (set-car!! bp n) (sc-loop (- n 1)))))'. '(begin (sc-loop 1000000) (car bp))'. 1 } value: #().
	compiledRun value: { 'set!! (car) 1000000'. '(define bq (list 0)) (define (sp-loop n) (if (= n 0) (car bq) (begin (set!! (car bq) n) (sp-loop (- n 1)))))'. '(begin (sp-loop 1000000) (car bq))'. 1 } value: #().
	compiledRun value: { 'vector-set!! 1000000'. '(define bv (vector 0)) (define (vs-loop n) (if (= n 0) (vector-ref bv 0) (begin (vector-set!! bv 0 n) (vs-loop (- n 1)))))'. '(begin (vs-loop 1000000) (vector-ref bv 0))'. 1 } value: #().
	compiledRun value: { 'set!! (vector-ref) 1000000'. '(define bw (vector 0)) (define (vp-loop n) (if (= n 0) (vector-ref bw 0) (begin (set!! (vector-ref bw 0) n) (vp-loop (- n 1)))))'. '(begin (vp-loop 1000000) (vector-ref bw 0))'. 1 } value: #() }.

"Phase 7.9: how long compiling takes. The forms of lib/core.lisp and
 examples/tiny-reader.lisp (expanders and procedures), compiled 20 times."
out value: '  timing compilation ...'.
compileForms := OrderedCollection new.
readText := (Smalltalk imageDirectory parent / 'lib' / 'core.lisp') contents ,
	(Smalltalk imageDirectory parent / 'examples' / 'tiny-reader.lisp') contents.
[:r | | d | [(d := r next) == LispReader eofObject] whileFalse: [compileForms add: d]]
	value: (LispReader on: readText).
LispCompiler new evalFile: (Smalltalk imageDirectory parent / 'lib' / 'core.lisp') fullName.
3 timesRepeat: [compileForms do: [:f | LispCompiler new compile: f]].
Smalltalk garbageCollect.
compileMs := (([60 timesRepeat: [compileForms do: [:f | LispCompiler new compile: f]]] timeToRun asMilliSeconds) / 60.0).
"compile: and LispReader on: use the reader and compiler written in LISP. Until
 Phase 9 step 9.1 the Smalltalk ones were timed beside them (Phase 8 AC-7, AC-8);
 they retired then. The Phase 7.9 compiler took 36.3 ms on a quieter machine;
 Phase 8.6 made it about 2x faster. The check guards that, with a margin for a
 busy machine."
3 timesRepeat: [LispReader readAll: readText].
Smalltalk garbageCollect.
readMs := (([20 timesRepeat: [LispReader readAll: readText]] timeToRun asMilliSeconds) / 20.0).
check value: 'Phase 8 AC-8 compiling is faster than Phase 7.9 did (36.3 ms): ' , (fmt value: compileMs) , ' ms'
	value: compileMs < 36.3.

report := String streamContents: [:s |
	s nextPutAll: '# cog-lisp benchmark results'; lf; lf.
	s nextPutAll: 'Generated by `bench\run-benchmarks.bat` on ' , Date today yyyymmdd , ', with '
		, SystemVersion current imageVersionString , ' on the Pharo VM '
		, ((Smalltalk vm version copyAfter: $v) copyUpTo: Character space) , ' (Cog JIT).'; lf.
	s nextPutAll: 'Times are the median of 5 warm runs, in milliseconds, excluding compile time. Lower is better.'; lf; lf.
	s nextPutAll: '## cog-lisp against the baselines'; lf; lf.
	s nextPutAll: '| Benchmark | cog-lisp | tree-walker | Smalltalk | speedup over tree-walker | slowdown vs Smalltalk |'; lf.
	s nextPutAll: '|---|---:|---:|---:|---:|---:|'; lf.
	rows do: [:r |
		s nextPutAll: '| ' , ((r at: 1) at: 1) , ' | ' , (fmt value: (r at: 2) first) , ' | ' , (fmt value: (r at: 3)) , ' | ' , (fmt value: (r at: 4))
			, ' | ' , (ratio value: (r at: 3) value: (r at: 2) first) , ' | ' , (ratio value: (r at: 2) first value: (r at: 4)) , ' |'; lf].
	s lf; nextPutAll: '## Each optimization switched off'; lf; lf.
	s nextPutAll: 'cog-lisp time with one optimization off, and how much slower that is than with all on.'; lf; lf.
	s nextPutAll: '| Benchmark |'.
	configs do: [:c | s nextPutAll: ' ' , (c at: 1) , ' |'].
	s lf; nextPutAll: '|---|'.
	configs do: [:c | s nextPutAll: '---:|'].
	s lf.
	rows do: [:r |
		s nextPutAll: '| ' , ((r at: 1) at: 1) , ' |'.
		(r at: 2) doWithIndex: [:t :i |
			s nextPutAll: ' ' , (fmt value: t).
			i > 1 ifTrue: [s nextPutAll: ' (' , (ratio value: t value: (r at: 2) first) , ')'].
			s nextPutAll: ' |'].
		s lf].
	s lf; nextPutAll: '## Compilation'; lf; lf.
	s nextPutAll: 'Compiling the ' , compileForms size printString , ' forms of `lib/core.lisp` and `examples/tiny-reader.lisp`: ' , (fmt value: compileMs)
		, ' ms (Phase 7.9: 36.3 ms).'; lf; lf.
	s nextPutAll: 'Reading the same ' , readText size printString , ' characters: ' , (fmt value: readMs) , ' ms.'; lf; lf.
	s nextPutAll: 'Until Phase 9 step 9.1 the Smalltalk compiler and reader were timed beside these; the last such run had them at 52.7 ms and 1.87 ms.'; lf.
	s lf; nextPutAll: '## Smalltalk interop'; lf; lf.
	s nextPutAll: 'A loop of 1,000,000 `(send acc + 1)`: ' , (fmt value: sendTimes first) , ' ms; the same loop with `(+ acc 1)`: '
		, (fmt value: sendTimes last) , ' ms (' , (ratio value: sendTimes first value: sendTimes last) , ').'; lf.
		s lf; nextPutAll: '## Assignment to a place'; lf; lf.
		s nextPutAll: 'Generalized `set!!` (Phase 9 step 9.4) against the setter it calls, in a loop of 1,000,000:'; lf; lf.
		s nextPutAll: '| Loop | direct | `set!!` of the place | ratio |'; lf.
		s nextPutAll: '|---|---:|---:|---:|'; lf.
		s nextPutAll: '| `(car p)` | ' , (fmt value: (placeTimes at: 1)) , ' | ' , (fmt value: (placeTimes at: 2)) , ' | ' , (ratio value: (placeTimes at: 2) value: (placeTimes at: 1)) , ' |'; lf.
		s nextPutAll: '| `(vector-ref v 0)` | ' , (fmt value: (placeTimes at: 3)) , ' | ' , (fmt value: (placeTimes at: 4)) , ' | ' , (ratio value: (placeTimes at: 4) value: (placeTimes at: 3)) , ' |'; lf.
	s lf; nextPutAll: '## Checks'; lf; lf.
	checks do: [:c | s nextPutAll: '- ' , c; lf]].
out value: ''.
out value: report.
file := Smalltalk imageDirectory parent / 'bench' / 'results.md'.
file ensureDelete.
file writeStreamDo: [:w | w nextPutAll: report].
out value: 'wrote ' , file pathString.
out value: '== RESULT: ' , pass printString , '/' , total printString , ' checks passed =='.
Smalltalk exit: (pass = total ifTrue: [0] ifFalse: [1])
] on: Error do: [:e |
	out value: 'BENCH ERROR: ' , e class name , ': ' , e messageText printString.
	Smalltalk exit: 1].
!
