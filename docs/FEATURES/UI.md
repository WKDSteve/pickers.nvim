# UI

What the plugin draws itself, as opposed to what the engine draws.

## The pickers that pick a picker

`:Pickers` with an argument missing does not error — it asks. Omitting the
scope opens a scope picker listing every built-in scope and every registered
collection; omitting the action opens an action picker; `dir` with no
navigation argument opens a navigation picker first.

They use `ui.kit.select` when lib.nvim is installed and fall back to
`vim.ui.select` otherwise — a `pcall` per call, so a missing lib.nvim degrades
the prompt rather than breaking the command. Either way the plugin does not
introduce a fourth selection UI of its own.

- **Module:** [`ui/scope_picker.lua`](../../lua/pickers/ui/scope_picker.lua),
  [`ui/action_picker.lua`](../../lua/pickers/ui/action_picker.lua),
  [`ui/dir_nav_picker.lua`](../../lua/pickers/ui/dir_nav_picker.lua)
- **Usercmds:** `:Pickers`, `:Pickers cwd`, `:Pickers dir`

## Result count

Shows the live match count in the prompt window's title — `Find Files (128)`.

**Telescope only, and off by default.** fzf-lua and snacks both show a
position/total counter natively, so this is skipped there rather than drawn
twice.

It polls the entry manager every 150 ms while the results buffer is open rather
than hooking an event, because a live finder streams matches in asynchronously
and there is no `CursorMoved` or `TextChanged` to hang an update off.

- **Module:** [`result_count/init.lua`](../../lua/pickers/result_count/init.lua)
- **Config:** `result_count = { enabled }` (default `false`)

## Long-path shortening

Cosmetic, off by default. Shortens long paths in the results list through each
engine's own native mechanism — `path_display = { "shorten" }` on telescope,
`path_shorten = true` on fzf-lua, and a no-op on snacks, which already
truncates to the available column width.

No pickers.nvim-side logic: three engines that already solve this get their own
switch flipped, rather than a fourth implementation.

- **Module:** [`engines/`](../../lua/pickers/engines/) — per adapter
- **Config:** `display.path_shorten` (default `false`)

## Health check

`:checkhealth pickers` reports, in this order: the required dependencies, which
picker engines are installed and which one resolves, whether `rg` and `fd` are
on `PATH` (`fdfind` counts), the merged configuration, whether image previews
are active and whether a PDF page can be rasterized, the registered
collections, and the external tools declared in `docs/install.json`. The
`:Pickers` command tree adds a section of its own through lib.nvim's composer.

- **Module:** [`health.lua`](../../lua/pickers/health.lua)
- **Usercmds:** `:checkhealth pickers`

## Mouse in the preview and the result list

With the snacks engine, the preview and the result list react to the mouse (telescope and fzf-lua
below):

- **Double click in the preview** asks "Jump to file:line?" in the kit dialog of `lib.nvim.ui.dialog` ("No" is the default); on yes the picker closes and the
  file opens in a new buffer on the clicked line.
- **Right click in the preview or the list** opens a context menu (needs
  `lib.nvim.contextmenu`, which ui.nvim re-exports): open in the current window, split, vsplit or
  tab, open with the system app; copy the selection, the line, the whole file content, the path,
  `path:line` or a Markdown link `[name](path)` (built like the insert-link action, for the window
  behind the picker); with a selected path and gopath.nvim installed, jump to that path; with
  filetree.nvim installed, reveal the row's file in its tree ("Reveal in filetree"); with
  mdview.nvim installed and a Markdown row, open it in mdview's browser preview ("Preview in
  mdview"); with gitsuite.nvim installed and a row that has a line, show who last changed that
  line ("Blame this line (gitsuite)", a notification; the picker stays open); and for the whole
  list copy all entries, send them to the quickfix list or open them in a new buffer.

The right click works while you are still typing in the input field: the menu is for the row or
preview line under the pointer, and it opens above the picker's own windows. The maps are
buffer-local and exist only while a picker window is current.

The other engines, as far as their windows allow
([`preview_mouse_engines.lua`](../../lua/pickers/preview_mouse_engines.lua)):

- **telescope:** the right click in the result list and the preview, the same menu (the list
  entries too). It is bound in the prompt, so it works while you type. There is no own double
  click: telescope's own single click in the preview already opens the entry.
- **fzf-lua** with the builtin previewer: after a click into the preview, the double click and the
  right click work there. The result list is fzf itself in a terminal, with no rows to bind, so
  the menu has no list entries; a shell previewer (a terminal too) is not covered.

- **Module:** [`preview_mouse.lua`](../../lua/pickers/preview_mouse.lua)
- **Config:** `preview_mouse` (default `true`)
- **Sheet:** [`pickers-mouse-snacks`](../../TESTS/sheets/pickers-mouse-snacks.sheet.lua) clicks
  with the mouse on the real snacks picker and the real filetree.nvim
- **Sheet:** [`pickers-mouse-blame-gitsuite`](../../TESTS/sheets/pickers-mouse-blame-gitsuite.sheet.lua)
  blames a preview line through the real gitsuite.nvim in a real git repository
