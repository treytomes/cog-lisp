# Third-party software in this bundle

This bundle redistributes, unchanged, software from the Pharo project, as
published at <https://files.pharo.org>:

- **The Pharo virtual machine** (`pharo/` on Linux; `pharo\` on Windows): the
  OpenSmalltalk-derived Cog VM built by the Pharo project, released under the
  MIT license. Source and license: <https://github.com/pharo-project/pharo-vm>.
  The VM folder also contains third-party libraries the Pharo project ships with
  its VM (for example SDL2, cairo, FreeType, libgit2, OpenSSL, libffi). Each is
  under its own license, as distributed by the Pharo project; see the pharo-vm
  repository for the list and their terms.
- **The Pharo 14 image and its sources file**: cog-lisp's image is built from the
  stock Pharo 14 image and includes it. Pharo is released under the MIT license.
  Source and license: <https://github.com/pharo-project/pharo>.
