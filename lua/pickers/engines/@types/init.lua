---@module 'pickers.engines.types'
---@brief Engine-related type definitions (adapter interface + call options).

-- ###########################################################################
-- Engine identifier

---@alias Pickers.Engine
---| '"auto"'       # Detect: telescope → fzf → snacks
---| '"telescope"'
---| '"fzf"'
---| '"snacks"'

-- ###########################################################################
-- Engine call-options (passed from action → engine)

---@class Pickers.EngineOpts
---@field roots           string[]
---@field prompt          string
---@field query           string|nil
---@field find_command    string[]|nil
---@field additional_args string[]|nil
---@field on_select      fun(path: string)|nil  pick_files: called with the absolute path of the file the user chose, AFTER the engine's own default action opened it (a multi-selection is not reported). Lets a caller do something with the pick -- filetree.nvim reveals it in its tree -- without replacing what opening does
---@field core            "smart"|"filegrep"|nil  smart: which per-keystroke query core feeds the live picker (default "smart")
---@field find            Pickers.FindOpts|nil   pick_files: full flags (ignored when find_command is set). live_grep: only `.exclude` is honoured (hidden/no_ignore/follow are hardcoded there already)

-- ###########################################################################
-- pick_item

---A richer alternative to a plain string for `pick_item`'s `items`. Only
---`text` is required — everything else (a `file` to preview, or any extra
---field a caller wants to carry through, e.g. filetree.nvim's template
---picker stashing the original template descriptor) rides along untouched:
---`on_select` is always called with the EXACT entry that was in `items`
---(string in, string out; table in, that same table out), never a re-parsed
---copy — so a caller never needs to search its own list back by label.
---@class Pickers.Item
---@field text string   Display text — what's shown and fuzzy-matched against.
---@field file string?  Absolute path to preview. When at least one item in a
---                      `pick_item` call carries this, every engine attaches
---                      its own native file previewer (telescope's
---                      `file_previewer`, snacks' default `preview.file`, or
---                      — since fzf is a separate process with no Lua object
---                      passthrough — a hidden per-line field fzf previews via
---                      a pure-Lua callback). Items without `file` still show
---                      (with no/blank preview) alongside ones that have it.
---@field line integer?  1-based line of `file` to put in view (modes preview).
---@field previews table<string, Pickers.PreviewSpec>?  Switchable previews:
---                      mode name -> what to show (`file`/`line` or `lines`/`ft`,
---                      a `lines` spec may carry a `line` too).
---                      When at least one item carries this, every engine shows
---                      the preview of the current mode and the key
---                      `opts.preview_toggle_key` (default `<M-c>`) cycles the
---                      modes (`opts.preview_modes` fixes their order; else
---                      "normal" first, then alphabetically). A `file` on the
---                      item stands in for a missing "normal" mode. See
---                      `pickers.preview_modes`.

---What `pick_item` takes. The first three fields are the call every caller
---makes. The rest is optional and what `pickers.items` builds its lists from;
---a caller that passes none of it gets the list `pick_item` always was.
---@class Pickers.PickItemOpts
---@field items (string|Pickers.Item)[]
---@field prompt string
---@field on_select fun(item: string|Pickers.Item, env?: Pickers.ItemEnv)  With `multi`, `item` is the first of `env.items`.
---@field preview_modes string[]?        Order of the modes of `Pickers.Item.previews`.
---@field preview_toggle_key string?     Key that cycles them (default `<M-c>`).
---@field preview (fun(item: string|Pickers.Item): Pickers.PreviewSpec|nil)?  A preview worked out per item (a file, or lines); takes the place of the items' own `file`/`previews`.
---@field query string?                  What is typed in the prompt when the list opens.
---@field multi boolean?                 `<CR>` reports every marked row (`env.items`), not only the one under the cursor. Marking itself is the engine's own (`<Tab>`).
---@field keys Pickers.ItemKey[]?        Keys of this call. The engine closes the list, then calls `run`.

---One key of a `pick_item` call.
---@class Pickers.ItemKey
---@field key string   Vim notation with a modifier or a special key (`<M-s>`, `<C-x>`, `<F5>`): the prompt has the focus on every engine, and fzf-lua binds nothing else.
---@field desc string?
---@field run fun(env: Pickers.ItemEnv)

---What a key (or `<CR>` with `multi`) acts on.
---@class Pickers.ItemEnv
---@field items (string|Pickers.Item)[]  The marked rows in the order of the list; without marks the row under the cursor; empty when the list shows nothing.
---@field query string                   What was typed in the prompt.

return {}
