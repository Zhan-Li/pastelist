# PasteList

**Copy anything. Paste it. It's a checklist.**

PasteList is a tiny macOS menu bar app with one job: turn whatever text you
paste into a checklist you can tick off. A meeting agenda, a recipe, a
numbered list from an email, a Markdown todo block — paste it, select the
lines, press Tab, and every line becomes a checkbox.

```
   Shopping:                          ☐ Shopping:
   - milk                             ☐ milk
   1. eggs             ──Tab──▶       ☐ eggs
   - [x] bread                        ☑ bread
   • call the plumber                 ☐ call the plumber
```

No document to save, no window to find. It lives in the menu bar and the
list is still there next time you open it.

## What it does

- **Paste is just paste.** ⌘V puts the text in exactly as copied.
- **Tab makes a line an item.** Press Tab on a line, or select several lines
  and press Tab, and each gets a box. Bullets (`-`, `*`, `•`, `>`), numbering
  (`1.`, `2)`, `(3)`, `a.`), and checkbox syntax (`- [ ]`, `- [x]`, `☐`, `☑`,
  `✓`) are stripped, and lines already marked done arrive checked. Shift-Tab
  takes the boxes off again.
- **It is just text.** The popover is one document, like a note. Click
  anywhere and type. Enter starts the next item, Enter on an empty item
  drops its box, Backspace right after a box removes it. Click a box to tick
  it, or press ⌘↩ on the line. Undo works.
- **Copy it back out** as Markdown (`- [x] done`, `- [ ] not yet`) from the
  ⋯ menu, so the list can go into a note, a message, or a pull request.
- **Remembers the list** between launches. The footer shows how many are
  done, and has four buttons: shortcuts, copy, clear, quit. Hover one for a
  hint. That is the entire interface.

## Shortcuts

The ⌨ button in the footer shows these inside the app too.

| Keys | What happens |
|---|---|
| ⌘V | Paste text, exactly as copied |
| ⇥ | Give this line, or every selected line, a checkbox |
| ⇧⇥ | Take the checkbox off |
| ⌘↩ | Tick or untick this line |
| ↩ | Next item. On an empty item, drops its box |
| ⌫ | Right after a box, removes the box |
| ⌘Z | Undo |
| ⇧⌘C | Copy the list as Markdown |

And that is all. It is not a task manager.

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel (universal binary)

## Install

**Download** the latest `.dmg` from
[Releases](https://github.com/Zhan-Li/pastelist/releases), open it, and drag
**PasteList** onto the Applications shortcut.

**First launch.** PasteList is not signed with a paid Apple Developer ID, so
Gatekeeper refuses the first open. Either:

- **Right-click** the app ▸ **Open** ▸ **Open** in the dialog, or
- run `xattr -dr com.apple.quarantine /Applications/PasteList.app`

Once per install, not once per launch. PasteList needs no Accessibility or
other privacy permissions.

## Build from source

Only the Xcode Command Line Tools are needed (`xcode-select --install`).

```
git clone https://github.com/Zhan-Li/pastelist.git
cd pastelist
./build.sh --run
```

`build.sh` produces a universal `build/PasteList.app`. Set
`PASTELIST_ARCH=native` for a faster single-architecture dev build.
`release.sh` wraps it in a `.dmg` under `dist/`.

## Layout

```
Sources/
  App.swift          MenuBarExtra entry point
  ContentView.swift        the popover: the document plus a slim footer
  ChecklistTextView.swift  NSTextView subclass: paste, Enter, Backspace, click-to-tick, styling
  Model.swift              the text→checklist parser, Markdown export, persistence
Resources/
  Info.plist
build.sh             swiftc build, universal, ad-hoc signed
release.sh           build + package as .dmg
```

## License

MIT — see [LICENSE](LICENSE).
