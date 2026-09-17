# Changelog

## 1.2.0

- Labels. Type `#p1`, `#blocked`, any word, on a line and it is drawn as a
  coloured pill. Nothing is predefined; every label is one you typed. Colours
  are assigned automatically, least-used first, and remembered per label.
- A Labels panel (⌘L, or the tag button in the footer) lists the labels in
  the document. Click one to put it on the current line or take it off, or
  type a new one and press Enter.
- Labels are plain text, so they survive copy, undo and Markdown export.

## 1.1.0

- An app icon: a blue tile with a ticked-off list, so PasteList is
  recognisable in Finder, the DMG and the Gatekeeper dialog.

## 1.0.0

- First release.
- Menu bar popover holding one free-form document.
- Tab turns the current or selected lines into checklist items, stripping
  bullets, numbering and existing `- [ ]` / `☐` / `✓` markers; lines already
  marked done come in checked. Shift-Tab removes the boxes.
- Items are editable, reorderable, and persist across launches.
- Copy the whole list back out as Markdown (⇧⌘C).
- Checkboxes are drawn by hand: a thin rounded outline when open, a soft accent tint with a checkmark when done. Pointing-hand cursor over each.
- A ⌨ button in the footer lists every shortcut; footer buttons show a hint on hover.
