# Actions

An action answers *what*. Three of them, each usable with any scope from
[SCOPES.md](SCOPES.md). Omit the action and an action picker appears.

## Find files

Filename search over the scope's roots, via `fd`, honouring the resolved
`find` flags below.

- **Module:** [`actions/files.lua`](../../lua/pickers/actions/files.lua)
- **Usercmds:** `:Pickers <scope> files`
- **Config:** `find`

## Live grep

Content search over the same roots. Live grep always runs
`--hidden --no-ignore-vcs` unconditionally — the flag escalation below is a
`files` concern, and is silently ignored here rather than half-applied.

Exclude globs are the exception: `find.exclude` applies to grep as well, since
"never look in this directory" is a statement about the search space, not about
how hard to look.

- **Module:** [`actions/grep.lua`](../../lua/pickers/actions/grep.lua)
- **Usercmds:** `:Pickers <scope> grep`
- **Config:** `find.exclude`

## Smart — grep and find, merged and ranked

The action that is not just a wrapper. `smart` runs `rg` (content) **and** `fd`
(filenames) for the same live query and merges both result sets into **one
list, ranked on a shared scale** — so a filename hit and a content hit
interleave by relevance instead of appearing as two blocks, and a file matched
by name that *also* contains matches floats to the top.

The scorer is engine-agnostic and pure: `smart.query(query, opts)` is the one
entry point all three adapters drive, and each engine only has to provide a
live-finder shape for it (snacks an async live finder with `sort_empty = false`,
telescope a finder object plus an empty sorter, fzf-lua the Lua-function live
mode with a writer).

The editor never waits for `rg`/`fd`: each keystroke starts the search as a
job (`smart.query_async`, `pickers.smart.job`) `smart.debounce` ms (30) after
the last key, and the picker gets the rows when the processes are done. The
next keystroke cancels the running search and kills its processes, so only the
result of the newest query is ever shown. Measured with `testing perf` on the
smart sheet (StevesPC): 482 ms of blocked editor before (rg up to 220 ms per
keystroke, fd 102 ms, filegrep's rg 82 ms), 0 ms now.

The filenames come from **one listing per root**, not from an `fd` per
keystroke: when the picker opens, `lib.nvim.fs.fast` lists every root (the file
helper of filetree.nvim when it is installed, else `fd`, `rg` or a Lua walk),
and each keystroke filters that list the way `fd` applies its pattern (file
name, smart-case, `.` any character). A query only a regex can answer (`[`, `*`,
`|`, `/` ...) still runs `fd` for that keystroke. Measured on lib.nvim (1 451
files) and the tasks vault (7 352): 90-145 ms per keystroke before, now the
first one 33-53 ms with the helper (144-153 ms with `fd`) and every later one
0-3 ms. A listing is reused for 15 s; `vim.g.pickers_smart_listing = false`
before the first search turns it off. `filegrep` lists its files the same way.

- **Module:** [`smart/`](../../lua/pickers/smart/) — `query`, `search`, `score`
- **Usercmds:** `:Pickers <scope> smart`, `:{PascalName}Smart` per collection
- **Config:** `smart = { weights, limit, timeout, debounce }`; `weights.both`
  is the bonus for a file matched by both sources
- **Keymaps:** opt-in `cwd_smart`, `config_smart`, `folder_smart`, and
  `keys.smart` per collection

### Frecency boost

Opt-in ranking input, off by default. Visits are recorded on `BufReadPost` for
real listed file buffers only and persisted as JSON; the score combines
log-dampened visit frequency with a bucketed recency weight.

The lookup is built **once per query by the caller** and threaded into
`score.rank` as an optional parameter — the scorer never reads from disk, which
is what keeps it pure and testable.

- **Module:** [`smart/frecency.lua`](../../lua/pickers/smart/frecency.lua)
- **Config:** `smart.frecency = { enabled, weight, dir }` — `dir` defaults to
  `stdpath("data")/pickers.nvim/`

### One row per file

Opt-in. Collapses multiple grep hits in the same file down to the single
highest-scoring line. A display-density choice, not a re-scoring: the file's
other matches are dropped from the list rather than merged into its score.

- **Module:** [`smart/score.lua`](../../lua/pickers/smart/score.lua)
- **Config:** `smart.dedup_grep_rows` (default `false`)

## Filegrep — files by path, narrowed by content

A files picker whose prompt also takes `grep=<pattern>`: `akronyms grep=NWBC`
lists files with `akronyms` in the path **and** `NWBC` in the content. Several
`grep=` tokens AND together; without one it is a plain files picker, so it can
be the everyday main picker. One row per file, opening at the first hit.

It reuses the engines' `smart` live-picker adapters (`opts.core = "filegrep"`),
so there is no per-engine code. The content half honours `find.*` like the
file listing does, later `grep=` patterns only scan the files that survived,
and process output is memoised for a few seconds so refining the path part
spawns nothing.

- **Module:** [`filegrep/`](../../lua/pickers/filegrep/) — `parse`, `query`;
  [`actions/filegrep.lua`](../../lua/pickers/actions/filegrep.lua)
- **Usercmds:** `:Pickers <scope> filegrep`, `:FileGrep [query]`,
  `:FileGrepConfig [query]`, `:{PascalName}FileGrep` per collection
- **Keymaps:** opt-in `cwd_filegrep`, `mappings.<scope>_filegrep`, and
  `keys.filegrep` per collection
- **Config:** shares `smart = { weights, limit, timeout, debounce }`
- Details: [commands.md](../commands.md#the-filegrep-action)

## Search-flag escalation

Three independent flags widen a `files` search, and they can be combined with
`+`:

| Flag | Reaches |
| --- | --- |
| `hidden` | dotfiles |
| `no_ignore` | files excluded by `.gitignore` |
| `follow` | across symlinks |

`all` is the shorthand for all three, and works as a per-call escape hatch that
overrides the configured `find.*` defaults for that one search only.

They are separate because they answer different questions — all-or-nothing
meant walking `node_modules` just to see a `.env`. An unknown flag is reported
and the whole escalation dropped, rather than applied in part.

- **Module:** [`command/init.lua`](../../lua/pickers/command/init.lua)
- **Usercmds:** `:Pickers cwd files hidden+follow`, `:Pickers cwd files all`
- **Config:** `find = { hidden, no_ignore, follow, exclude }`
- **Keymaps:** opt-in `cwd_find_all`
