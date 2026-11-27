---@module 'pickers.engines.fzf'
---@brief fzf-lua adapter — implements the pickers engine interface.
---@description
--- Interface contract (all methods that pickers.nvim calls on an engine):
---   available()        → boolean
---   pick_files(opts)   → nil
---   live_grep(opts)    → nil
---   smart(opts)        → nil   (combined grep + find, the `smart` action)
---   pick_item(opts)    → nil   (used by repos / collection sources)
---   pick_dir(opts)     → nil   (used by folder source)
---
--- Escape behaviour (double-escape to close):
---   fzf runs inside a Neovim terminal buffer.  A terminal-mode <Esc> keymap
---   is injected via winopts.on_create BEFORE fzf reads stdin, so Neovim
---   intercepts the key first:
---     1st <Esc>  (t-mode)  →  <C-\><C-n>  →  Normal mode of the fzf buffer
---     2nd <Esc>  (n-mode)  →  nvim_win_close  →  fzf process exits

local notify = require("lib.nvim.notify").create("[pickers.engines.fzf]")

local M = {}

-- ── Double-escape helper ─────────────────────────────────────────────────────

---Injected into winopts.on_create for every fzf-lua call.
---Sets buffer-local t-mode and n-mode <Esc> keymaps on the fzf terminal buffer
---so that the first <Esc> goes to Normal mode (without aborting fzf) and the
---second <Esc> closes the window (killing the fzf process via stdin close).
---@internal
local function setup_double_esc()
  local buf = vim.api.nvim_get_current_buf()

  -- t-mode: intercept <Esc> before fzf sees it → exit terminal mode
  vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", {
    buffer = buf,
    silent = true,
    nowait = true,
  })

  -- n-mode: second <Esc> closes the floating window; fzf exits on stdin close
  vim.keymap.set("n", "<Esc>", function()
    local ok, err = pcall(vim.api.nvim_win_close, 0, true)
    if not ok then notify.debug("win_close error (already closed?): " .. tostring(err)) end
  end, {
    buffer = buf,
    silent = true,
    nowait = true,
  })
end

-- ── Other helpers ────────────────────────────────────────────────────────────

---@internal
---@return string|nil  "fd" | "fdfind" | nil
local function fd_exec()
  if vim.fn.executable("fd") == 1 then return "fd" end
  if vim.fn.executable("fdfind") == 1 then return "fdfind" end
  return nil
end

---Build the fd option string (everything after `fd`, before any path args) from
---the user's find flags. Reused for single-root fd_opts and multi-root cmd.
---@internal
---@param find Pickers.FindOpts|nil
---@return string
local function fd_opts_string(find)
  local f = find or {}
  local parts = { "--color=never", "--type", "f", "--exclude", ".git" }
  if f.hidden then parts[#parts + 1] = "--hidden" end
  if f.no_ignore then parts[#parts + 1] = "--no-ignore" end
  if f.follow then parts[#parts + 1] = "--follow" end
  if type(f.exclude) == "table" then
    for _, g in ipairs(f.exclude) do
      parts[#parts + 1] = "--exclude"
      parts[#parts + 1] = vim.fn.shellescape(g)
    end
  end
  return table.concat(parts, " ")
end

---Build a shell-safe fd command string for multi-root file listing.
---@internal
---@param roots string[]
---@param find  Pickers.FindOpts|nil
---@return string
local function multi_root_cmd(roots, find)
  local fd = fd_exec() or "fd"
  local parts = { fd, fd_opts_string(find) }
  for _, r in ipairs(roots) do
    parts[#parts + 1] = vim.fn.shellescape(r)
  end
  return table.concat(parts, " ")
end

---Safely call an fzf-lua function, surfacing errors via notify.
---@internal
---@param fn function
---@param opts table
local function safe_call(fn, opts)
  local ok, err = pcall(fn, opts)
  if not ok then notify.error("fzf-lua error: " .. tostring(err)) end
end

---`fzf_opts` fragment carrying a `--header` hint pointing at the cheatsheet
---key ("f1 cheatsheet"), or `{}` when the action is disabled -- fzf-lua's
---binding is fixed to f1 regardless of `keys.cheatsheet`'s lhs (see
---`pickers.entry_actions.adapters.fzf`), so unlike telescope's
---`results_title` this never needs `pickers.keys.resolve()`.
---@internal
---@return table
local function cheatsheet_header()
  local ok, cheatsheet = pcall(require, "pickers.cheatsheet")
  if not ok then return {} end
  local hint = cheatsheet.hint("fzf-lua")
  if hint == "" then return {} end
  return { ["--header"] = hint }
end

---`fzf_opts` for `--history`, or nil when history is disabled or scope isn't
---"plugin" (under "global"/"patch" the global fzf-lua default already covers
---it — see `pickers.history`).
---@internal
---@param kind "files"|"grep"|"item"|"dir"
---@return table|nil
local function history_fzf_opts(kind)
  local cfg = require("pickers.config").get()
  if not cfg.history.enabled or cfg.history.fzf_scope ~= "plugin" then return nil end
  return { ["--history"] = require("pickers.history").fzf_path(cfg, kind) }
end

---`path_shorten` opt for `fzf.files`/`fzf.live_grep`, or nil when the cosmetic
---"shorten long paths" toggle is off (the default). See `pickers.config`'s
---`Pickers.DisplayConfig`.
---@internal
---@return boolean|nil
local function path_shorten_opt()
  local cfg = require("pickers.config").get()
  if not (cfg.display and cfg.display.path_shorten) then return nil end
  return true
end

-- ── Public engine interface ───────────────────────────────────────────────────

---@return boolean
function M.available()
  local ok = pcall(require, "fzf-lua")
  return ok
end

---@internal
---The action fzf-lua would run on <CR> in a `files` picker: the user's own if they
---configured one (`actions.files.enter`, or its old name `default`), else
---fzf-lua's `file_edit_or_qf`. Wrapping this rather than fzf-lua's default keeps a
---customised <CR> customised.
---@return function|nil
local function configured_enter()
  local ok, cfg = pcall(require, "fzf-lua.config")
  local files = ok and cfg.globals and cfg.globals["actions.files"] or nil
  local act = type(files) == "table" and (files.enter or files.default) or nil
  if type(act) == "table" then act = act.fn end
  if type(act) == "function" then return act end
  local ok_fzf, fzf = pcall(require, "fzf-lua")
  return ok_fzf and fzf.actions and fzf.actions.file_edit_or_qf or nil
end

---@internal
---fzf-lua's <CR> action for `files`, followed by a report of the picked file.
---Only a single pick is reported (a multi-selection goes to the quickfix list,
---which is not "the file the user chose"). The entry is resolved by fzf-lua's own
---`entry_to_file`, which strips the icon/ANSI decoration the raw line carries.
---@param on_select (fun(path: string))|nil
---@param root string|nil  # Root a relative entry is against.
---@return (fun(selected: string[], o: table))|nil
local function default_action_with(on_select, root)
  if type(on_select) ~= "function" then return nil end
  local open = configured_enter()
  if not open then return nil end
  return function(selected, o)
    open(selected, o)
    if #selected ~= 1 then return end
    local ok, fzf_path = pcall(require, "fzf-lua.path")
    local entry = ok and fzf_path.entry_to_file(selected[1], o) or nil
    local file = entry and entry.path
    if type(file) ~= "string" or file == "" then return end
    require("pickers.engines.report").call(
      on_select,
      require("pickers.engines.report").absolute(file, o.cwd or root)
    )
  end
end

---@param opts Pickers.EngineOpts
function M.pick_files(opts)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify.error("fzf-lua unavailable")
    return
  end

  local base = {
    prompt = opts.prompt,
    query = opts.query,
    winopts = { on_create = setup_double_esc },
    fzf_opts = vim.tbl_extend("force", history_fzf_opts("files") or {}, cheatsheet_header()),
    path_shorten = path_shorten_opt(),
  }
  local on_pick = default_action_with(opts.on_select, opts.roots[1])
  if on_pick then base.actions = { ["default"] = on_pick } end

  -- Custom find command (system source: pre-built fd argv)
  if opts.find_command then
    local cmd_str = table.concat(vim.tbl_map(vim.fn.shellescape, opts.find_command), " ")
    base.cmd = cmd_str
    safe_call(fzf.files, base)
    return
  end

  -- Multi-root: construct fd command spanning all roots
  if #opts.roots > 1 then
    base.cmd = multi_root_cmd(opts.roots, opts.find)
    safe_call(fzf.files, base)
    return
  end

  -- Single root: standard fzf.files with cwd + user find flags
  base.cwd = opts.roots[1]
  base.fd_opts = fd_opts_string(opts.find)
  safe_call(fzf.files, base)
end

---@param opts Pickers.EngineOpts
function M.live_grep(opts)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify.error("fzf-lua unavailable")
    return
  end

  local extra = opts.additional_args or {}
  local rg_opts_list = { "--hidden", "--no-ignore-vcs", "-S" }
  for _, g in ipairs((opts.find or {}).exclude or {}) do
    rg_opts_list[#rg_opts_list + 1] = "-g"
    rg_opts_list[#rg_opts_list + 1] = vim.fn.shellescape("!" .. g)
  end
  -- Every other value folded into this string goes through shellescape (the
  -- glob excludes above, the roots/paths in multi_root_cmd) before this list
  -- is joined into one shell command line below -- additional_args is source
  -- config today (see sources/drives.lua), not live keystroke input, but
  -- SEC-03's point stands regardless of how harmless a value looks right now:
  -- shellescape is idempotent on a plain flag like "--type"/"lua" (it just
  -- wraps it in quotes the shell strips back off), so escaping costs nothing
  -- here and closes the gap for whatever a future source config passes.
  for _, a in ipairs(extra) do
    rg_opts_list[#rg_opts_list + 1] = vim.fn.shellescape(a)
  end

  -- `search_paths`, NOT `search_dirs`. `search_dirs` is telescope's spelling;
  -- fzf-lua has never read it (its `defaults.lua` documents `search_paths?
  -- string[]`, and `make_entry.lua` is the only consumer), and an unknown
  -- option is dropped without a word -- so every scoped grep through this
  -- engine silently ran over the CWD instead of over `roots`. Nothing errored,
  -- results appeared, and only their paths gave it away.
  --
  -- `search_paths` takes FILES where it takes directories (fzf-lua adds rg's
  -- `-r` for exactly that reason), which is what lets a caller narrow a grep
  -- to a handful of files rather than a tree. Paths are made relative to the
  -- cwd by fzf-lua itself, and an absolute path outside it survives unchanged
  -- (`path.relative_to` falls back to its input).
  safe_call(fzf.live_grep, {
    search_paths = opts.roots,
    prompt = opts.prompt,
    rg_opts = table.concat(rg_opts_list, " "),
    query = opts.query,
    winopts = { on_create = setup_double_esc },
    fzf_opts = vim.tbl_extend("force", history_fzf_opts("grep") or {}, cheatsheet_header()),
    path_shorten = path_shorten_opt(),
  })
end

---Combined grep + find-files picker (the `smart` action).
---
--- Uses fzf-lua's "live" mode (fuzzy matching disabled, contents reloaded per
--- keystroke) with a Lua contents function: on every query it hands fzf-lua a
--- writer that starts the shared core (pickers.smart.query) as a job through
--- one `pickers.smart.live` runner (debounced, the newest query wins, the
--- editor goes on while rg/fd run) and, once the job is done, writes the
--- already-merged, already-ranked list as grep-style (`path:line:col:text`) /
--- plain-path lines and closes the pipe. `--no-sort`
--- keeps fzf from reordering, so OUR relevance ranking is preserved. The native
--- `file_edit_or_qf` action + builtin previewer parse the grep lines and jump to
--- the matched line (file rows open at the top).
---
--- NOTE: the writer needs fzf-lua's `reload` path with the Lua function run in
--- this Neovim (`multiprocess = false`). Its `transform` path (fzf >= 0.45 with
--- `rg_glob = true`) only takes a finished list, so `rg_glob` stays off here.
---@param opts Pickers.EngineOpts
function M.smart(opts)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify.error("fzf-lua unavailable")
    return
  end
  local actions = require("fzf-lua.actions")

  local root = opts.roots and opts.roots[1] or vim.uv.cwd()
  local live = require("pickers.smart.live").new(opts.core, {
    roots = opts.roots,
    find = opts.find,
    additional_args = opts.additional_args,
  })

  ---The rows of `items` as fzf lines.
  ---@internal
  ---@param items Pickers.Smart.Item[]
  ---@return string[]
  local function lines_of(items)
    local lines = {}
    for i, it in ipairs(items) do
      -- Prefer a cwd-relative path (keeps "file:line:col" parseable — an
      -- absolute Windows path's drive colon would confuse it); fall back to the
      -- absolute path for hits from a secondary root.
      local p = (it.root == root) and it.path or it.abspath
      if it.kind == "grep" then
        lines[i] = string.format("%s:%d:%d:%s", p, it.lnum, it.col or 1, it.text or "")
      else
        lines[i] = p
      end
    end
    return lines
  end

  ---fzf-lua calls this per query (`{ query }`, or the query itself) and then the
  ---writer it returns with its line callback; `write(nil)` closes the pipe. A
  ---search superseded by a newer query closes its pipe without rows.
  ---@internal
  ---@param query string|string[]|nil
  ---@return fun(write: fun(line: string|nil))
  local function contents(query)
    if type(query) == "table" then query = query[1] end
    return function(write)
      live:run(type(query) == "string" and query or "", function(items)
        for _, line in ipairs(items and lines_of(items) or {}) do
          write(line)
        end
        write(nil)
      end)
    end
  end

  fzf.fzf_live(contents, {
    prompt = opts.prompt or "Smart> ",
    query = opts.query,
    cwd = root,
    is_live = true,
    multiprocess = false,
    previewer = "builtin",
    file_icons = false,
    git_icons = false,
    color_icons = false,
    fzf_opts = vim.tbl_extend(
      "force",
      { ["--no-sort"] = true },
      history_fzf_opts("grep") or {},
      cheatsheet_header()
    ),
    winopts = { on_create = setup_double_esc },
    actions = {
      ["default"] = actions.file_edit_or_qf,
    },
  })
end

---The extras of `pickers.items` on one `fzf_exec` call of `pick_item`: what was
---typed before (`query`), several marked rows (`multi`) and keys of the call
---(`keys`). Without any of them `exec_opts` comes back untouched.
---
---fzf prints the accepted lines, marked ones in the order they were marked. A
---line is found again by its position in `lines` (which run parallel to
---`opts.items`), so the items reach a callback in the order of the list, as on
---the other engines. Whether one printed line was marked or only under the
---cursor fzf does not say; it is the row the key acts on either way.
---@internal
---@param opts Pickers.PickItemOpts
---@param lines string[]
---@param exec_opts table
---@return table exec_opts
local function with_extras(opts, lines, exec_opts)
  local keys = opts.keys or {}
  if opts.query and opts.query ~= "" then exec_opts.query = opts.query end
  if not opts.multi and #keys == 0 then return exec_opts end

  local pos = {}
  for i, line in ipairs(lines) do
    pos[line] = pos[line] or i
  end
  ---@param selected string[]|nil
  ---@param o table|nil  fzf-lua's options of the run; `last_query` is what was typed
  ---@return Pickers.ItemEnv
  local function env_of(selected, o)
    local idxs = {}
    for _, line in ipairs(selected or {}) do
      if pos[line] then idxs[#idxs + 1] = pos[line] end
    end
    table.sort(idxs)
    local items = {}
    for i, idx in ipairs(idxs) do
      items[i] = opts.items[idx]
    end
    return { items = items, query = type(o) == "table" and o.last_query or "" }
  end

  exec_opts.actions = exec_opts.actions or {}
  if opts.multi then
    exec_opts.fzf_opts["--no-multi"] = nil
    exec_opts.fzf_opts["--multi"] = true
    exec_opts.actions["default"] = function(selected, o)
      local env = env_of(selected, o)
      if env.items[1] ~= nil then opts.on_select(env.items[1], env) end
    end
  end
  local pm = require("pickers.preview_modes")
  for _, key in ipairs(keys) do
    -- a plain action: fzf-lua closes fzf, then calls it
    exec_opts.actions[pm.fzf_key(key.key)] = function(selected, o)
      key.run(env_of(selected, o))
    end
  end
  return exec_opts
end

---Pick one item from a list (used by repos / collection sources, and by
---consumers like filetree.nvim's template picker). Items may be plain
---strings (unchanged — exact original code path, zero risk to existing
---callers) or `Pickers.Item` tables `{ text, file? }`.
---
---fzf is a separate process working on plain text lines, so there is no way
---to attach a hidden Lua object to a line the way telescope/snacks can:
---when at least one item carries `file`, every line instead gets a hidden
---second field (`<text>\t<file>`), `--delimiter`/`--with-nth=1` show/match
---only the first (the file path never appears or gets fuzzy-matched against),
---and `opts.preview` — a Lua function, not a shell command — reads that
---second field's file via `vim.fn.readfile` and returns its content. This
---avoids depending on `cat`/`bat` being on PATH (relevant on Windows).
---Selection still returns fzf's full untransformed line, so `by_line` maps it
---straight back to the original item for `on_select`.
---@param opts Pickers.PickItemOpts
function M.pick_item(opts)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify.error("fzf-lua unavailable")
    return
  end

  local has_preview = false
  for _, it in ipairs(opts.items) do
    if type(it) == "table" and it.file then
      has_preview = true
      break
    end
  end

  -- Items with `previews`: the preview follows the current mode and a key
  -- switches it (see `pickers.preview_modes`). fzf only sees text lines, so the
  -- hidden last field is the item's index, not a file; it is read from the end
  -- of the line, so an item text with a TAB in it still finds its index. The
  -- mode is kept in Lua only: the preview text itself starts near the spec's
  -- `line` (`pm.fzf_text`), and fzf's own scroll offset is left alone, so
  -- fzf-lua's resize/flex/fullscreen handling cannot pull it out of step.
  local pm = require("pickers.preview_modes")
  local modes = pm.new(opts)
  if modes then
    local lines, by_line = {}, {}
    for i, it in ipairs(opts.items) do
      local text = (type(it) == "table") and it.text or it
      lines[i] = text .. "\t" .. i
      by_line[lines[i]] = it
    end
    local mode_actions = {
      ["default"] = function(selected)
        if selected and selected[1] then opts.on_select(by_line[selected[1]] or selected[1]) end
      end,
    }
    -- a preview callback (`opts.preview`) has one mode and no key
    if modes.key then
      mode_actions[pm.fzf_key(modes.key)] = {
        fn = function()
          modes:toggle()
        end,
        exec_silent = true,
        postfix = "refresh-preview",
      }
    end
    fzf.fzf_exec(
      lines,
      with_extras(opts, lines, {
        prompt = opts.prompt,
        -- the mode line on top of the text stays put when the preview is scrolled
        preview_offset = "~" .. pm.FZF_HEADER_LINES,
        fzf_opts = vim.tbl_extend("force", {
          ["--no-multi"] = true,
          ["--delimiter"] = "\\t",
          ["--with-nth"] = "1",
        }, history_fzf_opts("item") or {}, cheatsheet_header()),
        preview = function(selected, preview_lines)
          local line = (type(selected) == "table") and selected[1] or selected
          local idx = line and tonumber(line:match("\t(%d+)$"))
          -- fzf has no preview title: the first line names the modes, the current one in brackets
          return pm.fzf_text(
            modes:label(),
            idx and modes:spec(opts.items[idx]),
            tonumber(preview_lines)
          )
        end,
        winopts = {
          on_create = function()
            -- a resumed picker restarts fzf with this same state: start in the first mode
            modes:reset()
            setup_double_esc()
          end,
        },
        actions = mode_actions,
      })
    )
    return
  end

  if not has_preview then
    -- `opts.items` may still be `Pickers.Item` tables even with no `file` set
    -- anywhere (`file` is optional -- see the type doc) -- fzf-lua's contents
    -- table wants plain strings, and `on_select` must get back the EXACT
    -- entry that was in `items` (PRIN-25: narrow the input before the
    -- foreign-API call, same as the has_preview branch below already does).
    local lines, by_line = {}, {}
    for i, it in ipairs(opts.items) do
      local text = (type(it) == "table") and it.text or it
      lines[i] = text
      by_line[text] = it
    end

    fzf.fzf_exec(
      lines,
      with_extras(opts, lines, {
        prompt = opts.prompt,
        fzf_opts = vim.tbl_extend(
          "force",
          { ["--no-multi"] = true },
          history_fzf_opts("item") or {},
          cheatsheet_header()
        ),
        winopts = { on_create = setup_double_esc },
        actions = {
          ["default"] = function(selected)
            if selected and selected[1] then opts.on_select(by_line[selected[1]] or selected[1]) end
          end,
        },
      })
    )
    return
  end

  local lines, by_line = {}, {}
  for i, it in ipairs(opts.items) do
    local text = (type(it) == "table") and it.text or it
    local file = (type(it) == "table") and it.file or nil
    local line = file and (text .. "\t" .. file) or text
    lines[i] = line
    by_line[line] = it
  end

  fzf.fzf_exec(
    lines,
    with_extras(opts, lines, {
      prompt = opts.prompt,
      fzf_opts = vim.tbl_extend("force", {
        ["--no-multi"] = true,
        ["--delimiter"] = "\\t",
        ["--with-nth"] = "1",
      }, history_fzf_opts("item") or {}, cheatsheet_header()),
      preview = function(selected)
        local line = (type(selected) == "table") and selected[1] or selected
        local file = line and line:match("\t(.+)$")
        if not file then return "" end
        local ok_read, read_lines = pcall(vim.fn.readfile, file)
        if not ok_read then return "could not read " .. file end
        return table.concat(read_lines, "\n")
      end,
      winopts = { on_create = setup_double_esc },
      actions = {
        ["default"] = function(selected)
          if selected and selected[1] then opts.on_select(by_line[selected[1]] or selected[1]) end
        end,
      },
    })
  )
end

---Open a directory picker (used by folder source).
---@param opts { prompt: string, cwd: string|nil, on_select: fun(path: string) }
function M.pick_dir(opts)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify.error("fzf-lua unavailable")
    return
  end

  local cwd = opts.cwd or vim.fn.getcwd()

  fzf.files({
    prompt = opts.prompt or "Folder> ",
    cwd = cwd,
    fd_opts = "--type d --hidden --follow --exclude .git",
    winopts = { on_create = setup_double_esc },
    fzf_opts = vim.tbl_extend("force", history_fzf_opts("dir") or {}, cheatsheet_header()),
    actions = {
      ["default"] = function(selected)
        if not selected or not selected[1] then return end
        local path = vim.fs.normalize(cwd .. "/" .. selected[1])
        opts.on_select(path)
      end,
    },
  })
end

-- fzf-lua asks for `fzf --version` synchronously when a picker opens. When fzf-lua is loaded by this very
-- picker, the asynchronous lookup (pickers.engines.fzf_version) has only just started, so the open is
-- deferred until it is done instead of blocking the editor on fzf-lua's own call.
for _, name in ipairs({ "pick_files", "live_grep", "smart", "pick_item", "pick_dir" }) do
  local open = M[name]
  M[name] = function(opts, ...)
    local args, n = { ... }, select("#", ...)
    local ok, fv = pcall(require, "pickers.engines.fzf_version")
    if ok and pcall(require, "fzf-lua") and fv.install() and not fv.ready() then
      fv.when_ready(function()
        open(opts, unpack(args, 1, n))
      end)
      return
    end
    return open(opts, ...)
  end
end

return M
