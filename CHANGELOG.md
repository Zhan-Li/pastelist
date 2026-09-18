# Changelog

## 1.3.0

- Tabs. ⌘T (or the + at the top) opens another list beside the first, and
  the popover shows one at a time. Double-click a tab, or right-click ▸
  Rename, to name it. ⌘1–9 jump to a tab; ⇧⌘[ and ⇧⌘] step through them.
- Every tab gets its own colour, chosen automatically from the label
  palette so neighbouring tabs never match.
- Each tab remembers its own cursor and has its own undo history. Closing
  the last tab empties it rather than leaving nothing to type into.
- The Labels panel now lists labels from every tab, so a label made on one
  list is one click away on another. The menu bar icon reads as all-done
  only when every tab is.
- The list from 1.2 becomes the first tab on upgrade.

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
