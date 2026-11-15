-- TESTS/sheets/features.lua -- the functionalities of pickers.nvim as its user meets them; `testing sheets report`
-- says which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet that
-- names an id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The list follows docs/FEATURES/ (one entry per page there).
-- The sheets of `pickers.items` open the real picker libraries (telescope, fzf-lua, snacks): the workflow checks
-- them out beside this repository and installs fzf (a `requires` skip of a feature sheet is red under CI).
return {
  {
    id = "pickers.engines",
    title = "One set of pickers on telescope, fzf-lua or snacks, whichever is installed",
    surface = { "config:engine" },
    docs = "docs/FEATURES/ENGINES.md",
  },
  {
    id = "pickers.builtins",
    title = "The native pickers of the engine under one name: git branches, LSP lists, diagnostics, help tags, marks",
    docs = "docs/FEATURES/BUILTINS.md",
  },
  {
    id = "pickers.browse",
    title = "A file browser on the item picker: one directory per list, the file operations as rows",
    docs = "docs/FEATURES/BROWSE.md",
  },
  {
    id = "pickers.actions",
    title = "What to do in a scope (find files, grep and the rest); without an action an action picker appears",
    docs = "docs/FEATURES/ACTIONS.md",
  },
  {
    id = "pickers.items",
    title = "A list of the caller's own rows: keys of the call, several marked rows, a preview per row, the list again after an action",
    docs = "docs/FEATURES/ITEMS.md",
  },
  {
    id = "pickers.refine",
    title = "Narrow a result list by a stack of filter clauses, each one removable",
    docs = "docs/FEATURES/REFINE.md",
  },
  {
    id = "pickers.scopes",
    title = "Where to search: a scope resolves to roots, works with every action and tab-completes",
    docs = "docs/FEATURES/SCOPES.md",
  },
  {
    id = "pickers.quickfix",
    title = "The quickfix and location window kept as it is, with what it is missing added",
    docs = "docs/FEATURES/QUICKFIX.md",
  },
  {
    id = "pickers.persistence",
    title = "What survives a picker closing: the query typed, the picker that was open, the files visited",
    docs = "docs/FEATURES/PERSISTENCE.md",
  },
}
