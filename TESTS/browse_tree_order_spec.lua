-- Test code: a nil here (a require, a fixture read) must crash and name it.
---@diagnostic disable: need-check-nil
-- pickers.nvim -- the directory browser lists a folder in the order the own
-- tree of filetree.nvim shows it in (no framework, no network).
--
-- Run:
--   nvim -l TESTS/browse_tree_order_spec.lua
--
-- Both read the rule from `lib.nvim.fs.listing`; this spec pins that they
-- still agree on real folders, position by position. filetree.nvim is not a
-- dependency of pickers.nvim: it is looked up ($FILETREE_NVIM_DIR, a sibling
-- checkout, $REPOS_DIR) and without it the comparison is reported as "n/a".
-- A file of its own, so that the modules of filetree.nvim are not loaded into
-- the process of pickers_spec.lua.

-- ── Self-bootstrapping runtimepath ──────────────────────────────────────────
local this = debug.getinfo(1, "S").source:sub(2) -- strip leading '@'
local tests_dir = vim.fn.fnamemodify(this, ":p:h")
local root = vim.fn.fnamemodify(tests_dir, ":h") -- TESTS -> repo root
vim.opt.runtimepath:append(root)

---@param path string|nil
---@return boolean
local function is_dir(path)
  return type(path) == "string" and path ~= "" and vim.fn.isdirectory(path) == 1
end

local siblings = vim.fn.fnamemodify(root, ":h")
local lib = siblings .. "/lib.nvim"
if is_dir(vim.env.LIB_NVIM_PATH) then
  lib = vim.env.LIB_NVIM_PATH
elseif vim.env.REPOS_DIR and is_dir(vim.env.REPOS_DIR .. "/lib.nvim") then
  lib = vim.env.REPOS_DIR .. "/lib.nvim"
end
if is_dir(lib) then vim.opt.runtimepath:append(lib) end

---filetree.nvim with an own tree that reads the shared rule, or nil.
---@return string|nil
local function find_filetree()
  local candidates = { vim.env.FILETREE_NVIM_DIR, siblings .. "/filetree.nvim" }
  if vim.env.REPOS_DIR then candidates[#candidates + 1] = vim.env.REPOS_DIR .. "/filetree.nvim" end
  for _, dir in pairs(candidates) do
    if is_dir(dir) and vim.fn.filereadable(dir .. "/lua/filetree/native/source/files.lua") == 1 then
      return dir
    end
  end
  return nil
end

-- ── Tiny assertion harness ──────────────────────────────────────────────────
local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. (detail and ("  → " .. detail) or ""))
  end
end

local function finish()
  print(string.format("\n%d passed, %d failed", passed, failed))
  os.exit(failed == 0 and 0 or 1)
end

local filetree = find_filetree()
if not filetree then
  print("  n/a  browse vs own tree: filetree.nvim not found (no own tree to compare with)")
  finish()
end
vim.opt.runtimepath:append(filetree)

local ok_service, service = pcall(require, "filetree.native.fs.service")
local ok_files, files = pcall(require, "filetree.native.source.files")
if
  not (ok_service and ok_files)
  or type(service.list_sync) ~= "function"
  or type(files.nodes) ~= "function"
then
  print("  n/a  browse vs own tree: this filetree.nvim has no own tree that lists a folder")
  finish()
end

local browse = require("pickers.browse")

---One folder as the directory browser lists it: `{ name, kind }` per row.
---@param dir string
---@return string[]
local function through_browser(dir)
  local out = {}
  for _, entry in ipairs(browse.entries(dir, { actions = false })) do
    if entry.kind == "dir" or entry.kind == "file" then
      out[#out + 1] = entry.kind .. " " .. vim.fs.basename(entry.path)
    end
  end
  return out
end

---The same folder as the own tree shows it (sorted by name, the default; no
---merged folder chains, which are one row for several folders).
---@param dir string
---@return string[]
local function through_tree(dir)
  local entries = assert(service.list_sync(vim.fs.normalize(dir)))
  local nodes = files.nodes(entries, {
    loader = function() end,
    sort = { kind = "name" },
    group_empty = false,
  })
  local out = {}
  for _, node in ipairs(nodes) do
    out[#out + 1] = node.kind .. " " .. node.label
  end
  return out
end

---@param label string
---@param dir string
---@param at_least integer  Rows the folder must have, so that an empty read cannot pass.
local function same_order(label, dir, at_least)
  local a, b = through_browser(dir), through_tree(dir)
  local differ = {}
  for i = 1, math.max(#a, #b) do
    if a[i] ~= b[i] then
      differ[#differ + 1] = ("%d: browser %s, tree %s"):format(i, tostring(a[i]), tostring(b[i]))
    end
  end
  check(
    ("browse vs own tree: %s, %d rows, zero positions differ"):format(label, #a),
    #differ == 0 and #a >= at_least,
    #differ > 0 and table.concat(differ, "; ", 1, math.min(#differ, 5)) or (#a .. " rows")
  )
end

-- real folders: this repository and its largest source folder
same_order("the repository root", root, 5)
same_order("lua/pickers", root .. "/lua/pickers", 5)
if is_dir(lib) then same_order("lib.nvim's lua/lib/nvim", lib .. "/lua/lib/nvim", 5) end

-- the names the rule was written for: the row text of a folder ends in `/`,
-- case differs, twins differ in case only, and a link points to a folder
do
  local tmp = vim.fs.normalize(vim.fn.tempname())
  for _, name in ipairs({ "foo", "foo.bar", "Foo-x", "target", ".git", "Zeta", "alpha" }) do
    vim.fn.mkdir(tmp .. "/" .. name, "p")
  end
  for _, name in ipairs({ "a", "a.txt", "B.md", ".hidden", "_x", "Makefile", "10.txt", "9.txt" }) do
    vim.fn.writefile({ "x" }, tmp .. "/" .. name)
  end
  local rows = 15
  -- a junction on Windows (needs no privilege), a symlink elsewhere
  if vim.uv.fs_symlink(tmp .. "/target", tmp .. "/zlink", { junction = true }) then
    rows = rows + 1
  end
  -- twins that differ in case only exist where the file system tells them apart
  vim.fn.writefile({ "x" }, tmp .. "/readme")
  vim.fn.writefile({ "x" }, tmp .. "/Readme")
  rows = rows + (vim.uv.fs_stat(tmp .. "/README") and 1 or 2)
  same_order("a folder of awkward names", tmp, rows)
  vim.fn.delete(tmp, "rf")
end

finish()
