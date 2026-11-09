# HTTP(S) and JSON from LISP: an early slice of Phase 11.6

| | |
|---|---|
| **Status** | JSON (R-3) done (2026-11-09), as the owner directed: null reads as `()`, built from lisp-expert's code. HTTP(S) proposed, a spike first; decision 1 open |
| **Found by** | Reviewing `~/projects/lisp-expert` (2026-11-09), whose weather REPL needed both |
| **Relates to** | Phase 11.6 "Networking from LISP" (specified when reached); this is its first slice, brought forward |

## 1. The gaps, as found

- **HTTPS does not work in the Linux bundle.**
  - The VM's `libSqueakSSL.so` needs `libssl.so.1.0.0` and `libcrypto.so.1.0.0`
    (`objdump -p`, 2026-11-09).
  - The pharo-vm archive has them, and OpenSSL 1.1 too, but the bundles leave
    OpenSSL out (`release/licenses/README.md`). OpenSSL 1.0 has had no security
    support since 2019.
  - Plain HTTP works (`ZnClient`), and so does Windows HTTPS in principle:
    `SqueakSSL.dll` uses Windows' own `CRYPT32` and `Secur32`. That has not been
    checked live in a bundle.
- **`lisp-expert` works around it with `curl`.** It builds a shell command line
  and runs it through `[(smalltalk LibC) system: cmd]`, with the response in
  temporary files. It works, but every program would need its own quoting,
  temporary files and error handling.
- **JSON comes only through interop.** `STONJSON` answers Smalltalk objects:
  - objects are `Dictionary`s with string keys;
  - arrays are `Array`s;
  - `null` is `nil`, which LISP sees as `(smalltalk-nil)`.

  `lisp-expert` wrote `weather/json.lisp` to make that usable (`json-get`,
  `json-null?`, `json-false?`).

## 2. The spike

Each question below is settled by an experiment, recorded here, before the
design is fixed:
1. **Windows HTTPS:** does `ZnClient` fetch an `https://` URL in a Windows
   bundle, with its certificate checked?
2. **Linux HTTPS:** does a newer pharo-vm build than the pinned one link
   `SqueakSSL` against OpenSSL 3 (or 1.1)? If one does, moving the pin
   (CLAUDE.md, "To move to a newer Pharo") and shipping that OpenSSL with its
   license may be the whole fix.
3. **If neither works on Linux**, the fallbacks are:
   - **(a)** the system's `curl`, run with its arguments as an argument list,
     never through a shell;
   - **(b)** a small TLS-capable helper.

   Each is weighed for what it ships, its license, and its failure modes.

## 3. Requirements (subject to the spike)

- **R-1. `(http-request method url [headers] [body] [timeout])`** answers a
  response.
  - Read it with `http-status`, `http-headers` and `http-body`; the body is a
    string, decoded by the response's charset.
  - `(http-get url)` is the short form.
  - A connection failure or a timeout is a condition, not a Smalltalk stack:
    `http: could not connect to host`.
  - A status of 4xx or 5xx is a response, not an error.
- **R-2. HTTPS checks certificates**, and the documentation says how to give a
  timeout. There is no option to turn checking off.
- **R-3. `(json-read string)` and `(json-write value [port])`**, in LISP terms:

  | JSON | cog-lisp |
  |---|---|
  | object | hash table, string keys |
  | array | vector |
  | string, number | string, number |
  | `true`, `false` | `#t`, `#f` |
  | `null` | `()`, the empty list: Common Lisp's `nil`, which `lib/cl.lisp` binds `nil` to |

  - **`null` is the empty list** (owner, 2026-11-09). JSON has no lists (its
    arrays read as vectors), so `()` cannot be mistaken for anything else when
    reading. Writing, `()` writes `null`, and an empty vector writes `[]`.
  - **One trap, documented:** in cog-lisp only `#f` is false, so `()` is true.
    A null value is tested with `null?`, never with a plain `if`. `null` stays
    distinct from `false`, which `lisp-expert` had to separate by hand.
- **R-4. Documented**, with an example in `examples/` that runs offline: JSON
  only, plus HTTP against a local server started by the test. Live network
  checks are opt-in, never part of the suites.
- **R-5. Licenses:** anything shipped (OpenSSL, a helper) gets its license, a
  notices entry and the keep list (CLAUDE.md, "Bundles ship only the VM files
  `release/package.sh` lists").

## 3a. JSON as built (2026-11-09)

- **`lib/json.lisp`** is loaded by the build after `lib/format.lisp`, so
  `json-read` and `json-write` are built in, documented under "Ports".
- **Reading** is Pharo's `STONJSON`, with its result turned into LISP data, as
  `lisp-expert`'s `weather/json.lisp` (`json->lisp`) does.
  - Two differences from that file, both from the spec's table: an array reads
    as a vector, not a list, and `null` reads as `()`, not Smalltalk's `nil`.
  - With arrays as lists, an empty array would have read as `()`, the same as
    `null`.
- **Writing** is new, in LISP:
  - an object's keys are written sorted, so the same table always writes the
    same text;
  - a string is escaped (`\"`, `\\`, `\n`, `\r`, `\t`, `\u` for other control
    characters), and other characters are written as they are;
  - an exact rational is written as a float;
  - a NaN, an infinity, a list, a symbol, or a key that is not a string is an
    error.
  - It writes into a string first, so a value with no JSON writes nothing.
- **Found while checking `STONJSON`:** `1e3` reads as the integer `1000`.
- **Checks:** `tests/lisp/json.lisp`, 33/33; `examples/json.lisp` round-trips an
  order (AC-2) and joins the "Input and output" chapter.

## 4. Acceptance criteria

- **AC-1:** the spike's three answers are recorded here, and the design is
  chosen from them.
- **AC-2:** `examples/json.lisp` round-trips the table in R-3 exactly, including
  `null`, nesting, Unicode and numbers.
- **AC-3:** HTTP: a request to a local test server answers its status, headers
  and body, and a closed port answers the condition of R-1, on Windows and
  Linux.
- **AC-4:** HTTPS: an opt-in check fetches an `https://` URL from a bundle on
  each platform, and fails cleanly against a host whose certificate is invalid.
- **AC-5 (owner, 2026-11-09):** `lisp-expert`'s
  `weather/examples/fetch.lisp` is re-tested once HTTPS is done, on Windows
  and Linux, and fetches Open-Meteo's current weather. Today its curl
  transport fails on Windows: it builds a POSIX shell command (`/tmp`,
  `mkdir -p`, single-quote quoting) and `LibC system:` runs `cmd.exe`. Moving
  it onto the built-in HTTPS replaces that transport.

## 5. Decisions for the owner

1. **Bring this ahead of Phase 11**, or leave networking to 11.6? Proposed: JSON
   now (small, offline, already wanted), and HTTP(S) after the spike shows its
   cost.
2. **How `null` reads:** as `()`, the empty list (owner, 2026-11-09).
