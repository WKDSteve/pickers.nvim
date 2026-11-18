-- The smart picker lists a root once and filters that list per keystroke (pickers.smart.search: `listing`,
-- `listed`); before that, every keystroke ran fd over the whole tree (90-145 ms in the nvim config repository).
-- This sheet keeps the measurement of the acceptance task: a generated tree of 10 000 files, the first listing
-- and a keystroke from the list, once with the file helper (when $LIB_FS_HELPER_TEST names one, else with what
-- the machine has: fd, rg or the Lua walk) and once with the helper switched off. A keystroke that runs fd again
-- or filters the list slowly is far above `max`.
-- What a person still feels while typing (redraws of the engine) stays in the task's hand check.

local SETUP = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
  _G.S = require("pickers.smart.search")
  _G.root = vim.fs.normalize(vim.fn.tempname())
  local uv = vim.uv
  for d = 1, 100 do
    local dir = ("%s/dir%03d/sub"):format(_G.root, d)
    vim.fn.mkdir(dir, "p")
    for f = 1, 100 do
      local fd = assert(uv.fs_open(("%s/file%03d_%03d.txt"):format(dir, d, f), "w", 420))
      uv.fs_close(fd)
    end
  end
  -- 10 000 files; the name of one of them, found by the keystroke
  _G.query = "file042_07"]]

---Start a fresh listing of the root (the first keystroke of a picker).
local START = [[_G.S.clear_listings(); _G.took = nil; _G.S.listing(_G.root, {})]]

---Done, and how long the listing took (ms), kept in `_G.took`.
local DONE = [[(function()
  local e = _G.S.listing(_G.root, {})
  if e.done and not _G.took then _G.took = vim.uv.hrtime() / 1e6 - e.at end
  return e.done and e.ok and #e.rels == 10000
end)()]]

---One keystroke from the finished listing (ms); it must find the ten files of the query.
local KEYSTROKE = [[(function()
  local t = vim.uv.hrtime()
  local files = _G.S.listed(_G.root, {}, _G.query, 0)
  local ms = (vim.uv.hrtime() - t) / 1e6
  assert(files and #files == 10, "listed " .. tostring(files and #files))
  return ms
end)()]]

return {
  id = "pickers.smart-listing-speed",
  title = "Smart picker: one listing of 10 000 files, a keystroke filters it in a few ms, with and without the helper",
  task = "pickers.nvim/abnahme-schnelle-dateilisten",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    { lua = SETUP, timeout = 120000, note = "a tree of 100 folders with 100 files each" },
    {
      lua = [[local exe = vim.env.LIB_FS_HELPER_TEST
        require("lib.nvim.fs.helper").configure(exe and exe ~= "" and exe or nil)]],
      note = "the helper of $LIB_FS_HELPER_TEST, else what the machine has",
    },
    { lua = START, note = "first keystroke: the listing starts" },
    { wait = DONE, timeout = 30000, note = "the listing holds all 10 000 files" },
    { measure = "_G.took", name = "first listing (as available)", unit = "ms", max = 10000 },
    { measure = KEYSTROKE, name = "keystroke (as available)", unit = "ms", runs = 9, max = 40 },
    { lua = [[require("lib.nvim.fs.helper").configure(false)]], note = "the helper switched off" },
    { lua = START, note = "first keystroke again, without the helper" },
    { wait = DONE, timeout = 30000, note = "the listing holds all 10 000 files" },
    { measure = "_G.took", name = "first listing (no helper)", unit = "ms", max = 10000 },
    { measure = KEYSTROKE, name = "keystroke (no helper)", unit = "ms", runs = 9, max = 40 },
    {
      lua = [[require("lib.nvim.fs.helper").configure(nil); vim.fn.delete(_G.root, "rf")]],
      timeout = 60000,
    },
  },
}
