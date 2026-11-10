# HTTP(S) and JSON from LISP: an early slice of Phase 11.6

| | |
|---|---|
| **Status** | Done (2026-11-09): JSON (R-3), then HTTP(S) after the spike (§2a), with the design (§3b) accepted with decisions 3 to 5 as leaned: curl on every platform, hidden inside cog-lisp. As built: §3c |
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

## 2a. The spike's answers (2026-11-09)

1. **Windows: `ZnClient` fetches `https://` URLs, but certificates are not
   enforced.**
   - It fetched `example.com` and Open-Meteo, and also `expired.badssl.com`,
     `self-signed.badssl.com`, `untrusted-root.badssl.com`,
     `wrong.host.badssl.com` and `revoked.badssl.com`, all with status 200.
     Windows' own TLS (`curl.exe`, Schannel) refuses all five.
   - `SqueakSSL` does report some problems:
     `ZdcPluginSSLSession>>certificateVerificationState` is 4 (expired) or 2
     (untrusted root). Zinc's `ZdcSecureSocketStream>>connect` never reads it.
   - **It cannot be made safe from the image.** For `wrong.host` the plugin
     answers state 0 and gives `wrong.host.badssl.com` as the certificate's
     name, though the certificate names only `*.badssl.com` and `badssl.com`.
     It does not check revocation either (state 0 for `revoked`).
2. **Linux: no newer VM helps.** The pinned v12.0.6-beta (2026-10-23) is the
   newest build on files.pharo.org, and its `libSqueakSSL.so` needs OpenSSL
   1.0, unsupported since 2019. Fixing the plugin means changing the VM, which
   cog-lisp does not do (Path A).
3. **Fallback (a), the system's curl, works, run with no shell:**
   - **Windows:** `CreateProcessW` (uFFI) runs
     `C:\Windows\System32\curl.exe` (curl 8.21, Schannel, part of Windows
     since 2018). Its exit code tells the failures apart: 60 for a wrong host,
     35 for a revoked certificate, 0 for `example.com`. It works through this
     machine's network, which intercepts TLS (its root is in the Windows
     store).
   - **Linux:** `posix_spawnp` and `waitpid` (uFFI, `libc.so.6`) run a program
     with an exact argument list: the file name `a b'c"d $HOME;x` arrived
     intact. A missing program is an error code, not a crash.
   - **The VM keeps running while curl does:** the wait polls (`WNOHANG`, or a
     zero timeout) with a 10 ms `Delay`, so other Smalltalk processes run, such
     as a test's local server.
   - Fallback (b), a helper of our own, would be a TLS client to build, ship
     and license: curl already is one, kept current by the system.

## 3. Requirements (as first proposed; §3b settles them for HTTP)

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

## 3b. HTTP(S) design, from the spike

- **R-6. Transport: the system's curl, for `http://` and `https://` alike**
  (decision 3), run without a shell (§2a.3).
  - Found as `COGLISP_CURL` if set, else `%SystemRoot%\System32\curl.exe` on
    Windows, else `curl` on the `PATH`. None found is a condition: `http: curl
    was not found (set COGLISP_CURL)`.
  - Every value from the program goes to curl as one argument. On Windows that
    means one command line, quoted by the rules `CommandLineToArgvW` reads, so
    each argument arrives exactly.
  - The response comes back through files in a private temporary folder, which
    is deleted after each request: `-o` (the body), `-D` (the headers) and
    `--stderr` (curl's message). Nothing goes through stdout.
  - Always passed: `-sS`, `--proto =http,https` (so a redirect cannot turn
    into `file:` or another scheme), `--max-time`, and `-L --max-redirs 10`
    (decision 4). Never passed: `-k` / `--insecure`.
- **R-7. The interface** (R-1, made exact):
  - `(http-request method url [headers] [body] [timeout])`:
    - `method` is a symbol or string (`GET`, `POST`, ...);
    - `headers` an alist of `(name . value)` strings;
    - `body` a string, sent as UTF-8, or `#f`; with no `Content-Type` among the
      headers it is sent as `text/plain; charset=utf-8` (curl's own default,
      `application/x-www-form-urlencoded`, would be wrong for a string);
    - `timeout` seconds, 30 by default.
  - `(http-get url [headers] [timeout])` is `GET` with no body.
  - The response is a record:
    - `(http-status r)`: an integer;
    - `(http-headers r)`: an alist with names in lower case, in order, of the
      last response after redirects;
    - `(http-header r name)`: the first value of that name, or `#f`;
    - `(http-body r)`: a string, decoded by the `Content-Type` charset, UTF-8
      when there is none.
  - A 4xx or 5xx status is a response, not an error.
- **R-8. Failures are conditions** (`error-object?`), whose message starts with
  `http:` and names the host:
  - `http: could not connect to <host>` (curl 6 and 7: name or connection);
  - `http: timed out after <n> s: <url>` (28);
  - `http: certificate rejected by <host>: <curl's message>` (35, 51, 58, 60
    and the other TLS codes);
  - `http: request failed (curl <n>): <curl's message>` for the rest;
  - a header name or value holding CR or LF, or a URL whose scheme is not
    `http` or `https`, is an error before curl runs.
- **R-9. Certificates (R-2):** curl's own checks, with the system's trust
  store. There is no option to turn them off. On Windows (Schannel) that
  includes revocation; on Linux, curl with OpenSSL checks the chain, the dates
  and the host name, and checks revocation only if the server staples it. A
  proxy is curl's: `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY`.
- **R-10. Running a program is cog-lisp's own** (`LispProcess` in
  `src/coglisp-runtime.st`): an argument list in, an exit code out, with the
  polling wait of §2a.3. It is not a LISP primitive yet (Phase 11.6 decides
  that); `http-request` is its only user.
- **R-11. Licenses (R-5):** nothing is shipped. curl is the system's, as
  `cmd.exe` and `libc` are. The documentation says HTTP needs curl on Linux.
- **R-12. Tests and the example (R-4):**
  - `tests/lisp/http.lisp` starts a `ZnServer` on `127.0.0.1` in the same
    image, which the polling wait lets run. It checks:
    - status, headers and body of a `GET`;
    - a `POST` body and headers echoed back;
    - a 404 as a response;
    - a redirect followed;
    - a charset decoded;
    - a closed port, a timeout, a CR/LF header, a `file:` URL and a missing
      curl as their conditions.
  - A live check, run only with `COGLISP_LIVE_HTTPS=1` (AC-4), fetches
    `https://example.com/` and expects the five `badssl.com` hosts of §2a to
    fail as `certificate rejected`.
  - `examples/http.lisp` fetches from a local server it starts by interop, so
    the manual's example runs offline.
- **R-13. lisp-expert (AC-5):** `weather/transport.lisp`'s `zn-transport` and
  `curl-transport` give way to `http-request`, keeping its `make-response`
  shape for its callers; committed only with the owner's go-ahead.

## 3c. HTTP(S) as built (2026-11-09)

- **`lib/http.lisp`**, loaded by the build after `lib/json.lisp` (so built in,
  category "Network"): `http-request`, `http-get`, `http-response?`,
  `http-status`, `http-headers`, `http-header`, `http-body`.
- **`LispProcess` and `LispHttpResponse`** in `src/coglisp-runtime.st`:
  - `run:` runs a program from an Array of Strings (Windows `CreateProcessW`
    with `CommandLineToArgvW` quoting; POSIX `posix_spawnp`), and answers its
    exit code, or `nil` when it cannot be started;
  - `curlProgram` finds curl (`COGLISP_CURL`, Windows' `System32\curl.exe`,
    else `curl` on the `PATH`);
  - `curl:body:` adds the file arguments, runs it, reads the files and deletes
    its folder;
  - `decode:charset:` decodes bytes (UTF-8 when the charset is missing or
    unknown).
- **Always passed to curl:** `-q` (no `.curlrc`), `-sS`, `--proto` and
  `--proto-redir =http,https`, `-L --max-redirs 10` and `--max-time`. A `HEAD`
  is `--head`, any other method `-X`.
- **Added while doing it:**
  - **A body is sent as `text/plain; charset=utf-8`** unless the headers give
    a `Content-Type`. Without it curl says `application/x-www-form-urlencoded`,
    and the test server parsed a POST's body as a form.
  - **`(url-encode string)`**, RFC 3986 percent-encoding of the UTF-8 bytes.
    `lisp-expert`'s query parameters needed it, and a program should not need
    Smalltalk to build a query string.
  - `release/smoke-test.sh` gained the opt-in live check of AC-4.
- **Checks:**
  - `tests/lisp/http.lisp`: 50 checks against a `ZnServer` in the same image;
    55 with `COGLISP_LIVE_HTTPS=1`, on Windows and Linux (AC-3, AC-4).
  - `examples/http.lisp`, in the "Input and output" chapter, runs offline from
    a bundle on both platforms.
  - Both release bundles, built in Docker, pass the smoke test with
    `COGLISP_LIVE_HTTPS=1`: each fetches `https://example.com/` and refuses
    `expired.badssl.com` (AC-4).
- **AC-5:** `lisp-expert`'s `weather/examples/fetch.lisp` fetches Open-Meteo's
  current weather on Windows and on Linux.
  - Its transport is now `http-request`; its own `http-request`, which had a
    different signature and would have replaced the built-in, is
    `weather-request`.
  - Its curl HTTPS test, which failed on Windows, passes (17/17).
- **Found:**
  - cog-lisp's `apply` takes exactly two arguments.
  - The local Docker container had no curl; it got it with `apt-get`.

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

1. **Ahead of Phase 11:** yes; JSON first, then HTTPS, before Phase 11
   (owner, 2026-11-09).
2. **How `null` reads:** as `()`, the empty list (owner, 2026-11-09).
3. **The transport is the system's curl** (R-6), for `http://` too. The
   alternatives:
   - Zinc for `http://`: no curl needed for plain HTTP, but two behaviors;
   - shipping OpenSSL 1.0 for `SqueakSSL`: unsupported, and Windows would
     still accept a wrong host.

   Leaning: curl for both.
4. **Redirects are followed** (up to 10, within `http`/`https`), as Zinc and
   browsers do. Leaning: follow them.
5. **HTTP needs curl on Linux:** most distributions have it, but a minimal
   container may not; the condition says so. Leaning: accept, and document it.
