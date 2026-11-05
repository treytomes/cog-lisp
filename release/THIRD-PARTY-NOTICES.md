# Third-party software in this bundle

cog-lisp itself is under the MIT license (`LICENSE`). This bundle also
redistributes, unchanged, the software listed here. Each is under its own
license, whose full text is in `licenses/`. The exact Pharo builds are pinned in
cog-lisp's `pharo.pins`, as published at <https://files.pharo.org>.

## The Pharo 14 image and its sources file

`pharo/cog-lisp.image`, `pharo/cog-lisp.changes` and `pharo/Pharo14.0-*.sources`.
cog-lisp's image is built from the stock Pharo 14 image (build 788, commit
`58e29ca31d`) and contains it.

- License: the MIT License, with parts under the Apache License 2.0, as stated by
  the Pharo project: `licenses/Pharo-LICENSE.txt` (verbatim, with the Pharo
  copyright notices). The Apache License 2.0: `licenses/Apache-2.0.txt`.
- That file also gives the licenses of the icons and fonts the image contains:
  icons by Mark James (famfamfam.com, Creative Commons Attribution 2.5) and by
  Eclipse (Eclipse Public License 1.0); Source Code Pro by Adobe (SIL Open Font
  License 1.1: `licenses/OFL-1.1.txt`); Open Sans by Steve Matteson (Apache
  License 2.0); the Bitstream Vera fonts (license text in
  `licenses/Pharo-LICENSE.txt`).
- Source: <https://github.com/pharo-project/pharo>.

## The Pharo virtual machine

The VM executable and its plugins (`pharo/` on Linux, `pharo\` on Windows),
from pharo-vm v12.0.6-beta, commit `bebdbac`: the OpenSmalltalk-derived Cog VM.

- License: MIT: `licenses/pharo-vm-LICENSE.txt` (verbatim).
- Source: <https://github.com/pharo-project/pharo-vm>.

## libffi 3.3

`pharo/lib/libffi.so` (Linux), `pharo\ffi.dll` (Windows): the foreign function
interface library, built by the pharo-vm project from
<https://github.com/pharo-project/libffi> (tag `v3.3-cmake`).

- License: MIT: `licenses/libffi-LICENSE.txt` (verbatim).

## winpthreads 6.0.0 (Windows only)

`pharo\libwinpthread-1.dll`: the POSIX threads library of the mingw-w64 project,
which the Windows VM is linked against.

- License: MIT, with parts under a BSD license (Lockless Inc.):
  `licenses/winpthreads-COPYING.txt` (verbatim).
- Source: <https://github.com/mingw-w64/mingw-w64>.

## Left out

The pharo-vm archives also contain third-party libraries that cog-lisp does not
use, and this bundle leaves them out: cairo, pixman, FreeType, fontconfig,
HarfBuzz, libpng, expat, bzip2, zlib, iconv, libgcc, SDL2 and SDL3, libgit2,
libssh2, OpenSSL, the JPEG plugin that contains libjpeg, a test library, and the
GUI `Pharo.exe`. Because of that, the parts of the Pharo image that need them
(drawing with Cairo, fonts, windows, Git, HTTPS on Linux) do not work in this
bundle. They will come back, with their licenses, when cog-lisp adds graphics
and networking.
