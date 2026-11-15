# Items

A list of your own rows on the active engine: `pickers.items`. For another
plugin or your config, not a `:Pickers` argument. `pick_item` picks one entry
and is done; a list that is worked in (a task dashboard, a list of repositories
with batch commands) needs keys that act on the marked rows, a preview that is
generated, and the list again after an action. This is that, once for
telescope.nvim, fzf-lua and snacks.nvim.

```lua
require("pickers.items").open({
  items = function() return rows() end,       -- or a list
  title = function(rows) return ("Tasks (%d)"):format(#rows) end,
  preview = function(item) return { file = item.file, line = 1 } end,
  marks = true,
  actions = {
    status = {
      key = "<M-s>",
      desc = "advance the status",
      fn = function(sel, ctx)
        advance(sel)          -- the marked rows, else the one under the cursor
        ctx.reopen()          -- the list again: fresh rows, the query kept
      end,
    },
  },
  on_select = function(item, sel) open(sel) end,
})
```

## The call

| Field | What it is |
| --- | --- |
| `items` | The rows: a list, or a function that returns one and is called on every (re)open. A row is a string or a `Pickers.Item` (`text`, plus any field of your own). An action gets back the very tables you passed in |
| `title` | The prompt title: a string, or a function that gets the rows just read (for counts and filter chips) |
| `preview` | `function(item)` that returns what to show: `{ file, line? }` (the engine's file preview) or `{ lines, ft?, line? }` (text). Without it, a row's own `file` or `previews` is used as in `pick_item` |
| `marks` | `true`: several rows can be marked with the engine's own key (`<Tab>`), and actions and `on_select` get all of them |
| `actions` | Keys of this list, by a name of your choice: `{ key, desc?, fn(sel, ctx) }` |
| `on_select` | `<CR>`: `function(item, sel)`, the first row and all of them |
| `query` | What is typed in the prompt when the list opens |
| `engine_mod` | The engine to use (default: the resolved one) |

`open` returns `false` and says why when the call is not valid, no engine is
installed or the rows cannot be read. `pickers.items.check(opts)` returns the
same findings as a list without opening anything.

## Actions

`fn(sel, ctx)` runs after the list has closed.

- `sel`: the marked rows in the order of the list; without marks the row under
  the cursor; empty when the list shows nothing (an action such as "set a
  filter" needs no row). With `marks` off it holds at most one row.
- `ctx.query`: what was typed in the prompt.
- `ctx.reopen(changes?)`: the list again. `items` and `title` are read anew,
  the query is kept. `changes` replaces fields of the call, for example
  `ctx.reopen({ query = "" })`.

An action that throws is reported by its name and does not take anything down
with it.

**The restart is the re-render.** No engine redraws the list in place here: a
key closes the list, the action runs, and `ctx.reopen()` opens it again with
what was typed. That is the one way that behaves the same on all three engines
(fzf is a process of its own). The marks are gone after a reopen, and so is the
cursor position: the action has just used them.

**Keys are chords**: `<M-s>`, `<C-x>`, `<F5>`. The prompt has the focus on every
engine, a plain letter is typed into it, and fzf-lua binds nothing else. `<CR>`,
`<Tab>`, `<S-Tab>`, `<Esc>` and `<C-c>` belong to the list. Two actions on one
key are refused, whatever the spelling (`<M-s>` and `<A-S>` are one key to
fzf). A key of the call wins over an entry action on the same key (`keys.*` of
the config) inside this list.

`pickers.items.describe(actions)` returns one line per key with its
description, for a help float or a header.

## Columns

```lua
local lines = require("pickers.items").columns({
  { 1, "open", "S", "Fix the thing" },
  { 10, "blocked", "XL", "Another" },
}, { right = { [1] = true } })
--  " 1  open     S   Fix the thing"
--  "10  blocked  XL  Another"
```

Rows of cells as aligned lines, to use as the `text` of the items. A column is
as wide as its widest cell on the screen (wide characters count as they are
drawn); `sep` is what stands between two columns (default two spaces),
`right[i]` aligns column `i` to the right.

## What each engine does

| | telescope.nvim | fzf-lua | snacks.nvim |
| --- | --- | --- | --- |
| Marking | its own multi-selection | `--multi` | its own selection |
| A key | mapped in insert and normal mode | an fzf action | bound on the input and the list |
| The preview callback | a buffer previewer | a text preview (Lua, no shell) | the preview window |
| The query at reopen | `default_text` | `query` | `pattern` |

fzf prints the accepted lines without saying whether a single one was marked or
only under the cursor; it is the row the key acts on either way. The marked rows
reach an action in the order of the list on every engine, not in the order they
were marked. fzf also knows a row only by its line: two rows with the same text
(and no preview callback, which numbers the lines) are one row to it, so give
rows that an action must tell apart different texts.

Checked against the real libraries: keys, marked rows, the preview and the
restart on telescope.nvim and snacks.nvim; the key, the query and the restart on
fzf-lua. Marking in a real fzf-lua could not be driven without a UI and is
pinned on a stand-in.

The adapters take these as optional fields of `pick_item` (`query`, `multi`,
`keys`, `preview`; see `Pickers.PickItemOpts` in
[`engines/@types/init.lua`](../../lua/pickers/engines/@types/init.lua)). A
`pick_item` call that passes none of them is the call it always was.

- **Module:** [`items/init.lua`](../../lua/pickers/items/init.lua)
- **Specs:** `TESTS/items_spec.lua` (the neutral part on a fake engine, each
  adapter against a stand-in of its library)
