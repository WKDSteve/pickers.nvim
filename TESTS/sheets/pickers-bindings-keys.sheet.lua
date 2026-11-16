-- The keys of pickers.nvim as the nvim config sets them (BINDINGS-RUNTIME-CHECKLIST.md, section "pickers" and
-- <leader>fa): each key is typed, and the sheet reads what reached the picker -- which picker (files, grep, smart,
-- the files picker with a grep= filter), on which root, under which prompt. The interactive steps in between (a
-- folder, a subdir of a collection, a directory and an action) are answered as a person would.
-- The engine is a recorder (TESTS/sheets/_bindings.lua): that the real engines draw what they are handed is what
-- the pickers.items sheets check. <leader>. (the explorer) is in pickers-bindings-snacks.sheet.lua.

local steps = {
  {
    lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); dofile(vim.fn.getcwd() .. "/TESTS/sheets/_bindings.lua")]],
    note = "pickers.setup as in the nvim config, the engine a recorder",
  },
}

local function add(step)
  steps[#steps + 1] = step
end

---Type `lhs` (with the leader as a space) and check the picker that came.
local function key(lhs, kind, want, note)
  add({ keys = " " .. lhs, note = "<leader>" .. lhs .. ": " .. note })
  add({
    expect = '_G.took("' .. kind .. '", ' .. want .. ")",
    note = "<leader>" .. lhs .. " opened it",
  })
end

-- The defaults of pickers.nvim.
key("li", "live_grep", '{ root = _G.cwd(), prompt = "CWD> " }', "live grep in the cwd")
key("fc", "pick_files", '{ root = _G.cfgdir(), prompt = "Config> " }', "files in the nvim config")
key("gc", "live_grep", '{ root = _G.cfgdir(), prompt = "Config> " }', "grep in the nvim config")

add({ keys = " fb", note = "<leader>fb: find files in a folder picked first" })
add({ expect = '_G.took("pick_dir", { prompt = "Folder> " }) and _G.answer(_G.fx("coll/notes"))' })
add({
  expect = '_G.took("pick_files", { root = "/coll/notes", prompt = "notes> " })',
  note = "the files of the picked folder",
})

add({ keys = " dp", note = "<leader>dp: directory navigation" })
add({
  expect = [[_G.took("select", { prompt = "Dir", items = { "cwd", "git", "home", "1 up", "path=…" } }) and _G.answer("cwd")]],
  note = "it offers the aliases, the levels up and a typed path",
})
add({
  expect = [[_G.took("select", { prompt = "Pickers — Action", items = { "files", "grep", "smart", "filegrep" } }) and _G.answer("grep")]],
  note = "then the action",
})
add({ expect = '_G.took("live_grep", { root = _G.cwd() })', note = "grep in the directory chosen" })

add({ keys = "3 dp", note = "3<leader>dp: three levels up, no navigation picker" })
add({ expect = [[_G.took("select", { prompt = "Pickers — Action" }) and _G.answer("files")]] })
add({
  expect = [[_G.took("pick_files", { root = vim.fs.normalize(vim.fn.fnamemodify(_G.cwd(), ":h:h:h")) })]],
  note = "files three levels above the cwd",
})

-- The opt-in keys the nvim config sets.
key(
  "mp",
  "smart",
  '{ core = "filegrep", root = _G.cwd(), prompt = "CWD grep=> " }',
  "files in the cwd with a grep= filter"
)
key(
  "CW",
  "smart",
  '{ core = false, root = _G.cwd(), prompt = "CWD> " }',
  "smart (grep + find) in the cwd"
)
key(
  "CF",
  "smart",
  '{ core = false, root = _G.cfgdir(), prompt = "Config> " }',
  "smart in the nvim config"
)
key(
  "fa",
  "pick_files",
  "{ root = _G.cwd(), find = { hidden = true, no_ignore = true, follow = true } }",
  "every file in the cwd, hidden and ignored ones too"
)

-- The collections of the nvim config, with a folder of their own.
local flat = {
  { "mnf", "pick_files", "notes" },
  { "mng", "live_grep", "notes" },
  { "mns", "smart", "notes" },
  { "mlf", "pick_files", "notes_lua" },
  { "mlg", "live_grep", "notes_lua" },
  { "mvf", "pick_files", "notes_nvim" },
  { "mvg", "live_grep", "notes_nvim" },
  { "chf", "pick_files", "checklists" },
  { "chg", "live_grep", "checklists" },
  { "spf", "pick_files", "spickzettel" },
  { "spg", "live_grep", "spickzettel" },
  { "wlf", "pick_files", "wkdbooks_lua" },
  { "wlg", "live_grep", "wkdbooks_lua" },
  { "wvf", "pick_files", "wkdbooks_nvim" },
  { "wvg", "live_grep", "wkdbooks_nvim" },
}
for i = 1, #flat do
  local lhs, kind, name = flat[i][1], flat[i][2], flat[i][3]
  key(
    lhs,
    kind,
    '{ root = "/coll/' .. name .. '", prompt = "' .. name .. '> " }',
    name .. ": " .. kind
  )
end

-- The collections with a subdir picked first: wkdbooks lists the wkdbook-* folders without the prefix,
-- plugins_book every folder but the excluded ones.
local nested = {
  { "wkf", "pick_files", "wkdbooks", "alpha", "wkdbook-alpha", '"other"' },
  { "wkg", "live_grep", "wkdbooks", "alpha", "wkdbook-alpha", '"other"' },
  { "wks", "smart", "wkdbooks", "alpha", "wkdbook-alpha", '"other"' },
  { "pbf", "pick_files", "plugins_book", "alpha.nvim", "alpha.nvim", '"ALL", "TOOLS"' },
  { "pbg", "live_grep", "plugins_book", "alpha.nvim", "alpha.nvim", '"ALL", "TOOLS"' },
  { "pbs", "smart", "plugins_book", "alpha.nvim", "alpha.nvim", '"ALL", "TOOLS"' },
}
for i = 1, #nested do
  local lhs, kind, name, label, folder, hidden =
    nested[i][1], nested[i][2], nested[i][3], nested[i][4], nested[i][5], nested[i][6]
  add({ keys = " " .. lhs, note = "<leader>" .. lhs .. ": " .. name .. ": " .. kind })
  add({
    expect = '_G.took("pick_item", { prompt = "'
      .. name
      .. '> ", items = { "'
      .. label
      .. '" }, not_items = { '
      .. hidden
      .. ' } }) and _G.answer("'
      .. label
      .. '")',
    note = "it offers the subdirs of " .. name,
  })
  add({
    expect = '_G.took("'
      .. kind
      .. '", { root = "/coll/'
      .. name
      .. "/"
      .. folder
      .. '", prompt = "'
      .. label
      .. '> " })',
    note = "and searches the one picked",
  })
end

add({ expect = "#_G.calls == 0", note = "nothing else reached the picker" })

return {
  id = "pickers.bindings-keys",
  title = "The keys of pickers.nvim in the nvim config each open the picker they name, on the right root",
  task = "pickers.nvim/testblatt-bindings-checkliste",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  steps = steps,
  manual = {
    "In the real editor: the collections' folders of the nvim config (Notes, WKDBooks, rules-vault, tasks-vault) exist on this machine, so their keys do not end in 'directory not found'",
  },
}
