# The built-ins of cog-lisp

Every special form, derived form and built-in procedure, with its call form
and what it does. Generated from the documentation kept in the image
(specs/phase-10-documentation-and-editor.md, step 10.2): do not edit by hand.
After changing documentation, rebuild the image and run
`./cog-lisp.sh tools/generate-docs.lisp` (or `cog-lisp.bat`).

In a call form, `[x]` is optional and `x ...` is any number of them.
`(documentation 'name)` answers the same text at the REPL.

- [Special forms](#special-forms) (16)
- [Equality and types](#equality-and-types) (11)
- [Numbers](#numbers) (62)
- [Lists](#lists) (20)
- [Characters](#characters) (16)
- [Strings](#strings) (29)
- [Vectors](#vectors) (14)
- [Hash tables](#hash-tables) (19)
- [Control](#control) (3)
- [Conditions and restarts](#conditions-and-restarts) (19)
- [Evaluation and macros](#evaluation-and-macros) (5)
- [Output](#output) (3)
- [Ports](#ports) (14)
- [Files](#files) (17)
- [The system](#the-system) (7)
- [Smalltalk interop](#smalltalk-interop) (11)
- [Language server](#language-server) (2)
- [The compiler and reader](#the-compiler-and-reader) (17)

## Special forms

| Name | Call | Kind | What it does |
|---|---|---|---|
| `begin` | `(begin form ...)` | special form | Evaluates the forms in order and answers the last; at top level each is a top-level form. |
| `define` | `(define name value), (define (name . params) body ...)` | special form | Defines name, globally at top level or locally at the start of a body. A body that starts with a string keeps it as its documentation. |
| `define-macro` | `(define-macro (name . params) body ...)` | special form | A macro that is not hygienic: its expander gets the operands and answers code, whose names mean what they mean where it is used. |
| `define-syntax` | `(define-syntax name [documentation] (syntax-rules ...))` | special form | A hygienic macro, at top level or local to a body. |
| `if` | `(if test then [else])` | special form | Evaluates then if test is true (anything but #f), else else. |
| `lambda` | `(lambda params body ...)` | special form | A procedure. params is (a b), (a b . rest) or rest; a body may start with internal definitions, and with a documentation string. |
| `let` | `(let ((name init) ...) body ...), (let loop ((name init) ...) body ...)` | special form | Binds each name to its init, evaluated outside the bindings; the named form also binds loop to the body as a procedure. |
| `let-syntax` | `(let-syntax ((name (syntax-rules ...)) ...) body ...)` | special form | Local macros, defined in the enclosing scope, for the body. |
| `letrec-syntax` | `(letrec-syntax ((name (syntax-rules ...)) ...) body ...)` | special form | Local macros that can use each other, for the body. |
| `quasiquote` | `(quasiquote template), `template` | special form | The template as data, with (unquote x) and (unquote-splicing x), written ,x and ,@x, filled in. |
| `quote` | `(quote datum), 'datum` | special form | The datum itself, not evaluated. |
| `send` | `(send receiver selector arg ...), [receiver selector arg ...]` | special form | Sends a Smalltalk message; the selector is spelled as in Smalltalk (at:put:). |
| `set!` | `(set! name value)` | special form | Assigns value to the variable name, local or global. |
| `smalltalk` | `(smalltalk Name)` | special form | The Smalltalk global Name, such as a class. |
| `syntax-error` | `(syntax-error message form ...)` | special form | Stops compilation with message and the forms, for a macro to report a misuse. |
| `syntax-rules` | `(syntax-rules [ellipsis] (literal ...) (pattern template) ...)` | special form | The transformer of a hygienic macro: the first pattern a use matches gives its template, filled in. |

## Equality and types

| Name | Call | Kind | What it does |
|---|---|---|---|
| `boolean?` | `(boolean? x)` | procedure | True if x is #t or #f. |
| `char?` | `(char? x)` | procedure | True if x is a character. |
| `eq?` | `(eq? a b)` | procedure | True if a and b are the same object. |
| `equal?` | `(equal? a b)` | procedure | True if a and b are eqv?, or pairs, vectors or strings with equal? contents. |
| `eqv?` | `(eqv? a b)` | procedure | True if a and b are the same object, or numbers of the same exactness and value, or the same character. |
| `integer?` | `(integer? x)` | procedure | True if x is an integer, exact or not: (integer? 2.0) is true. |
| `not` | `(not x)` | procedure | True if x is #f, the only false value. |
| `number?` | `(number? x)` | procedure | True if x is a number. |
| `procedure?` | `(procedure? x)` | procedure | True if x is a procedure. |
| `string?` | `(string? x)` | procedure | True if x is a string. |
| `symbol?` | `(symbol? x)` | procedure | True if x is a symbol. |

## Numbers

| Name | Call | Kind | What it does |
|---|---|---|---|
| `*` | `(* z ...)` | procedure | The product of the numbers; 1 for none. |
| `+` | `(+ z ...)` | procedure | The sum of the numbers; 0 for none. |
| `-` | `(- z w ...)` | procedure | z minus each w in turn; with one argument, its negation. |
| `/` | `(/ z w ...)` | procedure | z divided by each w in turn; with one argument, its reciprocal. Exact division stays exact (1/3); a float divided by zero gives an infinity or NaN. |
| `<` | `(< x1 x2 ...)` | procedure | True if the numbers are strictly increasing. |
| `<=` | `(<= x1 x2 ...)` | procedure | True if the numbers never decrease. |
| `=` | `(= z1 z2 ...)` | procedure | True if the numbers are all equal. |
| `>` | `(> x1 x2 ...)` | procedure | True if the numbers are strictly decreasing. |
| `>=` | `(>= x1 x2 ...)` | procedure | True if the numbers never increase. |
| `abs` | `(abs x)` | procedure | The absolute value of the real number x. |
| `acos` | `(acos z)` | procedure | The arccosine of z; +nan.0 outside -1 to 1. |
| `asin` | `(asin z)` | procedure | The arcsine of z; +nan.0 outside -1 to 1. |
| `atan` | `(atan y [x])` | procedure | The arctangent of y, or of y/x in the right quadrant. |
| `ceiling` | `(ceiling x)` | procedure | The smallest integer not less than x; a float stays a float. |
| `complex?` | `(complex? x)` | procedure | True if x is a number: there are no non-real numbers built in. |
| `cos` | `(cos z)` | procedure | The cosine of z, in radians. |
| `denominator` | `(denominator q)` | procedure | The denominator of the rational q in lowest terms, always positive. |
| `even?` | `(even? n)` | procedure | True if the integer n is even. |
| `exact` | `(exact z)` | procedure | The exact number equal to z: a float gives the fraction it holds exactly. An error for an infinity or NaN. |
| `exact->inexact` | `(exact->inexact z)` | procedure | The old name of inexact. |
| `exact-integer-sqrt` | `(exact-integer-sqrt n)` | procedure | Two values: the largest integer s with s*s not above n, and n - s*s. |
| `exact-integer?` | `(exact-integer? x)` | procedure | True if x is an exact integer. |
| `exact-rational?` | `(exact-rational? x)` | procedure | True if x is an exact integer or an exact fraction. |
| `exact?` | `(exact? z)` | procedure | True if the number z is exact. |
| `exp` | `(exp z)` | procedure | e raised to the power z. |
| `expt` | `(expt z1 z2)` | procedure | z1 raised to the power z2: exact for an exact base and an exact integer power. |
| `finite?` | `(finite? z)` | procedure | True if the number z is neither infinite nor NaN. |
| `floor` | `(floor x)` | procedure | The largest integer not greater than x; a float stays a float. |
| `floor-quotient` | `(floor-quotient n d)` | procedure | The quotient of n by d, rounded toward minus infinity. |
| `floor-remainder` | `(floor-remainder n d)` | procedure | The remainder of n by d after floor-quotient; it has the sign of d. |
| `floor/` | `(floor/ n d)` | procedure | Two values: the quotient of n by d rounded toward minus infinity, and the remainder, which has the sign of d. |
| `gcd` | `(gcd n ...)` | procedure | The greatest common divisor of the integers, never negative; 0 for none. |
| `inexact` | `(inexact z)` | procedure | The float nearest to z. |
| `inexact->exact` | `(inexact->exact z)` | procedure | The old name of exact. |
| `inexact?` | `(inexact? z)` | procedure | True if the number z is inexact (a float). |
| `infinite?` | `(infinite? z)` | procedure | True if the number z is +inf.0 or -inf.0. |
| `lcm` | `(lcm n ...)` | procedure | The least common multiple of the integers, never negative; 1 for none. |
| `log` | `(log z [base])` | procedure | The natural logarithm of z, or its logarithm in base; -inf.0 at zero, +nan.0 below it. |
| `magnitude` | `(magnitude x)` | procedure | The magnitude of x: for a real number, its absolute value. |
| `max` | `(max x y ...)` | procedure | The largest of the real numbers; inexact if any of them is. |
| `min` | `(min x y ...)` | procedure | The smallest of the real numbers; inexact if any of them is. |
| `modulo` | `(modulo n d)` | procedure | The old name of floor-remainder. |
| `nan?` | `(nan? z)` | procedure | True if the number z is a NaN. |
| `negative?` | `(negative? x)` | procedure | True if the real number x is less than zero. |
| `numerator` | `(numerator q)` | procedure | The numerator of the rational q in lowest terms. |
| `odd?` | `(odd? n)` | procedure | True if the integer n is odd. |
| `positive?` | `(positive? x)` | procedure | True if the real number x is greater than zero. |
| `quotient` | `(quotient n d)` | procedure | The old name of truncate-quotient. |
| `rational?` | `(rational? x)` | procedure | True if x is a rational number: an exact rational, or a finite float. |
| `rationalize` | `(rationalize x y)` | procedure | The simplest rational number within y of x; inexact if either is. |
| `real?` | `(real? x)` | procedure | True if x is a real number. |
| `remainder` | `(remainder n d)` | procedure | The old name of truncate-remainder. |
| `round` | `(round x)` | procedure | The nearest integer to x, a half going to the even one; a float stays a float. |
| `sin` | `(sin z)` | procedure | The sine of z, in radians. |
| `sqrt` | `(sqrt x)` | procedure | The square root of x: exact for an exact perfect square, else inexact. An error for a negative number (complex numbers are not built in). |
| `square` | `(square z)` | procedure | z times z. |
| `tan` | `(tan z)` | procedure | The tangent of z, in radians. |
| `truncate` | `(truncate x)` | procedure | x with its fraction dropped, toward zero; a float stays a float. |
| `truncate-quotient` | `(truncate-quotient n d)` | procedure | The quotient of n by d, rounded toward zero. |
| `truncate-remainder` | `(truncate-remainder n d)` | procedure | The remainder of n by d after truncate-quotient; it has the sign of n. |
| `truncate/` | `(truncate/ n d)` | procedure | Two values: the quotient of n by d rounded toward zero, and the remainder, which has the sign of n. |
| `zero?` | `(zero? z)` | procedure | True if z is zero, exact or inexact. |

## Lists

| Name | Call | Kind | What it does |
|---|---|---|---|
| `append` | `(append list ... x)` | procedure | A list of the elements of each list in turn, ending in x, which is shared, not copied. |
| `assoc` | `(assoc key alist)` | procedure | The first pair of the association list whose car is equal? to key, or #f. |
| `assq` | `(assq key alist)` | procedure | The first pair of the association list whose car is eq? to key, or #f. |
| `assv` | `(assv key alist)` | procedure | The first pair of the association list whose car is eqv? to key, or #f. |
| `car` | `(car pair)` | procedure | The first element of pair. |
| `cdr` | `(cdr pair)` | procedure | The second element of pair: for a list, the rest of it. |
| `cons` | `(cons a b)` | procedure | A new pair whose car is a and whose cdr is b. |
| `for-each` | `(for-each proc list)` | procedure | Calls proc on each element of list, in order, for its effect. |
| `length` | `(length list)` | procedure | The number of elements of list; an error for an improper or circular list. |
| `list` | `(list x ...)` | procedure | A new list of the arguments. |
| `list?` | `(list? x)` | procedure | True if x is a proper list: finite, and ending in the empty list. |
| `map` | `(map proc list)` | procedure | A new list of the results of calling proc on each element of list. |
| `member` | `(member x list)` | procedure | The first tail of list whose car is equal? to x, or #f. |
| `memq` | `(memq x list)` | procedure | The first tail of list whose car is eq? to x, or #f. |
| `memv` | `(memv x list)` | procedure | The first tail of list whose car is eqv? to x, or #f. |
| `null?` | `(null? x)` | procedure | True if x is the empty list. |
| `pair?` | `(pair? x)` | procedure | True if x is a pair. |
| `reverse` | `(reverse list)` | procedure | A new list of the elements of list in reverse order. |
| `set-car!` | `(set-car! pair x)` | procedure | Replaces the car of pair with x. |
| `set-cdr!` | `(set-cdr! pair x)` | procedure | Replaces the cdr of pair with x. |

## Characters

| Name | Call | Kind | What it does |
|---|---|---|---|
| `char->integer` | `(char->integer char)` | procedure | The Unicode code point of char. |
| `char-alphabetic?` | `(char-alphabetic? char)` | procedure | True if char is a letter. |
| `char-ci=?` | `(char-ci=? c1 c2 ...)` | procedure | True if the characters are the same, ignoring case. |
| `char-downcase` | `(char-downcase char)` | procedure | The lower-case form of char. |
| `char-lower-case?` | `(char-lower-case? char)` | procedure | True if char is a lower-case letter. |
| `char-numeric?` | `(char-numeric? char)` | procedure | True if char is a digit. |
| `char-upcase` | `(char-upcase char)` | procedure | The upper-case form of char. |
| `char-upper-case?` | `(char-upper-case? char)` | procedure | True if char is an upper-case letter. |
| `char-whitespace?` | `(char-whitespace? char)` | procedure | True if char is white space. |
| `char<=?` | `(char<=? c1 c2 ...)` | procedure | True if the code points never decrease. |
| `char<?` | `(char<? c1 c2 ...)` | procedure | True if the code points are strictly increasing. |
| `char=?` | `(char=? c1 c2 ...)` | procedure | True if the characters are all the same. |
| `char>=?` | `(char>=? c1 c2 ...)` | procedure | True if the code points never increase. |
| `char>?` | `(char>? c1 c2 ...)` | procedure | True if the code points are strictly decreasing. |
| `digit-value` | `(digit-value char)` | procedure | The value of the digit char, or #f if it is not a digit. |
| `integer->char` | `(integer->char n)` | procedure | The character with the Unicode code point n. |

## Strings

| Name | Call | Kind | What it does |
|---|---|---|---|
| `list->string` | `(list->string list)` | procedure | A new string of the characters of list. |
| `make-string` | `(make-string k [char])` | procedure | A new string of k characters, each char (a space by default). |
| `number->string` | `(number->string z [radix])` | procedure | The text of the number z, as write writes it, in radix. |
| `string` | `(string char ...)` | procedure | A new string of the characters. |
| `string->list` | `(string->list string [start [end]])` | procedure | A list of the characters of string. |
| `string->number` | `(string->number string [radix])` | procedure | The number string reads as, or #f; radix is 2, 8, 10 or 16. |
| `string->symbol` | `(string->symbol string)` | procedure | The symbol spelled string. |
| `string-append` | `(string-append string ...)` | procedure | A new string of the characters of each string in turn. |
| `string-ci=?` | `(string-ci=? s1 s2 ...)` | procedure | True if the strings are the same, ignoring case. |
| `string-copy` | `(string-copy string [start [end]])` | procedure | A new string of the characters of string from start to end. |
| `string-copy!` | `(string-copy! to at from [start [end]])` | procedure | Copies the characters of from, start to end, into to at index at. |
| `string-downcase` | `(string-downcase string)` | procedure | A new string of string in lower case. |
| `string-fill!` | `(string-fill! string char)` | procedure | Replaces every character of string with char. |
| `string-index` | `(string-index string char)` | procedure | The index of the first char in string, or #f. |
| `string-join` | `(string-join list [separator])` | procedure | A new string of the strings of list, with separator between them. |
| `string-length` | `(string-length string)` | procedure | The number of characters of string. |
| `string-ref` | `(string-ref string k)` | procedure | The character of string at index k, from 0. |
| `string-search` | `(string-search string pattern)` | procedure | The index where pattern first occurs in string, or #f. |
| `string-set!` | `(string-set! string k char)` | procedure | Replaces the character of string at index k with char. |
| `string-split` | `(string-split string char)` | procedure | A list of the parts of string between the occurrences of char. |
| `string-trim` | `(string-trim string)` | procedure | A new string of string without the white space at either end. |
| `string-upcase` | `(string-upcase string)` | procedure | A new string of string in upper case. |
| `string<=?` | `(string<=? s1 s2 ...)` | procedure | True if the strings never decrease, by code point. |
| `string<?` | `(string<? s1 s2 ...)` | procedure | True if the strings are strictly increasing, by code point. |
| `string=?` | `(string=? s1 s2 ...)` | procedure | True if the strings are all the same. |
| `string>=?` | `(string>=? s1 s2 ...)` | procedure | True if the strings never increase, by code point. |
| `string>?` | `(string>? s1 s2 ...)` | procedure | True if the strings are strictly decreasing, by code point. |
| `substring` | `(substring string start [end])` | procedure | A new string of the characters of string from start to end. |
| `symbol->string` | `(symbol->string symbol)` | procedure | A new string of the name of symbol. |

## Vectors

| Name | Call | Kind | What it does |
|---|---|---|---|
| `list->vector` | `(list->vector list)` | procedure | A new vector of the elements of list. |
| `make-vector` | `(make-vector k [fill])` | procedure | A new vector of k elements, each fill. |
| `subvector` | `(subvector vector start end)` | procedure | A new vector of the elements of vector from start to end. |
| `vector` | `(vector x ...)` | procedure | A new vector of the arguments. |
| `vector->list` | `(vector->list vector [start [end]])` | procedure | A list of the elements of vector. |
| `vector-append` | `(vector-append vector ...)` | procedure | A new vector of the elements of each vector in turn. |
| `vector-copy` | `(vector-copy vector [start [end]])` | procedure | A new vector of the elements of vector from start to end. |
| `vector-fill!` | `(vector-fill! vector x)` | procedure | Replaces every element of vector with x. |
| `vector-for-each` | `(vector-for-each proc vector)` | procedure | Calls proc on each element of vector, in order. |
| `vector-length` | `(vector-length vector)` | procedure | The number of elements of vector. |
| `vector-map` | `(vector-map proc vector)` | procedure | A new vector of the results of calling proc on each element of vector. |
| `vector-ref` | `(vector-ref vector k)` | procedure | The element of vector at index k, from 0. |
| `vector-set!` | `(vector-set! vector k x)` | procedure | Replaces the element of vector at index k with x. |
| `vector?` | `(vector? x)` | procedure | True if x is a vector. |

## Hash tables

| Name | Call | Kind | What it does |
|---|---|---|---|
| `alist->hash-table` | `(alist->hash-table alist [equality])` | procedure | A new hash table of the pairs of alist; the first of a repeated key wins. |
| `hash-table->alist` | `(hash-table->alist table)` | procedure | An association list of the keys and values of table. |
| `hash-table-clear!` | `(hash-table-clear! table)` | procedure | Removes every key from table. |
| `hash-table-contains?` | `(hash-table-contains? table key)` | procedure | True if table has a value for key. |
| `hash-table-copy` | `(hash-table-copy table)` | procedure | A new hash table with the keys and values of table. |
| `hash-table-count` | `(hash-table-count table)` | procedure | The number of keys in table. |
| `hash-table-delete!` | `(hash-table-delete! table key)` | procedure | Removes key and its value from table. |
| `hash-table-exists?` | `(hash-table-exists? table key)` | procedure | The old name of hash-table-contains?. |
| `hash-table-keys` | `(hash-table-keys table)` | procedure | A list of the keys of table, in the order they were added. |
| `hash-table-ref` | `(hash-table-ref table key [missing])` | procedure | The value of key in table; if there is none, the result of calling missing, or an error. |
| `hash-table-ref/default` | `(hash-table-ref/default table key default)` | procedure | The value of key in table, or default. |
| `hash-table-set!` | `(hash-table-set! table key value)` | procedure | Associates key with value in table. |
| `hash-table-size` | `(hash-table-size table)` | procedure | The old name of hash-table-count. |
| `hash-table-update!` | `(hash-table-update! table key proc [missing])` | procedure | Replaces the value of key with the result of calling proc on it. |
| `hash-table-update!/default` | `(hash-table-update!/default table key proc default)` | procedure | As hash-table-update!, with default as the value of a missing key. |
| `hash-table-values` | `(hash-table-values table)` | procedure | A list of the values of table, in the order of their keys. |
| `hash-table-walk` | `(hash-table-walk table proc)` | procedure | Calls proc on each key and its value. |
| `hash-table?` | `(hash-table? x)` | procedure | True if x is a hash table. |
| `make-hash-table` | `(make-hash-table [equality])` | procedure | A new hash table comparing keys with equality: eq?, eqv? or equal? (the default). |

## Control

| Name | Call | Kind | What it does |
|---|---|---|---|
| `apply` | `(apply proc list)` | procedure | Calls proc with the elements of list as its arguments. |
| `call-with-values` | `(call-with-values producer consumer)` | procedure | Calls consumer with the values producer answers. |
| `values` | `(values x ...)` | procedure | Answers its arguments as several values; one value is just itself. |

## Conditions and restarts

| Name | Call | Kind | What it does |
|---|---|---|---|
| `abort` | `(abort)` | procedure | Invokes the abort restart. |
| `compute-restarts` | `(compute-restarts)` | procedure | A list of the active restarts, innermost first. |
| `condition-report` | `(condition-report c)` | procedure | The text that describes the condition c, as the runner shows it. |
| `condition?` | `(condition? x)` | procedure | True if x is a condition: anything raised or signalled. |
| `dynamic-wind` | `(dynamic-wind before thunk after)` | procedure | Calls before, thunk and after, and calls after however thunk is left. |
| `error` | `(error message irritant ...)` | procedure | Signals an error with message, and the irritants for its report. |
| `error-object-irritants` | `(error-object-irritants e)` | procedure | The irritants of the error e, as a list. |
| `error-object-message` | `(error-object-message e)` | procedure | The message of the error e. |
| `error-object?` | `(error-object? x)` | procedure | True if x is an error, as error and the system signal them. |
| `file-error?` | `(file-error? x)` | procedure | True if x is an error from opening a file. |
| `find-restart` | `(find-restart name)` | procedure | The innermost active restart named name, or #f. |
| `invoke-restart` | `(invoke-restart restart arg ...)` | procedure | Transfers to the active restart (or the one with that name), with the arguments. |
| `raise` | `(raise obj)` | procedure | Raises obj to the current handlers; a handler that returns is an error. |
| `raise-continuable` | `(raise-continuable obj)` | procedure | Raises obj; the value the handler returns is the value of raise-continuable. |
| `read-error?` | `(read-error? x)` | procedure | True if x is an error from reading. |
| `restart-name` | `(restart-name restart)` | procedure | The name of restart, a symbol. |
| `store-value` | `(store-value x)` | procedure | Invokes the store-value restart with x. |
| `use-value` | `(use-value x)` | procedure | Invokes the use-value restart with x. |
| `with-exception-handler` | `(with-exception-handler handler thunk)` | procedure | Calls thunk with handler handling what it raises. |

## Evaluation and macros

| Name | Call | Kind | What it does |
|---|---|---|---|
| `eval` | `(eval form)` | procedure | Compiles and runs form at top level, and answers its value. |
| `gensym` | `(gensym [prefix])` | procedure | A new uninterned symbol, unlike any other, for a name a macro makes up. |
| `image-build-info` | `(image-build-info)` | procedure | How this image was built: an association list of its seed, the bootstrap and its fixpoint. |
| `macroexpand` | `(macroexpand form)` | procedure | form expanded until it is no longer a macro call. |
| `macroexpand-1` | `(macroexpand-1 form)` | procedure | form expanded once, if it is a macro call; else form itself. |

## Output

| Name | Call | Kind | What it does |
|---|---|---|---|
| `display` | `(display x [port])` | procedure | Writes x for a person: strings and characters as they are, to port or the current output. |
| `newline` | `(newline [port])` | procedure | Writes a line break. |
| `write` | `(write x [port])` | procedure | Writes x so that read reads it back: strings in quotes, characters as #\x. |

## Ports

| Name | Call | Kind | What it does |
|---|---|---|---|
| `char-ready?` | `(char-ready? [port])` | procedure | True: a character can always be read without waiting for it here. |
| `eof-object` | `(eof-object)` | procedure | The eof object, which reading answers at the end of its input. |
| `eof-object?` | `(eof-object? x)` | procedure | True if x is the eof object. |
| `get-output-string` | `(get-output-string port)` | procedure | The string of what has been written to the output string port. |
| `open-input-string` | `(open-input-string string)` | procedure | An input port that reads the characters of string. |
| `open-output-string` | `(open-output-string)` | procedure | An output port that collects what is written to it. |
| `peek-char` | `(peek-char [port])` | procedure | The next character from port, without reading it, or the eof object. |
| `read` | `(read [port])` | procedure | The next datum from port (the current input by default), or the eof object. |
| `read-char` | `(read-char [port])` | procedure | The next character from port, or the eof object. |
| `read-line` | `(read-line [port])` | procedure | The rest of the line from port, without its line break, or the eof object. |
| `read-string` | `(read-string k [port])` | procedure | A string of the next k characters from port, fewer at its end, or the eof object. |
| `with-output-to-string` | `(with-output-to-string thunk)` | procedure | Calls thunk with its output collected, and answers it as a string. |
| `write-char` | `(write-char char [port])` | procedure | Writes char to port. |
| `write-string` | `(write-string string [port])` | procedure | Writes the characters of string to port. |

## Files

| Name | Call | Kind | What it does |
|---|---|---|---|
| `call-with-input-file` | `(call-with-input-file path proc)` | procedure | Calls proc with an input port on the file, closed afterwards. |
| `call-with-output-file` | `(call-with-output-file path proc)` | procedure | Calls proc with an output port on the file, closed afterwards. |
| `close-input-port` | `(close-input-port port)` | procedure | Closes the input port. |
| `close-output-port` | `(close-output-port port)` | procedure | Closes the output port, so what was written is in its file. |
| `close-port` | `(close-port port)` | procedure | Closes port. |
| `command-line` | `(command-line)` | procedure | A list of the program name and its arguments, as strings. |
| `current-error-port` | `(current-error-port)` | procedure | The port for error messages. |
| `current-input-port` | `(current-input-port)` | procedure | The port read reads from by default. |
| `current-load-path` | `(current-load-path)` | procedure | The full path of the file being loaded or run, or #f. |
| `current-output-port` | `(current-output-port)` | procedure | The port display and write write to by default. |
| `delete-file` | `(delete-file path)` | procedure | Deletes the file at path. |
| `file-exists?` | `(file-exists? path)` | procedure | True if there is a file at path. |
| `open-input-file` | `(open-input-file path)` | procedure | An input port reading the file at path. |
| `open-output-file` | `(open-output-file path)` | procedure | An output port writing the file at path, which is replaced. |
| `with-input-from-file` | `(with-input-from-file path thunk)` | procedure | Calls thunk with the current input read from the file. |
| `with-output-to-file` | `(with-output-to-file path thunk)` | procedure | Calls thunk with the current output written to the file. |
| `write-shared` | `(write-shared x [port])` | procedure | Writes x with a datum label for every part it shares, so the sharing reads back. |

## The system

| Name | Call | Kind | What it does |
|---|---|---|---|
| `disassemble` | `(disassemble proc)` | procedure | Writes the bytecode of the procedure proc. |
| `exit` | `(exit [code])` | procedure | Ends the program: (exit) and (exit #t) succeed, (exit #f) fails, (exit n) exits with n. |
| `load` | `(load path)` | procedure | Reads and evaluates every form of the file at path, relative to the file being loaded. |
| `procedure-documentation` | `(procedure-documentation proc)` | procedure | The documentation of proc, or #f: the call form on its first line, then what it does. |
| `procedure-source` | `(procedure-source proc)` | procedure | The text proc was compiled from, or #f for a primitive. |
| `save-image` | `(save-image)` | procedure | Saves the running image, so its definitions are there when it next starts. |
| `stack-depth` | `(stack-depth)` | procedure | The number of frames on the stack, for testing that loops run in constant space. |

## Smalltalk interop

| Name | Call | Kind | What it does |
|---|---|---|---|
| `array->list` | `(array->list array)` | procedure | A list of the elements of a Smalltalk collection. |
| `lisp-symbol` | `(lisp-symbol x)` | procedure | The LISP symbol spelled as x, a Smalltalk symbol or string. |
| `list->array` | `(list->array list)` | procedure | A Smalltalk Array of the elements of list. |
| `procedure->block` | `(procedure->block proc)` | procedure | A Smalltalk block that calls proc, for Smalltalk code that wants one. |
| `smalltalk-global` | `(smalltalk-global name)` | procedure | The Smalltalk global named name (a symbol or a string), or #f. |
| `smalltalk-nil` | `(smalltalk-nil)` | procedure | Smalltalk nil, which is not a LISP value. |
| `smalltalk-nil?` | `(smalltalk-nil? x)` | procedure | True if x is Smalltalk nil. |
| `smalltalk-object?` | `(smalltalk-object? x)` | procedure | True if x is a Smalltalk object that is not also a LISP value. |
| `smalltalk-selector` | `(smalltalk-selector name)` | procedure | The Smalltalk selector spelled name. |
| `smalltalk-send` | `(smalltalk-send receiver selector arg ...)` | procedure | Sends the message selector to receiver with the arguments, chosen at run time. |
| `smalltalk-symbol` | `(smalltalk-symbol name)` | procedure | The Smalltalk symbol spelled name. |

## Language server

| Name | Call | Kind | What it does |
|---|---|---|---|
| `read-framed-message` | `(read-framed-message)` | procedure | The next message on standard input, framed as the Language Server Protocol frames it (a Content-Length header, a blank line, the text), or the eof object. |
| `write-framed-message` | `(write-framed-message text)` | procedure | Writes text to standard output, framed as the Language Server Protocol frames it. |

## The compiler and reader

| Name | Call | Kind | What it does |
|---|---|---|---|
| `compile-form` | `(compile-form datum [reader [context]])` | procedure | The Smalltalk CompiledMethod that runs datum, made by the compiler in use. reader is the LISP reader that read datum, so its procedures keep their text. |
| `define-number-syntax` | `(define-number-syntax predicate parser)` | procedure | A new number syntax for the reader and string->number: a token that no built-in syntax reads and that satisfies predicate is read as (parser token). |
| `define-special-form` | `(define-special-form name [documentation] translator)` | procedure | Makes name a special form of the running compiler: translator, called with the compiler's state, the form, the scope and whether the form is in tail position, answers its code. The documentation is what (documentation name) answers. |
| `documentation` | `(documentation name)` | procedure | The documentation of what the symbol name means: a special form, a macro or a procedure; #f if it has none. Its first line is the call form. |
| `documentation-category` | `(documentation-category name)` | procedure | The section of the reference of the built-ins that name belongs in, or #f. |
| `lisp-eval` | `(lisp-eval datum [reader])` | procedure | Compiles and runs datum with the compiler in use, as eval does. |
| `lisp-eval-string` | `(lisp-eval-string string)` | procedure | Reads and evaluates every datum of string in turn, so procedures keep their text; answers the last value. |
| `make-reader` | `(make-reader string)` | procedure | A reader over string: reader-next reads its datums one at a time. |
| `opal-run` | `(opal-run method)` | procedure | Runs a CompiledMethod that compile-form made, and answers its value. |
| `read-all` | `(read-all string)` | procedure | A list of every datum of string. |
| `read-from-string` | `(read-from-string string)` | procedure | The one datum string holds; an error for none or more than one. |
| `reader-datum-start` | `(reader-datum-start reader)` | procedure | The offset, from 0, at which the datum read last starts. |
| `reader-next` | `(reader-next reader)` | procedure | The next datum, or the eof object at the end of the text. |
| `reader-position` | `(reader-position reader)` | procedure | The offset, from 0, just after what the reader has read. |
| `reader-range-of` | `(reader-range-of reader list)` | procedure | The start and end offsets of the text the reader read the list from, or #f. |
| `reader-source-for` | `(reader-source-for reader list)` | procedure | The text the reader read the list from, or #f. |
| `special-form-names` | `(special-form-names)` | procedure | The names of the special forms, sorted. |
