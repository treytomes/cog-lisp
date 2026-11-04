"============================================================================
 cog-lisp : Phase 8 step 8.3 suite  (specs/phase-8-self-hosting.md AC-3)
 The LISP compiler (lib/compiler/compiler.lisp) against the Smalltalk compiler
 (LispCompiler): every form compiles to the same method, compared by its
 fingerprint (the header, the bytecode bytes, and every literal, blocks
 recursively), or fails with the same error. Not the symbolic listing: Pharo
 cannot print many nested blocks of these methods (CLAUDE.md). Inputs: the bytecode corpus, malformed forms, every top-level form of
 lib/ and examples/ (read with source text, so procedures keep it), and the
 same with each Phase 6 optimization switched off.
 The compiler's own unit tests are tests/lisp/phase-8.3-compiler.lisp.
 Every bang in Lisp text is doubled for the chunk reader.
 ============================================================================"

"--- Chunk 1: load the packages and the harness -----------------------------"
| dir |
dir := Smalltalk imageDirectory parent / 'src'.
#('coglisp-reader.st' 'coglisp-core.st' 'coglisp-compiler.st' 'coglisp-runtime.st' 'coglisp-shell.st')
	do: [:name | (dir / name) fileIn].
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the checks -----------------------------------------------------"
| h root dump describe stCompile lispCompile compileForm compare firstDiff visit isDefinition files count corpus r d lf |
h := LispTestHarness new.
root := Smalltalk imageDirectory parent.
lf := String with: Character lf.

"a method's fingerprint: header, bytecode bytes, literals; blocks recursively.
 A literal block's own listing (symbolic) is not used: printing a nested block
 makes Pharo look up its source node, which fails for many of these methods."
dump := nil.
dump := [:code :s |
	s nextPutAll: 'code header '; print: code header; nextPutAll: ' bytes'.
	code initialPC to: code endPC do: [:i | s space; print: (code at: i)].
	s nextPut: Character lf.
	code literals do: [:lit |
		(lit isKindOf: CompiledBlock)
			ifTrue: [dump value: lit value: s]
			ifFalse: [(lit isKindOf: BlockClosure)
				ifTrue: [s nextPutAll: 'closure '; print: lit numArgs; nextPut: Character lf. dump value: lit compiledBlock value: s]
				ifFalse: [s nextPutAll: 'lit '; nextPutAll: lit class name; space; nextPutAll: (lit printStringLimitedTo: 2000); nextPut: Character lf]]]].
"a compile error is a result; an error while taking the fingerprint is not (it
 would make two failures compare equal), so it is not caught here"
describe := [:blk | | m err |
	err := nil.
	m := [blk value] on: Error do: [:e | err := 'ERROR ' , e class name , ': ' , (e messageText ifNil: ['']). nil].
	err ifNil: [String streamContents: [:s | dump value: m value: s]]].

stCompile := [:datum :map :ctx | describe value: [ | c |
	c := LispCompiler new.
	c instVarNamed: 'sourceMap' put: map.
	c smalltalkCompile: datum context: ctx]].
compileForm := nil.
lispCompile := [:datum :map :ctx | describe value: [
	LispProcedure apply: compileForm to: { datum. map ifNil: [false]. ctx ifNil: [false] }]].

"nil when the texts agree, else the first line where they differ"
firstDiff := [:a :b | | la lb diff |
	a = b ifTrue: [nil] ifFalse: [
		la := a lines. lb := b lines. diff := nil.
		1 to: (la size max: lb size) do: [:i | | x y |
			x := i <= la size ifTrue: [la at: i] ifFalse: ['<end>'].
			y := i <= lb size ifTrue: [lb at: i] ifFalse: ['<end>'].
			(diff isNil and: [x ~= y]) ifTrue: [diff := 'line ' , i printString , ': lisp ' , x printString , ' smalltalk ' , y printString]].
		diff ifNil: ['texts differ']]].

"Both compilers expand the macros in a form, and expanders make gensyms: each
 starts from the same gensym counter, so both see the same expansion."
compare := [:label :datum :map :ctx | | pool g a b |
	pool := LispPrimitives classPool.
	g := pool at: #GensymCounter.
	a := lispCompile value: datum value: map value: ctx.
	pool at: #GensymCounter put: g.
	b := stCompile value: datum value: map value: ctx.
	h check: label actual: (firstDiff value: a value: b) expected: nil].

"forms that define procedures or macros run, so the forms after them compile
 in the same world; others only compile (they may read input or write files)"
isDefinition := [:datum |
	(datum isKindOf: LispCons) and: [
		datum car == (LispSymbol named: 'define-macro') or: [
		datum car == (LispSymbol named: 'define') and: [
			(datum cdr car isKindOf: LispCons) or: [
			(datum cdr cdr car isKindOf: LispCons) and: [datum cdr cdr car car == (LispSymbol named: 'lambda')]]]]]].

"each top-level form as eval sees one: a begin's forms and a macro call's
 expansion are top-level forms in their turn (LispCompiler>>eval:context:steps:)"
visit := nil.
visit := [:datum :reader :ctx :label | | m |
	((datum isKindOf: LispCons) and: [datum car == (LispSymbol named: 'begin')])
		ifTrue: [datum cdr lispElements do: [:f | visit value: f value: reader value: ctx value: label]]
		ifFalse: [
			m := (datum isKindOf: LispCons)
				ifTrue: [LispCompiler new macroFor: datum car inScope: IdentityDictionary new]
				ifFalse: [nil].
			m notNil
				ifTrue: [visit value: (LispCompiler new expand: datum with: m) value: reader
					value: ((reader sourceFor: datum) ifNil: [ctx]) value: label]
				ifFalse: [
					count := count + 1.
					compare value: label , ' form ' , count printString value: datum value: reader value: ctx.
					(isDefinition value: datum) ifTrue: [
						[(LispCompiler new instVarNamed: 'sourceMap' put: reader; yourself) eval: datum]
							on: Error do: [:e | nil]]]]].

[
h say: '== cog-lisp Phase 8.3 : the compiler in LISP =='.
LispPrimitives installDefault.
LispCompiler new evalFile: (root / 'lib' / 'core.lisp') fullName.
"The compiler under test is the installed one, sealed (step 8.5), whichever
 compiler eval uses: the forms of the examples that run here define names such
 as cons and append (examples/sealed-compiler.lisp), which an unsealed copy
 loaded from source would then call."
LispCompiler hasLispCompiler ifFalse: [LispCompiler installLispCompiler].
compileForm := LispCompiler entries at: #compile.

"the comparison itself must see differences"
h check: 'control: (+ 1 2) and (+ 1 3) differ'
	actual: (firstDiff value: (stCompile value: (LispReader read: '(+ 1 2)') value: nil value: nil)
		value: (stCompile value: (LispReader read: '(+ 1 3)') value: nil value: nil)) notNil expected: true.
h check: 'control: the LISP compiler compiles (+ 1 2)'
	actual: ((lispCompile value: (LispReader read: '(+ 1 2)') value: nil value: nil) beginsWith: 'ERROR') expected: false.

"AC-3 the bytecode corpus"
count := 0.
r := LispReader basicOn: (root / 'tests' / 'bytecode-corpus.lisp') contents.
[(d := r next) == LispReader eofObject] whileFalse: [
	count := count + 1.
	compare value: 'AC-3 corpus ' , count printString , ' ' , (LispPrinter writeString: d limitedTo: 50) value: d value: nil value: nil].

"AC-3 a form for each path of the compiler, including its limits"
corpus := OrderedCollection new.
corpus add: ((1 to: 40) inject: 'x' into: [:acc :i | '(+ 1 ' , acc , ')']).
corpus add: '(lambda (x) ' , ((1 to: 30) inject: 'x' into: [:acc :i | '(car ' , acc , ')']) , ')'.
corpus add: '(lambda (' , ((1 to: 20) inject: '' into: [:a :i | a , ' p' , i printString]) , ') (list p1 p20))'.
corpus add: '(lambda (' , ((1 to: 20) inject: '' into: [:a :i | a , ' p' , i printString]) , ' . more) more)'.
corpus add: '(define (big' , ((1 to: 18) inject: '' into: [:a :i | a , ' p' , i printString]) , ') (big' , ((1 to: 18) inject: '' into: [:a :i | a , ' p' , i printString]) , '))'.
corpus add: '(f' , ((1 to: 25) inject: '' into: [:a :i | a , ' ' , i printString]) , ')'.
corpus add: '(let (' , ((1 to: 20) inject: '' into: [:a :i | a , ' (v' , i printString , ' ' , i printString , ')']) , ') (+ v1 v20))'.
corpus add: '(let ((a 1) (b 2) (c 3) (d 4) (e 5)) (list a e))'.
corpus add: '`(1 ' , ((1 to: 30) inject: '' into: [:a :i | a , ' ,x' ]) , ')'.
corpus addAll: #(
	'(define (count-up n) (let loop ((i 0) (acc (quote ()))) (if (= i n) acc (loop (+ i 1) (cons (lambda () i) acc)))))'
	'(define (outer n) (define (inner k) (if (= k 0) 0 (inner (- k 1)))) (inner n))'
	'(define (variadic a . rest) (if (null? rest) a (variadic (car rest))))'
	'(define (shadowed f) (define (f x) x) (f 1))'
	'(define g (lambda (n) (if (= n 0) 0 (g (- n 1)))))'
	'(define (self-arity n) (if (= n 0) 0 (self-arity (- n 1) 2)))'
	'(lambda (x) (set!! x (+ x 1)) x)'
	'(set!! some-global 5)'
	'(define some-global 1)'
	'(send (smalltalk OrderedCollection) new)'
	'(lambda (c) (send c at: 1 put: 2) (send c + 3))'
	'(lambda (t f) (send t ifTrue: f) (send t ifTrue: f ifFalse: f))'
	'[(smalltalk Array) with: 1 with: 2]'
	'(quasiquote #(1 (unquote (+ 1 1)) 3))'
	'(quasiquote (1 (quasiquote (2 (unquote (unquote x))))))'
	'(lambda (x) `(a ,@x b . ,x))'
	'(define-macro (my-swap a b) `(let ((t ,a)) (set!! ,a ,b) (set!! ,b t)))'
	'(define-macro my-id (lambda (x) x))'
	'(begin 1 2 3)'
	'(begin)'
	'(if 1 2)'
	'(quote (a #(b) "c" #\d 1.5))'
	'(lambda () (begin (define a 1) (define b 2)) (+ a b))'
	'(let () 5)'
	'(lambda (x) (eq? x (quote a)) (car x) (null? x) (+ x 1) (vector-ref x 0))'
	'(lambda (x) (+ (car x) (car (cdr x))))'
	'(define (tailer x) (if x (car x) (cdr x)))'
	'(lambda () (lambda () (lambda () 1)))').
corpus doWithIndex: [:src :i |
	compare value: 'AC-3 path ' , i printString , ' ' , (src size > 50 ifTrue: [(src first: 50) , '...'] ifFalse: [src])
		value: (LispReader read: src) value: nil value: nil].

"AC-3 malformed forms fail with the same error"
corpus := #('(if)' '(if 1 2 3 4)' '(lambda)' '(lambda (x x) x)' '(lambda (1) x)' '(lambda (a . 1) a)'
	'(let ((x)) x)' '(let ((x 1) (x 2)) x)' '(let (x) x)' '(let loop)' '(let 5 1)' '(define)' '(define 5 1)'
	'(define (5) 1)' '(define x 1 2)' '(set!! 5 1)' '(set!! x)' '(quote)' '(quote 1 2)' '(quasiquote ,@x)'
	'(send)' '(send x)' '(send x 5)' '(send x foo: 1 2)' '(send x a-b)' '(smalltalk)' '(smalltalk NoSuchGlobalAtAll)'
	'(smalltalk 5)' '(f . 1)' '(+ 1 . 2)' '(lambda (x) (define y 1) x (define z 2))' '(lambda () (+ 1 (define y 2)))'
	'(define-macro)' '(lambda () (define-macro (m) 1))' '(quasiquote (1 (unquote-splicing 5)))').
corpus do: [:src | compare value: 'AC-3 error ' , src value: (LispReader read: src) value: nil value: nil].
"an error from Opal's back end: more temporaries than a frame holds"
compare value: 'AC-3 error: 80 internal defines (frame too large)'
	value: (LispReader read: '(lambda () ' , ((1 to: 80) inject: '' into: [:a :i | a , '(define a' , i printString , ' ' , i printString , ') ']) , 'a1)')
	value: nil value: nil.
h check: 'AC-3 ... and that is an error'
	actual: ((stCompile value: (LispReader read: '(lambda () ' , ((1 to: 80) inject: '' into: [:a :i | a , '(define a' , i printString , ' ' , i printString , ') ']) , 'a1)') value: nil value: nil) beginsWith: 'ERROR')
	expected: true.

"AC-3 every top-level form of lib/ and examples/, with source text"
files := ((root / 'lib') allChildrenMatching: '*.lisp') asSortedCollection: [:x :y | x pathString <= y pathString].
files := files asOrderedCollection , (((root / 'examples') allChildrenMatching: '*.lisp') asSortedCollection: [:x :y | x pathString <= y pathString]).
count := 0.
files do: [:f | | rd label |
	label := 'AC-3 ' , (f relativeTo: root) pathString.
	rd := LispReader basicOn: f contents.
	[[(d := rd next) == LispReader eofObject] whileFalse: [visit value: d value: rd value: nil value: label]]
		on: LispReadError do: [:e | nil]].
h check: 'AC-3 forms compared from lib/ and examples/' actual: count > 300 expected: true.

"AC-3 the corpus again with each optimization off"
LispCompiler allOptions do: [:opt |
	LispCompiler withoutOptions: { opt } do: [
		count := 0.
		r := LispReader basicOn: (root / 'tests' / 'bytecode-corpus.lisp') contents.
		[(d := r next) == LispReader eofObject] whileFalse: [
			count := count + 1.
			compare value: 'AC-3 without ' , opt , ' corpus ' , count printString value: d value: nil value: nil]]].

h finish
] on: Error do: [:e | h harnessError: e].
!
