-- The collections of the installed nvim config on this machine (the hand check of pickers-bindings-keys, which
-- runs them on fixture folders): every collection's folder and repos_dir exist, so no key of a collection ends in
-- "directory not found", and every collection key the config names is mapped to its picker.
-- Runs on the installed config (`config = "user"`): a reported skip on CI and where there is no config.
return {
  id = "pickers.user-collections",
  title = "The collections of the installed config point at folders that exist, and their keys are mapped",
  task = "pickers.nvim/testblatt-bindings-checkliste",
  engine = "rpc",
  config = "user",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    {
      wait = [[package.loaded["pickers.config"] ~= nil and #require("pickers.config").get().collections > 0]],
      timeout = 30000,
      note = "the installed config has set up pickers.nvim with its collections",
    },
    {
      expect = [[(function()
        local missing = {}
        local cfg = require("pickers.config").get()
        for _, coll in ipairs(cfg.collections) do
          if vim.fn.isdirectory(coll.dir) ~= 1 then missing[#missing + 1] = coll.name .. ": " .. coll.dir end
        end
        if cfg.repos_dir and vim.fn.isdirectory(cfg.repos_dir) ~= 1 then
          missing[#missing + 1] = "repos_dir: " .. cfg.repos_dir
        end
        if #missing > 0 then error("missing folders: " .. table.concat(missing, "; "), 0) end
        return true
      end)()]],
      note = "every collection folder and repos_dir exist on this machine",
    },
    {
      expect = [[(function()
        local unmapped = {}
        for _, coll in ipairs(require("pickers.config").get().collections) do
          for action, lhs in pairs(coll.keys or {}) do
            local map = vim.fn.maparg(lhs, "n", false, true)
            local want = "[pickers] " .. coll.name .. ":"
            if type(map) ~= "table" or not (map.desc or ""):find(want, 1, true) then
              unmapped[#unmapped + 1] = lhs .. " (" .. coll.name .. " " .. action .. ")"
            end
          end
        end
        if #unmapped > 0 then error("not mapped to their collection: " .. table.concat(unmapped, ", "), 0) end
        return true
      end)()]],
      note = "every collection key of the config is mapped to its collection's picker",
    },
  },
}
