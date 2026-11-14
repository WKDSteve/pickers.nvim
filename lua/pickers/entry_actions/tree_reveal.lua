---@module 'pickers.entry_actions.tree_reveal'
---@brief Engine-agnostic "show the selected entry in the file tree" action.
---@description
--- The counterpart of `system`'s `reveal` (the OS file manager) inside the
--- editor: the tree opens and its cursor lands on the entry.
---
--- Which tree is not this plugin's business. The question goes to
--- `lib.nvim.explorer`, the registry every tree plugin signs in to
--- (filetree.nvim does, with whatever backend it runs): `can_reveal()` says
--- whether one of them can show a path, `reveal(path)` does it. Nothing here
--- names neo-tree, nvim-tree or filetree.
---
--- **Offered only when a tree can do it.** The key is bound either way (the
--- engines take their key tables once, at setup, long before a tree plugin may
--- be loaded), but without such a tree the cheatsheet leaves the row out and
--- the key answers with one line instead of closing the picker.
---
--- Unlike the copy and system actions this one CLOSES the picker: the answer
--- appears in another window, and a picker float on top of it would hide it.
--- The adapters therefore ask in two steps: `target(path)` while the picker is
--- still open (a refusal keeps it open), then `run(abs)` once it is gone.

local notify = require("lib.nvim.notify").create("[pickers.entry_actions.tree_reveal]")
local feedback = require("lib.nvim.notify").create("[pickers]", { messages = true })

local M = {}

---The `pickers.keys` action name, shared by the engine adapters.
M.ACTION = "reveal_in_tree"

---@internal
---`lib.nvim.explorer` when it can reveal at all (an older lib.nvim cannot).
---@return table|nil
local function explorer()
  local ok, mod = pcall(require, "lib.nvim.explorer")
  if not ok or type(mod) ~= "table" then return nil end
  if type(mod.can_reveal) ~= "function" or type(mod.reveal) ~= "function" then return nil end
  return mod
end

---True when a tree that can show a path is there right now.
---@return boolean
function M.available()
  local mod = explorer()
  if not mod then return false end
  local ok, can = pcall(mod.can_reveal)
  return ok and can == true
end

---The absolute path `run` would reveal, or nil (with one line saying why): no
---tree, no path, or a path that is not on disk. A picker entry is not always
---a file (a display label, a path relative to the wrong base); a tree asked
---for one of those re-roots itself somewhere unrelated.
---@param path string|nil
---@return string|nil abs
function M.target(path)
  if not path or path == "" then
    notify.warn("No valid path found")
    return nil
  end
  if not M.available() then
    notify.warn("No file tree that can reveal a path (filetree.nvim) is loaded")
    return nil
  end
  local abs = vim.fn.fnamemodify(path, ":p")
  if not vim.uv.fs_stat(abs) then
    notify.warn("Not an existing file or directory: " .. abs)
    return nil
  end
  return abs
end

---Show `abs` (from `target`) in the tree.
---@param abs string
---@return boolean ok
function M.run(abs)
  local mod = explorer()
  local ok, shown, name = false, false, nil
  if mod then
    ok, shown, name = pcall(mod.reveal, abs)
  end
  if not (ok and shown == true) then
    notify.warn("The file tree could not reveal " .. abs)
    return false
  end
  local tail = vim.fn.fnamemodify((abs:gsub("[/\\]+$", "")), ":t")
  feedback.info(
    string.format("revealed %s in %s", tail, type(name) == "string" and name or "the tree")
  )
  return true
end

return M
