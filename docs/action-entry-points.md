# Automatic action entry points

When no explicit action set is selected, Gambit searches for these entry points
in order:

1. Job/sub-job, such as `blm-rdm.json`.
2. Job, such as `blm.json`.
3. Matching role selectors, such as `(mages).json`.
4. Matching inverse role selectors, such as `(~mages).json` for jobs outside the mages group.
5. `(all).json`.
6. The existing `actions/defaults/default-actions.json` starter fallback.

Each stage searches all applicable locations: active namespace, inherited
namespaces, base settings, and shipped standard actions. Character-specific
locations precede shared locations. An inherited job file therefore wins over
an ordinary role or catch-all file in a child namespace.

Role filenames reuse target-selector job membership: `melee`, `ranged`, `mage`,
`healer`, `nuker`, `support`, and `tank`, including the aliases `mages`, `healers`,
`nukers`, and `tanks`. Use these filenames inside an `actions` folder. On Windows,
filename matching is case-insensitive. Multiple matching role files at one
location are considered alphabetically. Only one entry point is loaded.

Positive role matches across all locations take precedence over inverse matches,
so an inherited `(melee).json` beats a local `(~mages).json` for PLD. Inverse
matches search closest locations first, alphabetically within each location.
Inverse selectors support the job groups and aliases listed above, including
`melee_dps`; inverse leader and combined important/inverse syntax are not supported.

## Important entry points

Use `(!mages).json` or `(!all).json` to override entry points from lower-priority
locations. Exact job/sub-job and job files at that location or higher-priority
locations still win. Matching important role files are considered alphabetically,
before `(!all).json`.

For example, `bcnm/actions/(!mages).json` wins over an inherited
`base/actions/blm.json`, but `bcnm/actions/blm.json` wins over both.

This affects only entry-point selection. Common files and explicit imports
continue to inherit normally. Explicit action-set commands continue to load
the requested name; plain `all.json` has no automatic fallback meaning.

## Role and leader common files

Inside each `actions/lib/common` folder, automatic imports are additive and
ordered from lowest to highest priority: `common.json`, matching inverse role files
in alphabetical order, matching positive role files in alphabetical order, then
the job file (for example `BLM.json`). For PLD, `pld.json` wins over `(melee).json`,
which wins over `(~mages).json` when ordinary variable definitions conflict. Explicit
variable priorities still apply. The existing
`actions/lib/common.json` follows these. Namespace inheritance priority is
unchanged. Common files do not support `(all)` or important selector filenames;
use `common.json` and variable assignment priority markers instead.

`(leader).json` matches the current party leader at settings-load time. It works
in both common folders and action entry points; `(!leader).json` is supported
only as an entry point. It participates in alphabetical selector ordering.

If any leader-specific file exists in the applicable hierarchy, each character
records their leadership eligibility at load time. A stable change to that
eligibility produces a one-time reload recommendation in chat and the console.
Configuration is not automatically reloaded. Missing party data and the initial
zoning interval are ignored. A full reload refreshes this tracking; a settings-only
reload retains it because it reuses the previously compiled actions.

Use runtime preconditions for policies requiring immediate leadership handoff.
