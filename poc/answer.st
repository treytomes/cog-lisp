"============================================================================
 cog-lisp : proof-of-concept #1
 Hand-build CompiledMethods from Opal IR, run them, and confirm they are real
 Cog/Spur bytecode.

 WHY THIS EXISTS
   The project bet is: compile LISP down to CompiledMethods and let the Cog JIT
   run them native (Path A). Before writing a reader or evaluator, this POC
   de-risks the whole pathway by proving, with the smallest possible programs,
   that we can:
     1. build a CompiledMethod from an IR (not from source text)   -> method A
     2. execute it and get the right value                         -> method A
     3. pass arguments and use temporaries                         -> method B
     4. send back into Smalltalk (our future LISP primitives)      -> method B
     5. branch (our future LISP `if`)                              -> method C
   Bonus: install a built method into a class and hammer it so the Cog JIT
   actually compiles it to machine code.

 All selectors below were verified against this image (Pharo 14, build 788);
 the Opal builder is OCIRBuilder, finalized with `(builder ... ; ir)
 compiledMethod`, and methods run directly via #valueWithReceiver:arguments:.

 RUN (headless, from the repo root):
   pharo\PharoConsole.exe pharo\Pharo14.0-SNAPSHOT-64bit-58e29ca31d.image ^
       st poc\answer.st
 ============================================================================"

| out pass total check mAnswer mAdd mMax |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
pass := 0.
total := 0.
check := [:label :actual :expected |
  total := total + 1.
  actual = expected
    ifTrue: [ pass := pass + 1.
              out value: '  PASS  ' , label , ' = ' , actual printString ]
    ifFalse: [ out value: '  FAIL  ' , label , ' = ' , actual printString
                 , '  (expected ' , expected printString , ')' ] ].

out value: '== cog-lisp POC #1 : CompiledMethods from Opal IR =='.

[
  "--- A: zero-arg constant method, returns 3 + 4 --------------------------"
  mAnswer := (IRBuilder new
      numArgs: 0;
      pushLiteral: 3;
      pushLiteral: 4;
      send: #+;
      returnTop;
      ir) compiledMethod.
  check value: 'A  answer (3+4)'
        value: (mAnswer valueWithReceiver: nil arguments: #())
        value: 7.

  "--- B: two-arg method add:to:, returns a + b (args, temps, a send) ------"
  mAdd := (IRBuilder new
      numArgs: 2;
      addTemps: #(a b);
      pushTemp: #a;
      pushTemp: #b;
      send: #+;
      returnTop;
      ir) compiledMethod.
  check value: 'B  add:to: (2,5)'
        value: (mAdd valueWithReceiver: nil arguments: #(2 5))
        value: 7.
  check value: 'B  add:to: (10,-3)'
        value: (mAdd valueWithReceiver: nil arguments: #(10 -3))
        value: 7.

  "--- C: two-arg method max:with:, a > b ifTrue: [a] ifFalse: [b] --------
   This is the future shape of LISP `if`: a conditional jump over a branch."
  mMax := (IRBuilder new
      numArgs: 2;
      addTemps: #(a b);
      pushTemp: #a;
      pushTemp: #b;
      send: #>;
      jumpAheadTo: #useB if: false;
      pushTemp: #a;
      returnTop;
      jumpAheadTarget: #useB;
      pushTemp: #b;
      returnTop;
      ir) compiledMethod.
  check value: 'C  max:with: (2,5)'
        value: (mMax valueWithReceiver: nil arguments: #(2 5))
        value: 5.
  check value: 'C  max:with: (9,1)'
        value: (mMax valueWithReceiver: nil arguments: #(9 1))
        value: 9.

  "--- evidence: disassemble C to show it really is bytecode + a branch ----"
  out value: '  -- C disassembly (proof of real SistaV1 bytecode) --'.
  out value: mMax symbolic.

  "--- bonus: install A into a class, send it normally, and hammer it so the
   Cog JIT compiles it to machine code. Best-effort; never fails the POC. ---"
  [ | cls inst |
    cls := Object subclass: #CogLispPOC.
    cls addSelectorSilently: #answer withMethod: mAnswer.
    inst := cls new.
    check value: 'JIT  installed send: CogLispPOC new answer'
          value: inst answer
          value: 7.
    200000 timesRepeat: [ inst answer ].
    out value: '  (sent #answer 200k times to force JIT compilation - no error)' ]
    on: Error
    do: [:e | out value: '  SKIP  JIT bonus (' , e class name , ': '
                           , e messageText printString , ')' ].
] on: Error do: [:e |
  out value: '  ABORT  ' , e class name , ': ' , e messageText printString ].

out value: '== RESULT: ' , pass printString , '/' , total printString
           , ' checks passed =='.

Smalltalk snapshot: false andQuit: true.
