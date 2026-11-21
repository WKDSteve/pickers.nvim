---@module 'pickers.entry_actions.ocr_image'
---@brief Engine-agnostic "read the text out of the selected image" action.
---@description
--- The OCR itself is images.nvim's (`images.ocr`, tesseract): this module only
--- asks whether it can run, checks the entry and hands the file over. There is
--- no second tesseract call here. images.nvim opens the recognised text in a
--- scratch split, so like `tree_reveal` this action CLOSES the picker (the
--- answer appears in another window, and a picker float would hide it) and
--- the adapters ask in two steps: `target(path)` while the picker is still
--- open (a refusal keeps it open), then `run(abs)` once it is gone.
---
--- **Offered only when it can work.** images.nvim installed, and tesseract
--- found (`images.ocr.available()`). The key is bound either way (the engines
--- take their key tables once, at setup), but without both the cheatsheet
--- leaves the row out and the key answers with one line.

local notify = require("lib.nvim.notify").create("[pickers.entry_actions.ocr_image]")

local M = {}

---The `pickers.keys` action name, shared by the engine adapters.
M.ACTION = "ocr_image"

---@internal
---images.nvim's `ocr` module when it can say whether tesseract is there.
---@return table|nil
local function ocr()
  local ok, mod = pcall(require, "images.ocr")
  if not ok or type(mod) ~= "table" or type(mod.available) ~= "function" then return nil end
  return mod
end

---True when images.nvim is installed and tesseract can be found.
---@return boolean
function M.available()
  local mod = ocr()
  if not mod then return false end
  local ok, found = pcall(mod.available)
  return ok and found == true
end

---The absolute path `run` would read, or nil (with one line saying why): no
---OCR, no path, a path that is not on disk, or one that is not an image by
---images.nvim's own extension list.
---@param path string|nil
---@return string|nil abs
function M.target(path)
  if not path or path == "" then
    notify.warn("No valid path found")
    return nil
  end
  if not M.available() then
    notify.warn("OCR needs images.nvim and tesseract (see :checkhealth images)")
    return nil
  end
  local abs = vim.fn.fnamemodify(path, ":p")
  if not vim.uv.fs_stat(abs) then
    notify.warn("Not an existing file: " .. abs)
    return nil
  end
  if not require("pickers.integrations.images").is_image(abs) then
    notify.warn("Not an image: " .. vim.fn.fnamemodify(abs, ":t"))
    return nil
  end
  return abs
end

---Read the text of `abs` (from `target`); it arrives in a scratch split.
---@param abs string
---@return boolean started
function M.run(abs)
  local ok, started = pcall(function()
    return require("images").ocr(abs)
  end)
  if not ok or started ~= true then
    notify.warn("OCR could not be started for " .. abs)
    return false
  end
  return true
end

return M
