# Third-party software in this extension

The cog-lisp extension is under the MIT license, like cog-lisp itself. To talk
to cog-lisp's language server it redistributes, unchanged, the npm packages
listed here, bundled into the extension's one script, `dist/extension.js`
(specs/31-vsix-bundle.md). Their license texts, as each package ships them, are
in `dist/THIRD-PARTY-LICENSES.txt`. Building the bundle (`npm run bundle`, which
packaging runs) fails if it holds a package that is not listed here at its
version.

| Package | Version | License | Source |
| --- | --- | --- | --- |
| vscode-languageclient | 9.0.1 | MIT | <https://github.com/microsoft/vscode-languageserver-node> |
| vscode-languageserver-protocol | 3.17.5 | MIT | <https://github.com/microsoft/vscode-languageserver-node> |
| vscode-languageserver-types | 3.17.5 | MIT | <https://github.com/microsoft/vscode-languageserver-node> |
| vscode-jsonrpc | 8.2.0 | MIT | <https://github.com/microsoft/vscode-languageserver-node> |
| semver | 7.8.6 | ISC | <https://github.com/npm/node-semver> |
| minimatch | 5.1.9 | ISC | <https://github.com/isaacs/minimatch> |
| brace-expansion | 2.1.7 | MIT | <https://github.com/juliangruber/brace-expansion> |
| balanced-match | 1.0.2 | MIT | <https://github.com/juliangruber/balanced-match> |
