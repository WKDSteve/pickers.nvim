-- Test code: a nil here (a require, a captured option) must crash and name it.
---@diagnostic disable: need-check-nil
-- pickers.nvim -- `pickers.items` (the list of a caller's own rows) and the
-- extras of `pick_item` it is built on, per engine (no framework, no network).
--
-- Run:
--   nvim -l TESTS/items_spec.lua
--
-- The neutral part runs on a fake engine. The three adapters run against
-- stand-ins of their library (one per engine, as in pickers_spec.lua), so none
-- of telescope, fzf-lua and snacks has to be installed.

-- ── Self-bootstrapping runtimepath ──────────────────────────────────────────
local this = debug.getinfo(1, "S").source:sub(2) -- strip leading '@'
local tests_dir = vim.fn.fnamemodify(this, ":p:h")
local root = vim.fn.fnamemodify(tests_dir, ":h") -- TESTS -> repo root
vim.opt.runtimepath:append(root)

local lib = vim.fn.fnamemodify(root, ":h") .. "/lib.nvim"
if vim.env.LIB_NVIM_PATH and vim.fn.isdirectory(vim.env.LIB_NVIM_PATH) == 1 then
  lib = vim.env.LIB_NVIM_PATH
elseif vim.env.REPOS_DIR and vim.fn.isdirectory(vim.env.REPOS_DIR .. "/lib.nvim") == 1 then
  lib = vim.env.REPOS_DIR .. "/lib.nvim"
end
if vim.fn.isdirectory(lib) == 1 then vim.opt.runtimepath:append(lib) end

-- ── Tiny assertion harness ──────────────────────────────────────────────────
local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. (detail and ("  → " .. tostring(detail)) or ""))
  end
end

-- what the plugin says to the user, collected instead of shown
local said = {}
local real_notify = vim.notify
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg)
  said[#said + 1] = tostring(msg)
end

local items = require("pickers.items")
local pm = require("pickers.preview_modes")

-- ── keys spelled for fzf ────────────────────────────────────────────────────
check(
  "fzf_key: a chord on the letter s is not the shift modifier",
  pm.fzf_key("<M-s>") == "alt-s" and pm.fzf_key("<C-s>") == "ctrl-s",
  pm.fzf_key("<M-s>")
)
check(
  "fzf_key: several modifiers come in fzf's order",
  pm.fzf_key("<M-C-x>") == "ctrl-alt-x" and pm.fzf_key("<S-M-Up>") == "alt-shift-up",
  pm.fzf_key("<M-C-x>") .. " " .. pm.fzf_key("<S-M-Up>")
)
check(
  "fzf_key: function keys, shift on a special key, the old names",
  pm.fzf_key("<F5>") == "f5"
    and pm.fzf_key("<S-F5>") == "shift-f5"
    and pm.fzf_key("<S-Tab>") == "shift-tab"
    and pm.fzf_key("<M-CR>") == "alt-enter"
    and pm.fzf_key("<BS>") == "bspace"
)

-- ── columns ─────────────────────────────────────────────────────────────────
do
  local lines = items.columns({
    { "1", "open", "S", "Fix the thing" },
    { "10", "blocked", "XL", "Ä" },
    { "2", "done" },
  }, { right = { [1] = true } })
  check(
    "columns: aligned on the widest cell, the last column unpadded, no trailing blanks",
    lines[1] == " 1  open     S   Fix the thing"
      and lines[2] == "10  blocked  XL  Ä"
      and lines[3] == " 2  done",
    vim.inspect(lines)
  )
  local wide = items.columns({ { "日本", "x" }, { "a", "y" } })
  check(
    "columns: the width is what the screen shows, not the byte count",
    wide[1] == "日本  x" and wide[2] == "a     y",
    vim.inspect(wide)
  )
  check("columns: no rows, no lines", #items.columns({}) == 0)
end

-- ── check ───────────────────────────────────────────────────────────────────
do
  local noop = function() end
  check("check: a plain call is fine", #items.check({ items = {} }) == 0)
  check("check: items must be a list or a function", #items.check({ items = "x" }) == 1)
  check(
    "check: a plain letter is not a key (it is typed into the prompt)",
    items.check({ items = {}, actions = { a = { key = "s", fn = noop } } })[1]:find("chord") ~= nil
  )
  check(
    "check: the list's own keys are refused",
    items.check({ items = {}, actions = { a = { key = "<Tab>", fn = noop } } })[1]:find("own key")
        ~= nil
      and #items.check({ items = {}, actions = { a = { key = "<cr>", fn = noop } } }) == 1
  )
  local twice = items.check({
    items = {},
    actions = { one = { key = "<M-s>", fn = noop }, two = { key = "<A-S>", fn = noop } },
  })
  check(
    "check: one key for two actions is named, whatever its spelling",
    #twice == 1 and twice[1]:find("actions.two", 1, true) and twice[1]:find("actions.one", 1, true),
    vim.inspect(twice)
  )
  check(
    "check: an action without a function",
    #items.check({ items = {}, actions = { a = { key = "<M-s>" } } }) == 1
  )
  said = {}
  check(
    "open: an invalid call opens nothing and says why",
    items.open({ items = {}, actions = { a = { key = "s", fn = noop } } }) == false
      and #said == 1
      and said[1]:find("chord") ~= nil,
    vim.inspect(said)
  )
  check(
    "describe: key and description per action, in the order of the names",
    vim.deep_equal(
      items.describe({
        b = { key = "<M-p>", desc = "prio", fn = noop },
        a = { key = "<C-M-s>", fn = noop },
      }),
      { "<C-M-s>  a", "<M-p>    prio" }
    )
  )
end

-- ── open on a fake engine ───────────────────────────────────────────────────
do
  local calls = {}
  local fake = {
    pick_item = function(o)
      calls[#calls + 1] = o
    end,
  }
  local version = 1
  local rows_a = { { text = "a" }, { text = "b" }, { text = "c" } }
  local rows_b = { { text = "a2" }, { text = "b2" } }
  local acted, selected = {}, {}
  local opts = {
    engine_mod = fake,
    items = function()
      return version == 1 and rows_a or rows_b
    end,
    title = function(rows)
      return ("Rows (%d)"):format(#rows)
    end,
    preview = function(item)
      return { lines = { item.text } }
    end,
    marks = true,
    actions = {
      zap = {
        key = "<M-z>",
        desc = "zap",
        fn = function(sel, ctx)
          acted[#acted + 1] = { sel = sel, ctx = ctx }
        end,
      },
      boom = {
        key = "<M-b>",
        fn = function()
          error("kaputt")
        end,
      },
    },
    on_select = function(item, sel)
      selected[#selected + 1] = { item = item, sel = sel }
    end,
  }
  check("open: opened", items.open(opts) == true and #calls == 1)
  local call = calls[1]
  check(
    "open: rows and title are read, the title gets the rows",
    call.items == rows_a and call.prompt == "Rows (3)"
  )
  check(
    "open: preview, marks and keys reach the engine",
    call.preview == opts.preview
      and call.multi == true
      and #call.keys == 2
      and call.keys[1].key == "<M-b>"
      and call.keys[2].key == "<M-z>"
      and call.keys[2].desc == "zap"
      and call.keys[1].desc == "boom",
    vim.inspect(call.keys)
  )

  call.keys[2].run({ items = { rows_a[1], rows_a[3] }, query = "al" })
  check(
    "action: gets the marked rows as they are and what was typed",
    #acted == 1
      and acted[1].sel[1] == rows_a[1]
      and acted[1].sel[2] == rows_a[3]
      and acted[1].ctx.query == "al"
  )

  -- the restart: rows and title again, the query kept
  version = 2
  acted[1].ctx.reopen()
  check(
    "reopen: the rows and the title are read anew, the query is kept",
    #calls == 2
      and calls[2].items == rows_b
      and calls[2].prompt == "Rows (2)"
      and calls[2].query == "al"
  )
  acted[1].ctx.reopen({ query = "", title = "Other" })
  check(
    "reopen: changes replace fields of the call",
    #calls == 3 and calls[3].query == "" and calls[3].prompt == "Other" and calls[3].multi == true
  )

  said = {}
  call.keys[1].run({ items = {}, query = "" })
  check(
    "action: one that throws is reported, by name",
    #said == 1 and said[1]:find("boom") ~= nil and said[1]:find("kaputt") ~= nil,
    vim.inspect(said)
  )

  call.on_select(rows_a[2], { items = { rows_a[2], rows_a[3] }, query = "" })
  call.on_select(rows_a[1], nil) -- an engine that reports the one row only
  check(
    "on_select: the first row and all of them; one row from an engine without the extras",
    selected[1].item == rows_a[2]
      and #selected[1].sel == 2
      and selected[2].item == rows_a[1]
      and #selected[2].sel == 1
  )

  -- without marks an action never gets more than one row
  calls, acted = {}, {}
  items.open(vim.tbl_extend("force", opts, { marks = false, items = rows_a }))
  calls[1].keys[2].run({ items = { rows_a[2], rows_a[3] }, query = "" })
  check(
    "marks off: the engine is not asked to mark, an action gets one row",
    calls[1].multi == false and #acted[1].sel == 1 and acted[1].sel[1] == rows_a[2]
  )
  calls[1].keys[2].run({ items = {}, query = "x" })
  check("action: an empty list is an empty selection", #acted[2].sel == 0)

  said = {}
  local opened = items.open({
    engine_mod = fake,
    items = function()
      error("no rows today")
    end,
  })
  check(
    "open: rows that cannot be read open nothing and say so",
    opened == false and #said == 1 and said[1]:find("no rows today") ~= nil
  )
  calls = {}
  items.open({ engine_mod = fake, items = { "x" } })
  check(
    "open: a bare list of strings, no title",
    calls[1].prompt == "Items" and calls[1].items[1] == "x" and #calls[1].keys == 0
  )
end

-- ── a preview callback is one mode without a key ────────────────────────────
do
  local state = pm.new({
    items = { { text = "a" } },
    preview = function(item)
      if item.text == "bad" then error("oops") end
      return { lines = { "p " .. item.text }, ft = "lua" }
    end,
  })
  check(
    "preview callback: one mode, no key, a plain title",
    state ~= nil and #state.modes == 1 and state.key == nil and state:label() == "Preview"
  )
  check(
    "preview callback: the spec is asked per item",
    state:spec({ text = "a" }).lines[1] == "p a"
  )
  check(
    "preview callback: one that throws shows the error instead of closing the list",
    state:spec({ text = "bad" }).lines[1]:find("oops") ~= nil
  )
  check("preview callback: without one nothing changes", pm.new({ items = { "a" } }) == nil)
end

local rows = { { text = "one" }, { text = "two" }, { text = "three" } }

---The keys of a call that record what they were run with.
---@param into table
---@return Pickers.ItemKey[]
local function recording_keys(into)
  return {
    {
      key = "<M-s>",
      desc = "status",
      run = function(env)
        into[#into + 1] = env
      end,
    },
  }
end

-- ── telescope ───────────────────────────────────────────────────────────────
do
  local names = {
    "telescope.builtin",
    "telescope.pickers",
    "telescope.finders",
    "telescope.config",
    "telescope.actions",
    "telescope.actions.state",
    "telescope.previewers",
    "telescope.previewers.utils",
  }
  local prev = {}
  for _, k in ipairs(names) do
    prev[k] = package.loaded[k]
  end
  local captured, mapped, default_action, order = nil, {}, nil, {}
  local multi, current, line = {}, nil, ""
  package.loaded["telescope.builtin"] = {}
  package.loaded["telescope.pickers"] = {
    new = function(_, o)
      captured = o
      return {
        find = function()
          o.attach_mappings(7, function(modes, key, fn, mo)
            mapped[key] = { modes = modes, fn = fn, desc = mo and mo.desc }
          end)
        end,
      }
    end,
  }
  package.loaded["telescope.finders"] = {
    new_table = function(o)
      return o
    end,
  }
  package.loaded["telescope.config"] = {
    values = {
      generic_sorter = function()
        return "sorter"
      end,
      file_previewer = function()
        return "file_previewer"
      end,
    },
  }
  package.loaded["telescope.actions"] = {
    select_default = {
      replace = function(_, fn)
        default_action = fn
      end,
    },
    close = function()
      order[#order + 1] = "close"
    end,
  }
  package.loaded["telescope.actions.state"] = {
    get_current_picker = function()
      return {
        get_multi_selection = function()
          return multi
        end,
      }
    end,
    get_selected_entry = function()
      return current
    end,
    get_current_line = function()
      return line
    end,
  }
  package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function(o)
      return o
    end,
  }
  package.loaded["telescope.previewers.utils"] = { highlighter = function() end }
  package.loaded["pickers.engines.telescope"] = nil
  local tel = require("pickers.engines.telescope")

  local ran, picked = {}, {}
  local keys = recording_keys(ran)
  local run = keys[1].run
  keys[1].run = function(env)
    order[#order + 1] = "run"
    run(env)
  end
  tel.pick_item({
    items = rows,
    prompt = "T",
    query = "tw",
    multi = true,
    keys = keys,
    on_select = function(item, env)
      picked[#picked + 1] = { item = item, env = env }
    end,
  })
  check("telescope: the query is the text the prompt starts with", captured.default_text == "tw")
  check(
    "telescope: the key is mapped in insert and normal mode, with its description",
    mapped["<M-s>"] ~= nil and #mapped["<M-s>"].modes == 2 and mapped["<M-s>"].desc == "status"
  )
  -- marked in the order three, one: reported in the order of the list
  multi = { { value = rows[3], index = 3 }, { value = rows[1], index = 1 } }
  current, line = { value = rows[2], index = 2 }, "tw"
  mapped["<M-s>"].fn(7)
  check(
    "telescope: a key gets the marked rows in list order and the query, after the close",
    #ran == 1
      and ran[1].items[1] == rows[1]
      and ran[1].items[2] == rows[3]
      and ran[1].query == "tw"
      and order[1] == "close"
      and order[2] == "run",
    vim.inspect(order)
  )
  multi = {}
  mapped["<M-s>"].fn(7)
  check(
    "telescope: without marks the row under the cursor",
    #ran[2].items == 1 and ran[2].items[1] == rows[2]
  )
  current = nil
  mapped["<M-s>"].fn(7)
  check("telescope: an empty list is an empty selection", #ran[3].items == 0)

  multi, current = { { value = rows[2], index = 2 }, { value = rows[3], index = 3 } }, nil
  default_action(7)
  check(
    "telescope: <CR> with multi reports every marked row",
    #picked == 1 and picked[1].item == rows[2] and #picked[1].env.items == 2
  )

  -- a call without the extras is the call it always was
  local plain
  current = { value = rows[1] }
  tel.pick_item({
    items = rows,
    prompt = "T",
    on_select = function(item, env)
      plain = { item = item, env = env }
    end,
  })
  default_action(7)
  check(
    "telescope: without the extras <CR> reports the one row, no prompt text, no key",
    plain.item == rows[1] and plain.env == nil and captured.default_text == nil
  )

  -- telescope marks in every list: a call without `multi` acts on the cursor row
  ran, mapped = {}, {}
  tel.pick_item({
    items = rows,
    prompt = "T",
    keys = recording_keys(ran),
    on_select = function() end,
  })
  multi, current = { { value = rows[3], index = 3 } }, { value = rows[1], index = 1 }
  mapped["<M-s>"].fn(7)
  check(
    "telescope: without multi a key acts on the row under the cursor, whatever is marked",
    #ran[1].items == 1 and ran[1].items[1] == rows[1]
  )

  mapped = {}
  tel.pick_item({
    items = rows,
    prompt = "T",
    on_select = function() end,
    preview = function(item)
      return { lines = { item.text } }
    end,
  })
  check(
    "telescope: a preview callback is a previewer of its own, and no mode key is mapped",
    type(captured.previewer) == "table" and next(mapped) == nil
  )

  package.loaded["pickers.engines.telescope"] = nil
  for _, k in ipairs(names) do
    package.loaded[k] = prev[k]
  end
end

-- ── snacks ──────────────────────────────────────────────────────────────────
do
  local prev_snacks = package.loaded["snacks.picker"]
  local captured
  package.loaded["snacks.picker"] = {
    select = function(list, o, on_choice)
      captured = { items = list, opts = o, on_choice = on_choice }
    end,
  }
  package.loaded["pickers.engines.snacks"] = nil
  local sn = require("pickers.engines.snacks")

  -- `vim.schedule` is run at once here, so that the order is visible
  -- luacheck: push ignore 122
  local real_schedule = vim.schedule
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.schedule = function(fn)
    fn()
  end

  local ran, picked, order = {}, {}, {}
  local keys = recording_keys(ran)
  local run = keys[1].run
  keys[1].run = function(env)
    order[#order + 1] = "run"
    run(env)
  end
  sn.pick_item({
    items = rows,
    prompt = "S",
    query = "th",
    multi = true,
    keys = keys,
    on_select = function(item, env)
      picked[#picked + 1] = { item = item, env = env }
    end,
  })
  local so = captured.opts.snacks
  check("snacks: the query is the pattern the list starts with", so.pattern == "th")
  local bound = so.win.input.keys["<a-s>"]
  check(
    "snacks: the key is bound on the input and the list, in both modes",
    bound ~= nil
      and so.win.list.keys["<a-s>"] ~= nil
      and #bound.mode == 2
      and bound.desc == "status"
      and type(so.actions[bound[1]]) == "function"
  )
  -- `picker:selected()` hands out copies of the wrapped entries: only `idx` leads back
  local picker = {
    selected = function(_, o)
      order[#order + 1] = o and o.fallback and "selected+fallback" or "selected"
      return { { idx = 3, item = { text = "a copy" } }, { idx = 1, item = { text = "a copy" } } }
    end,
    filter = function()
      return { pattern = "th" }
    end,
    close = function()
      order[#order + 1] = "close"
    end,
  }
  so.actions[bound[1]](picker)
  check(
    "snacks: a key gets the very rows that were passed in, in list order, and the query",
    #ran == 1 and ran[1].items[1] == rows[1] and ran[1].items[2] == rows[3] and ran[1].query == "th"
  )
  check(
    "snacks: the selection is read (with the cursor row as the fallback) before the close",
    vim.deep_equal(order, { "selected+fallback", "close", "run" }),
    vim.inspect(order)
  )
  so.actions.confirm(picker)
  check(
    "snacks: <CR> with multi reports every marked row",
    #picked == 1 and picked[1].item == rows[1] and #picked[1].env.items == 2
  )
  captured.on_choice(nil) -- what `select` sends after a close without a choice of its own
  check("snacks: the close that follows is not a second pick", #picked == 1)

  -- snacks marks in every list: a call without `multi` acts on the cursor row
  ran = {}
  sn.pick_item({
    items = rows,
    prompt = "S",
    keys = recording_keys(ran),
    on_select = function() end,
  })
  picker.current = function()
    return { idx = 2, item = { text = "a copy" } }
  end
  local only = captured.opts.snacks
  only.actions[only.win.input.keys["<a-s>"][1]](picker)
  check(
    "snacks: without multi a key acts on the row under the cursor, whatever is marked",
    #ran[1].items == 1 and ran[1].items[1] == rows[2] and only.actions.confirm == nil
  )

  sn.pick_item({ items = rows, prompt = "S", on_select = function() end })
  check(
    "snacks: without the extras nothing is added to the call",
    captured.opts.snacks == nil
      or (
        captured.opts.snacks.pattern == nil
        and captured.opts.snacks.actions == nil
        and captured.opts.snacks.win == nil
      ),
    vim.inspect(captured.opts.snacks)
  )

  sn.pick_item({
    items = rows,
    prompt = "S",
    on_select = function() end,
    keys = recording_keys({}),
    preview = function(item)
      return { lines = { item.text } }
    end,
  })
  so = captured.opts.snacks
  check(
    "snacks: a preview callback and a key live side by side, without a mode key",
    type(so.preview) == "function"
      and so.win.input.keys["<a-s>"] ~= nil
      and so.win.input.keys["<a-c>"] == nil
      and so.actions.pickers_toggle_preview_mode ~= nil
      and so.actions.confirm == nil
  )

  vim.schedule = real_schedule
  -- luacheck: pop
  package.loaded["snacks.picker"] = prev_snacks
  package.loaded["pickers.engines.snacks"] = nil
end

-- ── fzf-lua ─────────────────────────────────────────────────────────────────
do
  local prev_fzf = package.loaded["fzf-lua"]
  local captured
  package.loaded["fzf-lua"] = {
    fzf_exec = function(lines, o)
      captured = { lines = lines, o = o }
    end,
  }
  package.loaded["pickers.engines.fzf"] = nil
  local fzf_engine = require("pickers.engines.fzf")

  local ran, picked = {}, {}
  fzf_engine.pick_item({
    items = rows,
    prompt = "F",
    query = "t",
    multi = true,
    keys = recording_keys(ran),
    on_select = function(item, env)
      picked[#picked + 1] = { item = item, env = env }
    end,
  })
  check(
    "fzf: rows can be marked and the query is passed on",
    captured.o.fzf_opts["--multi"] == true
      and captured.o.fzf_opts["--no-multi"] == nil
      and captured.o.query == "t"
  )
  check(
    "fzf: the key is an action under fzf's name",
    type(captured.o.actions["alt-s"]) == "function"
  )
  -- fzf prints marked lines in the order they were marked
  captured.o.actions["alt-s"]({ "three", "one" }, { last_query = "t" })
  check(
    "fzf: a key gets the very rows that were passed in, in list order, and the query",
    #ran == 1 and ran[1].items[1] == rows[1] and ran[1].items[2] == rows[3] and ran[1].query == "t"
  )
  captured.o.actions["alt-s"]({}, {})
  check("fzf: an empty list is an empty selection", #ran[2].items == 0 and ran[2].query == "")
  captured.o.actions["default"]({ "two", "three" }, { last_query = "" })
  check(
    "fzf: <CR> with multi reports every marked row",
    #picked == 1 and picked[1].item == rows[2] and #picked[1].env.items == 2
  )

  -- rows with a file carry a hidden field; the line as fzf prints it still finds its row
  local with_file = { { text = "A", file = "/tmp/a" }, { text = "B", file = "/tmp/b" } }
  ran = {}
  fzf_engine.pick_item({
    items = with_file,
    prompt = "F",
    keys = recording_keys(ran),
    on_select = function() end,
  })
  captured.o.actions["alt-s"]({ captured.lines[2] }, { last_query = "b" })
  check(
    "fzf: rows with a hidden file field are found again",
    captured.lines[2] == "B\t/tmp/b" and ran[1].items[1] == with_file[2]
  )
  check(
    "fzf: a key alone does not turn marking on",
    captured.o.fzf_opts["--no-multi"] == true and captured.o.fzf_opts["--multi"] == nil
  )

  -- a preview callback: the index field, the preview text, no mode key
  ran = {}
  fzf_engine.pick_item({
    items = rows,
    prompt = "F",
    keys = recording_keys(ran),
    on_select = function() end,
    preview = function(item)
      return { lines = { "p " .. item.text } }
    end,
  })
  local action_names = vim.tbl_keys(captured.o.actions)
  table.sort(action_names)
  check(
    "fzf: a preview callback shows its text under the title, and no mode key is bound",
    captured.o.preview({ "two\t2" }) == "Preview\np two"
      and vim.deep_equal(action_names, { "alt-s", "default" }),
    vim.inspect(action_names)
  )
  captured.o.actions["alt-s"]({ "three\t3" }, { last_query = "" })
  check("fzf: and its rows are found again by the key", ran[1].items[1] == rows[3])

  -- a call without the extras is the call it always was
  fzf_engine.pick_item({ items = rows, prompt = "F", on_select = function() end })
  check(
    "fzf: without the extras there is one action, no marking and no query",
    captured.o.fzf_opts["--no-multi"] == true
      and captured.o.query == nil
      and vim.deep_equal(vim.tbl_keys(captured.o.actions), { "default" })
  )

  package.loaded["pickers.engines.fzf"] = nil
  package.loaded["fzf-lua"] = prev_fzf
end

vim.notify = real_notify

-- ── Summary ─────────────────────────────────────────────────────────────────
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
