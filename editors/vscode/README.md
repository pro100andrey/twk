# twk for VS Code (experimental)

Run and debug twk apps in a terminal of the extension's own, beside the
editor: hot reload on save, switches for what the terminal can do (its
colours, images, keyboard protocol, a screen reader), the twk Inspector
with a pick mode that opens where a widget was made, a log of the
sequences between the app and its terminal, and recording and replay as
asciicast.

It is a prototype: not on the Marketplace, not packaged, tried on Linux
only. It runs from this directory.

```sh
cd editors/vscode
npm install
npm run compile
code --extensionDevelopmentPath=$PWD path/to/your/twk/project
```

Debug and F5 need the Dart extension (Dart-Code); Run needs only the
Dart SDK. Then Ctrl+Shift+P, "twk".

[DESIGN.md](DESIGN.md) is the whole of it: what the first version does
and how to use it (part 0), how it was found out, its architecture, its
tests and what is not in it yet.
