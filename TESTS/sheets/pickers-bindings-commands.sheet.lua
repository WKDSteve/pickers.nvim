-- The commands of pickers.nvim as the nvim config has them (BINDINGS-RUNTIME-CHECKLIST.md: :Pickers and its
-- subcommands, the compat commands, the commands of the nine collections, :PickersRepeat and :PickersScopes): each
-- command is typed, and the sheet reads what reached the picker -- which picker, on which root, under which prompt,
-- with which query. The interactive steps in between are answered as a person would.
-- The engine is a recorder (TESTS/sheets/_bindings.lua). :PickersResume and :Pickers builtin hand over to the
-- engine's own pickers: they are in pickers-bindings-snacks.sheet.lua, on the real snacks.

local steps = {
  {
    lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); dofile(vim.fn.getcwd() .. "/TESTS/sheets/_bindings.lua")]],
    note = "pickers.setup as in the nvim config, the engine a recorder",
  },
}

local function add(step)
  steps[#steps + 1] = step
end

---Type `:cmd` and check the picker that came.
local function cmd(line, kind, want, note)
  add({ keys = ":" .. line .. "<CR>", note = ":" .. line .. ": " .. note })
  add({ expect = '_G.took("' .. kind .. '", ' .. want .. ")", note = ":" .. line .. " opened it" })
end

---Type `:cmd`, check the sub-picker that came and answer it.
local function ask(line, kind, want, answer, note)
  add({ keys = ":" .. line .. "<CR>", note = ":" .. line .. ": " .. note })
  add({ expect = '_G.took("' .. kind .. '", ' .. want .. ") and _G.answer(" .. answer .. ")" })
end

---Check the picker that came after an answer.
local function then_(kind, want, note)
  add({ expect = '_G.took("' .. kind .. '", ' .. want .. ")", note = note })
end

-- ---------- the compat commands ----------
cmd("LiveGrep", "live_grep", '{ root = _G.cwd(), prompt = "CWD> " }', "live grep in the cwd")
cmd("PickersRepeat", "live_grep", '{ root = _G.cwd(), prompt = "CWD> " }', "the last action again")
cmd(
  "FindConfig",
  "pick_files",
  '{ root = _G.cfgdir(), prompt = "Config> " }',
  "files in the nvim config"
)
cmd(
  "GrepConfig",
  "live_grep",
  '{ root = _G.cfgdir(), prompt = "Config> " }',
  "grep in the nvim config"
)
ask(
  "FindInFolder",
  "pick_dir",
  '{ prompt = "Folder> " }',
  '_G.fx("coll/notes")',
  "files in a picked folder"
)
then_(
  "pick_files",
  '{ root = "/coll/notes", prompt = "notes> " }',
  "the files of the picked folder"
)
cmd(
  "DirPicker cwd files",
  "pick_files",
  "{ root = _G.cwd() }",
  "files in a directory named by alias"
)
ask(
  "DirPicker",
  "select",
  '{ prompt = "Dir", items = { "cwd", "1 up" } }',
  '"1 up"',
  "the navigation picker"
)
add({ expect = [[_G.took("select", { prompt = "Pickers — Action" }) and _G.answer("smart")]] })
then_(
  "smart",
  '{ root = vim.fs.normalize(vim.fn.fnamemodify(_G.cwd(), ":h")) }',
  "smart one level up"
)
cmd(
  "FileGrep alpha grep=beta",
  "smart",
  '{ core = "filegrep", root = _G.cwd(), prompt = "CWD grep=> ", query = "alpha grep=beta" }',
  "files with a grep= filter, the query seeded"
)
cmd(
  "FileGrepConfig alpha",
  "smart",
  '{ core = "filegrep", root = _G.cfgdir(), prompt = "Config grep=> ", query = "alpha" }',
  "the same in the nvim config"
)
cmd(
  "RepoFiles alpha",
  "pick_files",
  '{ root = "/repos/alpha", prompt = "alpha> " }',
  "files of a repo named"
)
cmd(
  "RepoGrep alpha",
  "live_grep",
  '{ root = "/repos/alpha", prompt = "alpha> " }',
  "grep in a repo named"
)
ask(
  "RepoFiles",
  "pick_item",
  '{ prompt = "repos> ", items = { "alpha" }, not_items = { "plain" } }',
  '"alpha"',
  "the git repos below repos_dir to pick from"
)
then_("pick_files", '{ root = "/repos/alpha", prompt = "alpha> " }', "files of the repo picked")
ask(
  "RepoGrep",
  "pick_item",
  '{ prompt = "repos> ", items = { "alpha" } }',
  '"alpha"',
  "pick a repo"
)
then_("live_grep", '{ root = "/repos/alpha", prompt = "alpha> " }', "grep in the repo picked")

-- drives: the mount points of this machine (on Windows a PowerShell call, so it may take a while).
add({ keys = ":AllDrives<CR>", note = ":AllDrives: files on every drive" })
add({ wait = "#_G.calls > 0", timeout = 30000 })
then_("pick_files", '{ roots = 1, prompt = "All Drives> " }', "on every drive or mount point")
add({ keys = ":AllDrivesGrep<CR>", note = ":AllDrivesGrep: grep on every drive" })
add({ wait = "#_G.calls > 0", timeout = 30000 })
then_("live_grep", '{ roots = 1, prompt = "All Drives> " }', "on every drive or mount point")

-- system: an fd search; fd is a stand-in (fakes), the search runs in the engine, which is the recorder.
ask(
  "FindOnSystem",
  "input",
  '{ prompt = "System search" }',
  '"alpha " .. _G.fx("repos")',
  "asks for the search"
)
then_("pick_files", '{ root = "/repos", prompt = "System> " }', "files by fd below the path typed")
add({
  expect = [[_G.eq(type(_G.taken.opts.find_command), "table") and _G.taken.opts.find_command[1]:find("fd") ~= nil]],
  note = "with fd as the find command",
})

-- ---------- :Pickers ----------
ask(
  "Pickers",
  "select",
  '{ prompt = "Pickers — Scope", items = { "cwd", "config", "folder", "repos", "system", "drives", "dir", "notes", "plugins_book" } }',
  '"notes"',
  "the scope picker, collections included"
)
add({ expect = [[_G.took("select", { prompt = "Pickers — Action" }) and _G.answer("smart")]] })
then_("smart", '{ root = "/coll/notes", prompt = "notes> " }', "smart in the collection picked")
cmd("Pickers cwd files", "pick_files", '{ root = _G.cwd(), prompt = "CWD> " }', "scope cwd")
cmd(
  "Pickers config grep",
  "live_grep",
  '{ root = _G.cfgdir(), prompt = "Config> " }',
  "scope config"
)
ask(
  "Pickers folder files",
  "pick_dir",
  '{ prompt = "Folder> " }',
  '_G.fx("repos/alpha")',
  "scope folder"
)
then_("pick_files", '{ root = "/repos/alpha", prompt = "alpha> " }', "files of the folder picked")
ask("Pickers repos grep", "pick_item", '{ items = { "alpha" } }', '"alpha"', "scope repos")
then_("live_grep", '{ root = "/repos/alpha" }', "grep in the repo picked")
add({ keys = ":Pickers drives files<CR>", note = ":Pickers drives files: scope drives" })
add({ wait = "#_G.calls > 0", timeout = 30000 })
then_("pick_files", '{ roots = 1, prompt = "All Drives> " }', "on every drive")
ask("Pickers system files", "input", "{}", '"alpha " .. _G.fx("repos")', "scope system")
then_("pick_files", '{ prompt = "System> " }', "an fd search")
cmd(
  "Pickers dir 1 files",
  "pick_files",
  '{ root = vim.fs.normalize(vim.fn.fnamemodify(_G.cwd(), ":h")) }',
  "scope dir, one level up"
)
cmd(
  "Pickers tabs",
  "pick_files",
  '{ root = _G.cwd(), prompt = "CWD> " }',
  "the default tab group: its first tab"
)
add({
  keys = ":Pickers browse " .. "TESTS/sheets<CR>",
  note = ":Pickers browse: a directory on the item picker",
})
add({
  expect = [[_G.took("pick_item", { items = {} }) and #_G.taken.opts.items > 0]],
  note = "with its rows",
})

-- The nine collections: :Pickers <name> <action> and the generated :<Name>Files/Grep/Smart/FileGrep.
local colls = {
  { "notes", "Notes" },
  { "notes_lua", "NotesLua" },
  { "notes_nvim", "NotesNvim" },
  { "checklists", "Checklists" },
  { "spickzettel", "Spickzettel" },
  { "wkdbooks_lua", "WkdbooksLua" },
  { "wkdbooks_nvim", "WkdbooksNvim" },
}
for i = 1, #colls do
  local name, pascal = colls[i][1], colls[i][2]
  local at = '{ root = "/coll/' .. name .. '", prompt = "' .. name .. '> " }'
  cmd("Pickers " .. name .. " files", "pick_files", at, "the collection " .. name)
  cmd(pascal .. "Files", "pick_files", at, "files in " .. name)
  cmd(pascal .. "Grep", "live_grep", at, "grep in " .. name)
  cmd(pascal .. "Smart", "smart", at, "smart in " .. name)
  cmd(
    pascal .. "FileGrep alpha",
    "smart",
    '{ core = "filegrep", root = "/coll/' .. name .. '", query = "alpha" }',
    "files with a grep= filter in " .. name
  )
end

-- The two with a subdir picked first.
local nested = {
  { "wkdbooks", "Wkdbooks", "alpha", "wkdbook-alpha" },
  { "plugins_book", "PluginsBook", "alpha.nvim", "alpha.nvim" },
}
for i = 1, #nested do
  local name, pascal, label, folder = nested[i][1], nested[i][2], nested[i][3], nested[i][4]
  local pick = '{ prompt = "' .. name .. '> ", items = { "' .. label .. '" } }'
  local at = '{ root = "/coll/' .. name .. "/" .. folder .. '", prompt = "' .. label .. '> " }'
  local runs = {
    { "Pickers " .. name .. " grep", "live_grep" },
    { pascal .. "Files", "pick_files" },
    { pascal .. "Grep", "live_grep" },
    { pascal .. "Smart", "smart" },
    { pascal .. "FileGrep", "smart" },
  }
  for j = 1, #runs do
    ask(runs[j][1], "pick_item", pick, '"' .. label .. '"', "a subdir of " .. name .. " first")
    then_(
      runs[j][2],
      j == 5 and '{ core = "filegrep", root = "/coll/' .. name .. "/" .. folder .. '" }' or at,
      "then the picker in it"
    )
  end
end

-- ---------- :PickersScopes ----------
add({ keys = ":PickersScopes<CR>", note = ":PickersScopes: every scope it can resolve" })
add({
  wait = [[vim.iter(_G.notes):any(function(n) return n:find("Built-in scopes:", 1, true) and n:find("Collections:", 1, true) and n:find("plugins_book", 1, true) end)]],
  note = "the built-in ones and the collections with their folders",
})

add({ expect = "#_G.calls == 0", note = "nothing else reached the picker" })

return {
  id = "pickers.bindings-commands",
  title = "The commands of pickers.nvim in the nvim config each open the picker they name, on the right root",
  task = "pickers.nvim/testblatt-bindings-checkliste",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  fakes = { "fd" },
  steps = steps,
  manual = {
    "In the real editor: :AllDrives and :FindOnSystem list files of this machine (the sheet stops at the picker: the drives are probed, fd is a stand-in)",
  },
}
