# Licenses: what the release bundles ship, and why

This folder holds the full license text of everything a cog-lisp release bundle
redistributes. `release/package.sh` copies these into each bundle's `licenses/`,
and `release/THIRD-PARTY-NOTICES.md` (copied as the bundle's notices) says which
text covers which file. This page records how that was decided (2026-11-04, for
v0.1.2), so the next change to the Pharo pins or the bundles can repeat the
check instead of rediscovering it.

## The question, and the answer

cog-lisp is MIT. Is that compatible with Pharo's licenses? **Yes**: Pharo is MIT
with parts under Apache 2.0, the VM is MIT, and both allow redistribution inside
an MIT project. But MIT is not "nothing to do": **every copy must carry the
copyright and permission notice**. The first bundles (v0.1.0, v0.1.1) only
linked to the Pharo repositories and said the VM folder held "libraries under
their own licenses". That does not satisfy MIT, and the VM archives turned out
to hold many more third-party libraries, under many licenses, than cog-lisp uses.

The owner had no corporate IP policy to satisfy (2026-11-04); the work was to
"correctly play along with the Pharo licenses".

## The texts here

| File | Covers | Source (pinned) |
|---|---|---|
| `Pharo-LICENSE.txt` | the Pharo 14 image and `.sources` (MIT, parts Apache 2.0; icon and font notices; the Bitstream Vera text) | `pharo-project/pharo` at `58e29ca31d` (build 788), `LICENSE`, verbatim |
| `Apache-2.0.txt` | the Apache-licensed parts of Pharo, and Open Sans | apache.org |
| `OFL-1.1.txt` | Source Code Pro, a font in the image | openfontlicense.org |
| `pharo-vm-LICENSE.txt` | the VM executable, `PharoVMCore`, the plugins, `libtty` | `pharo-project/pharo-vm` at `bebdbaca8` (v12.0.6-beta), `LICENSE`, verbatim |
| `libffi-LICENSE.txt` | `libffi.so` / `ffi.dll` | `pharo-project/libffi` tag `v3.3-cmake`, `LICENSE` (pharo-vm's `cmake/importLibFFI.cmake` names that tag) |
| `winpthreads-COPYING.txt` | `libwinpthread-1.dll` (Windows only) | `mingw-w64` tag `v6.0.0`, `mingw-w64-libraries/winpthreads/COPYING` (the DLL's build paths name winpthreads 6.0.0) |

Pharo's own LICENSE names, but does not contain, the Creative Commons BY 2.5
(famfamfam icons) and Eclipse Public License 1.0 (Eclipse icons) texts; it
attributes them and links them. The bundles follow Pharo's own practice there.

## What the VM really loads

Measured with `objdump` in a Docker container (`binutils`), on the pinned VM
archives:

- **Linux** (`objdump -p lib/libPharoVMCore.so | grep NEEDED`): `libffi.so`,
  plus system libraries only (`libdl`, `libm`, `libpthread`, `libc`). The plugins
  need only system libraries, except `libSqueakSSL.so`, which needs OpenSSL
  1.0 (`libssl.so.1.0.0`, `libcrypto.so.1.0.0`). `libtty.so` is pharo-vm's own
  (`src/tty/tty.c`, one function, `tty_spawn`). SDL2 is only `dlopen`ed by the
  image, for windows.
- **Windows** (`objdump -p … | grep 'DLL Name'`): `PharoConsole.exe` imports
  `PharoVMCore.dll` and system DLLs. `PharoVMCore.dll` imports `ffi.dll`,
  **`libwinpthread-1.dll`**, and system DLLs (`KERNEL32`, `USER32`, `SHELL32`,
  `ole32`, `WS2_32`, `dbghelp`, `msvcrt`). `SqueakSSL.dll` uses Windows'
  own `CRYPT32` and `Secur32`, not OpenSSL. Nothing imports `iconv.dll`;
  `zlib1.dll` is imported only by cairo, FreeType and libpng; `libgcc_s_seh-1.dll`
  only by cairo, fontconfig, HarfBuzz and pixman.
- **`JPEGReadWriter2Plugin`** contains libjpeg 6b (it carries "Copyright (C)
  1998, Thomas G. Lane" and `jpeglib.h` paths), whose license asks binary
  distributions to credit the Independent JPEG Group. `JPEGReaderPlugin` is
  pharo-vm's own code.

## What was left out, and the evidence it is unused

Left out of both bundles: cairo, pixman, FreeType, fontconfig, HarfBuzz, libpng,
expat, bzip2, libgit2, libssh2, OpenSSL, SDL2, `TestLibrary`,
`JPEGReadWriter2Plugin`; on Windows also zlib, iconv, libgcc, SDL3, the
`*.dll.a` import libraries and the GUI `Pharo.exe` (useless without SDL).

With those files removed from the local `pharo/` folder, **every suite passed**:
Windows 2506/2506, Linux 2509/2509 with each compiler. The packaged bundles then
passed their smoke tests (Linux 34/34, Windows 35/35), in CI and here.

Two of them would have brought more than a notice: **cairo and iconv are LGPL**,
which asks a distributor to offer their source. Others carry their own notices
(OpenSSL 1.0/1.1's dual license, libpng, FreeType's FTL, libgit2's GPLv2 with a
linking exception, the BSD-style libssh2 and bzip2, the zlib-style SDL and
zlib, libgcc's GPL with the runtime exception, libjpeg's IJG credit).

**What that costs**: in a bundle, the parts of the Pharo image that need those
libraries do not work: drawing with Cairo, fonts, OS windows, Git, and on Linux
HTTPS (`SqueakSSL` cannot load without OpenSSL 1.0, which modern distributions
lack anyway). Plain sockets and everything cog-lisp does work. The image itself
is unchanged; Phase 11.6 (networking) and 11.7 (graphics) bring libraries back
deliberately.

## How the bundles stay this way

- `release/package.sh` copies **only the VM files on its keep lists** (and has
  drop patterns for the files above). A VM file in neither list, or a kept file
  missing from the archive, stops the packaging: a new VM build cannot slip a
  library, and its license, into a bundle unnoticed.
- `release/smoke-test.sh` checks that every `licenses/*.txt` the notices name is
  in the bundle, and that the VM folder holds nothing but the VM, its plugins,
  libffi and winpthreads.

## When the pins change, or a library is wanted

1. Fetch the new `LICENSE` files at the pinned commits and diff them with these.
2. List the new archives and rerun the `objdump` checks above.
3. For a library to ship: read its license (LGPL means offering source), add it
   to a keep list in `release/package.sh`, its text here, and an entry in
   `release/THIRD-PARTY-NOTICES.md`.
4. Run every suite with the bundle's file set, then a release dry run
   (`gh workflow run release.yml -f version=X-dryrun`).
