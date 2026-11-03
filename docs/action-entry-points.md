# Automatic action entry points

When no explicit action set is selected, Gambit searches resolution layers in
order: active namespace, each inherited namespace, global character settings,
global shared settings, and shipped `actions/standard`. The first layer with a
matching entry point wins. Within each layer, selectors are searched in order:

1. Job/sub-job, such as `blm-rdm.json`.
2. Job, such as `blm.json`.
3. Matching role selectors, such as `(mages).json`.
4. Matching inverse role selectors, such as `(~mages).json` for jobs outside the mages group.
5. `(all).json`.

If no layer matches, Gambit uses the existing
`actions/defaults/default-actions.json` starter fallback.

Each named namespace is one layer containing both
`settings/_ns/<namespace>/players/<player>/actions` and
`settings/_ns/<namespace>/actions`. For each selector, the character directory
is checked before the shared directory. Thus a namespace's shared `blm.json`
beats its character-specific `(all).json`, while a character `blm.json` wins
over the shared `blm.json`. A child namespace's `(all).json` beats any inherited
or shipped job-specific file.

Global `settings/<player>/actions` and `settings/actions` are separate fallback
layers; global character folders do not use a `players` subdirectory. For an
inheritance chain C → B → A, resolution searches C, B, A, global character,
global shared, then shipped standard actions.

Role filenames reuse target-selector job membership: `melee`, `ranged`, `mage`,
`healer`, `nuker`, `support`, and `tank`, including the aliases `mages`, `healers`,
`nukers`, and `tanks`. Use these filenames inside an `actions` folder. On Windows,
filename matching is case-insensitive. Multiple matching role files at one
layer are ordered by group size (smaller matching sets first), with the existing
selector order breaking ties. Only one entry point is loaded.

Positive role matches take precedence over inverse matches within a layer.
An inverse match in a child namespace still beats a positive match in a parent.
Inverse specificity uses the size of the complementary job set.
Inverse selectors support the job groups and aliases listed above, including
`melee_dps`; inverse leader and combined important/inverse syntax are not supported.

## Important entry points

`(!mages).json` and `(!all).json` retain their important-selector behavior within
a layer: exact job files at the same or closer character/shared location win,
but exact files beyond that local override boundary do not. Matching important
role files use selector specificity before `(!all).json`. Ordinary `(mages)` and
`(all)` already take precedence over every lower-priority resolution layer;
an important marker is not needed merely to override an inherited job file.

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
