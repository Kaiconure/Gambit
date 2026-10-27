# Extending the base namespace: cheatsheet

This guide targets this repository's `settings/_ns/_base` configuration. Examples
use a new namespace named `my-event`; substitute your own name. Commands use the
Windower console form; prefix them with `//` in game chat.

## Contents

- [Create and select a namespace](#create-and-select-a-namespace)
- [Choose where a change belongs](#choose-where-a-change-belongs)
- [Understand inheritance and precedence](#understand-inheritance-and-precedence)
- [Set variables and clear defaults](#set-variables-and-clear-defaults)
- [Extend actions through slots](#extend-actions-through-slots)
- [Order contributions and keep sequences together](#order-contributions-and-keep-sequences-together)
- [Replace, disable, or provide fallback contributions](#replace-disable-or-provide-fallback-contributions)
- [Guard imports and isolate variables](#guard-imports-and-isolate-variables)
- [Select characters and targets](#select-characters-and-targets)
- [Configure positioning and camp behavior](#configure-positioning-and-camp-behavior)
- [Configure weapon skills and skillchains](#configure-weapon-skills-and-skillchains)
- [Initialize and expose reusable functions](#initialize-and-expose-reusable-functions)
- [Test and troubleshoot](#test-and-troubleshoot)
- [Existing namespaces to learn from](#existing-namespaces-to-learn-from)

## Create and select a namespace

```text
gbt ns -set my-event -force -parent base
gbt ns
gbt ns -list
```

This creates the namespace, records its parent, and selects it. `base` resolves to
the physical `_base` directory. Base is abstract: inherit it rather than select
it directly. Existing `.nsconfig` files are preserved and must agree with the
requested parent.

Minimal `settings/_ns/my-event/.nsconfig`:

```json
{
  "inherits_from": "base",
  "description": ["My event setup", "Expected party: PLD, WAR, COR, WHM"]
}
```

Descriptions appear after successful loading. `"abstract": true` creates a shared
parent that cannot be selected directly. `"inheritable": false` prevents use as
a parent. Existing namespaces are inheritable by default.

Folder nesting does not establish inheritance. A child such as `my-event/boss`
needs `"inherits_from": "my-event"` explicitly; parent names are relative to the
namespace root. Cycles are invalid. Logical `sortie/leshonn`, for example, can
resolve through underscore-prefixed directories.

## Choose where a change belongs

Paths below are relative to `settings/_ns/my-event/`.

| Change | File |
|---|---|
| Shared variables and contributions | `actions/lib/common/common.json` |
| One job's variables/contributions | `actions/lib/common/whm.json` |
| A job group's variables/contributions | `actions/lib/common/(mages).json` |
| Everyone outside that group | `actions/lib/common/(~mages).json` |
| Current party leader | `actions/lib/common/(leader).json` |
| Reusable action block | `actions/lib/my-event-buffs.json` |
| Entire job action entrypoint | `actions/whm.json` |
| One character's shared overrides | `players/Carbonite/actions/lib/common/common.json` |
| One character's job overrides | `players/Carbonite/actions/lib/common/pld.json` |
| Explicit namespace main configuration | `players/Carbonite/main.json` |

Start with common variables and contributions. Copying a job entrypoint creates
a full replacement and stops that file from following future parent updates.
Library files outside automatic common locations must be imported to run.

Character `main.json` preferences normally save to `settings/<name>/main.json`.
An existing namespace `main.json` still wins during loading, but automatic saves
do not create or update namespace overrides. `settings/settings.old` is an archive
for reference, not an automatic import location.

## Understand inheritance and precedence

Ordinary files use first-match lookup: selected namespace, its explicit parent
chain, then global settings and shipped fallbacks as applicable. Character files
precede shared files within a namespace. Matching files are not merged wholesale.

Automatic common imports are additive. Base and inherited common files still
contribute when the child has its own common file. Within the same scope, ordinary
variable conflicts favor:

```text
exact job > positive group > inverse group > general defaults
```

Thus PLD's `pld.json` beats `(melee).json`, which beats `(~mages).json`. Namespace
proximity and character scope still matter, and explicit variable priorities can
override ordinary load ordering. At equal rank, the first loaded value wins;
do not rely on competing overlapping groups to express a critical override.

Entrypoints use job/subjob, job, positive groups, inverse groups, then `(all)`.
A positive entrypoint in a parent beats an inverse entrypoint in a child.
Important `(!mages).json` / `(!all).json` entrypoints have special inheritance
cutoff behavior; they are not common-file contribution replacements.

Explicit import paths:

| Reference | Search |
|---|---|
| `"my-event-buffs"` | Normal library search through the active hierarchy |
| `"$(PlayerLib)/my-event-buffs"` | Character library scope |
| `"$(SettingsLib)/my-event-buffs"` | Shared settings library scope |
| `"$(GlobalLib)/my-event-buffs"` | Shipped `actions/lib` directly |

## Set variables and clear defaults

A child common file can change behavior without replacing any actions:

```json
{
  "vars": {
    "ws": {
      "all_out_melee": { "disabled": false, "allow_cleave": false },
      "ws_finisher": { "disabled": true }
    },
    "dynamic_engagement": { "model": "frontline" }
  }
}
```

| Definition | Meaning |
|---|---|
| `"name": value` | Ordinary definition |
| `"!name": value` | High-priority definition |
| `"^name": value` | Fallback default |
| `"name": "$array.empty"` | Explicit empty table/list |
| `"name": "$object.null"` | Explicit clearing to nil |

Objects merge recursively; arrays are whole values. Prefixes are stripped from
runtime names. A prefixed object supplies its priority to descendants unless a
nested prefix overrides it. Ordinary JSON `null` is removed by parsing; `{}`
does not erase inherited children. Use explicit clearing markers, optionally
with `!`, when clearing is the intent.

Runtime helpers include `getVar`, `setVar`, `getOriginalVar`, and `resetVar`.
Original values are the latest loaded values before loading actions execute.

## Extend actions through slots

Inspect the selected configuration first:

```text
gbt slots
gbt slots -t battle
```

The listing groups slots by action type and preserves their placement order.
Repeated names appear at their first occurrence; fallback alternatives are also
listed. A listed slot is an insertion opportunity, not a guarantee of execution.

Every executable section automatically exposes:

```text
<type>-setup
<type>-priority
ordinary actions
<type>-fallback
```

Types: `loading`, `battle`, `idle_battle`, `pull`, `idle`, `resting`, `event`,
`dead`, `mounted`. An explicit placement of the same hook retains its position.
Other hooks such as `sc-priority`, `ws-priority`, `priority-buffs`, and
`normal-debuffs` depend on the loaded entrypoint: check the listing.

Add behavior in the child's common file:

```json
{
  "contributions": {
    "battle-priority": [
      { "import": "heals/remove-doom" }
    ]
  }
}
```

Normal contributions accumulate with inherited contributions. Normal action-cycle
rules still apply: an earlier eligible action takes the cycle, so recurring
priority work can starve later actions. Setup/fallback names do not automatically
provide once-only behavior or guaranteed execution.

## Order contributions and keep sequences together

```json
{
  "contributions": {
    "battle-priority": [
      { "priority": "high", "import": "my-event-buffs" },
      { "priority": 0, "import": "heals/remove-doom" }
    ]
  }
}
```

| Alias | Numeric value |
|---|---:|
| `highest` | -1000 |
| `high` | -100 |
| `normal` | 0 |
| `low` | 100 |
| `lowest` | 1000 |

Any finite numeric priority is allowed. Lower runs first within the slot. Omitted
priority means 0, not the preceding entry's priority. Ties preserve existing file
precedence and declaration order. Replacement/fallback selection happens first.
Priority never moves an action across slot boundaries.

Put an ordered sequence in a library's `actions` array and assign priority to
its contribution import: its expanded block stays together. Priority fields on
ordinary actions inside that library do not independently reorder the block.
Base's current `battle-priority` import is an example of this pattern.

## Replace, disable, or provide fallback contributions

| Contribution key | Behavior |
|---|---|
| `"ws-priority"` | Add to inherited contributions |
| `"!ws-priority"` | Keep this and closer contributions; discard lower-precedence ones |
| `"^ws-priority"` | Use only if no explicit definition exists; closest fallback wins |

Disable inherited slot behavior with an empty replacement:

```json
{
  "contributions": {
    "!ws-priority": { "optional": true, "actions": [] }
  }
}
```

`optional` suppresses missing-slot warnings; it does not disable an action.
For shared files targeting different job-specific hooks:

```json
{
  "contributions": {
    "geo/black-magic-burst, blm/black-magic-burst": {
      "required_for": ["GEO", "BLM"],
      "actions": [{ "import": "nukes/black-magic-burst" }]
    }
  }
}
```

Comma-separated keys contribute to every named slot that exists. With
`required_for`, any named slot satisfies the warning requirement for a matching
character. Requirements affect warnings, not whether the contribution executes.

Contribution names prefixed with `^` are defaults. A slot placeholder containing
a nested array is a different mechanism: ordered alternative names, selecting
the first declared contribution. See the detailed slot reference before editing
entrypoint placeholders. Contributions cannot contain slots or import libraries
that declare slots or further contributions.

## Guard imports and isolate variables

```json
{
  "contributions": {
    "battle-priority": [
      {
        "import": "heals/remove-silence",
        "precondition": ["me.main_job == 'WHM' or me.main_job == 'RDM'"]
      }
    ]
  }
}
```

Import preconditions accumulate through nesting and are checked at runtime
before the imported action's own conditions. They do not stop variable definitions
from being imported. Use job common files when you need job-specific defaults.

`with_vars` provides an isolated variable override for an imported branch:

```json
{
  "import": "buffs/haste-cycle",
  "with_vars": { "haste_cycle": { "targets": ["me"] } }
}
```

Branches inherit their variable scopes. Use this when importing a reusable
library more than once with different settings instead of mutating shared vars.

## Select characters and targets

| Selector | Meaning |
|---|---|
| `"PLD"`, `"WAR"` | Current main job |
| `"melee"`, `"mages"`, `"ranged"` | Defined job groups, which can overlap |
| `"leader"` | Party leader |
| `"Carbonite"` | Named character |
| `"^mages"` | Mages excluding self, not non-mages |
| `["*", "~mages"]` | Everyone except mages in supported target lists |

Other groups include `melee_dps`, `healer`, `nuker`, `support`, and `tank`, with
plural aliases for mage/healer/nuker/tank. Group definitions are in
`lib/target-selectors.lua`; do not assume melee, ranged, and mages are complements.

Filename `(~mages).json` applies to main jobs outside that group. Filename
`(^mages).json` is not supported. Inverse leader filenames are not supported.
Filename selection occurs at load time; it is not a live target filter.

## Configure positioning and camp behavior

Base uses `dynamic_engagement.model`: `frontline` positions relative to the enemy;
`member` uses the configured member-engagement anchor targets. Inspect the job
entrypoint because some jobs directly import frontline positioning.

Common settings include `frontline_engagement.angle`, `distance`, `distance_offset`,
and `member_engagement.targets` / `distance`. Tank alignment can set secondary
tanks' angle to `backside` at runtime; changing the default angle alone may not
override that policy. Base's `primary_tank_precondition` controls tank eligibility.

The `xp` melee common file also defines a battle camp. Its `camp.zone`,
`camp.location`, `camp.min_distance`, `camp.max_distance`, `camp.leader_only`, and
`camp.action_types` can cause movement independently of enemy-relative alignment.
When someone runs away from the monster, inspect the camp before changing angles.
Camp distance bounds describe the character's distance from camp.

Check the active zone and camp coordinates before copying an XP profile. A
waypoint route (`waypoints_ex.active`) is another independent movement policy.

## Configure weapon skills and skillchains

Useful base switches:

```json
{
  "vars": {
    "ws": {
      "all_out_melee": { "disabled": true, "allow_cleave": false },
      "ws_finisher": { "disabled": true }
    }
  },
  "contributions": {
    "sc-priority": {
      "optional": true,
      "actions": [{ "import": "ws/staged/four-part-light" }]
    }
  }
}
```

The imported staged library defines the sequence and its settings preset. Its
`ws.multi_stage_settings` can define participants, stage-specific lists, rotation,
and static exclusions. Multi-stage lists also support protected `!` participants
that override manual exclusions, but cannot grant missing weapon skills.

Capabilities are exchanged as weapon-skill IDs. Unknown characters wait for
capability information; updates invalidate the plan for its next evaluation.
Derived exclusions appear in compiled output without rewriting source JSON.

```text
gbt jobinfo -sync
gbt jobinfo -all
gbt wsinfo -sync
gbt wsinfo -all
gbt fn test/multi-stage
```

`compileMultiStage(vars.ws.multi_stage)` explicitly prepares a plan without
checking combat readiness. The multi-stage library includes loading compilation;
normal opener/closer checks retain lazy compilation and invalidation. Inspect
`.data/<character>/multi-stage/compiled/<JOB-SUB>.json` after evaluation. Plans
compiled before all capability replies arrive may temporarily exclude characters.

## Initialize and expose reusable functions

Use `loading`, not `load`, for an explicit initialization array:

```json
{
  "loading": [
    { "commands": ["setVar('user.ready', true)"] }
  ],
  "functions": [
    {
      "name": "my-event/status",
      "commands": ["log('My event configuration is loaded')"]
    }
  ]
}
```

Run the function with `gbt fn my-event/status`. A library can also mark an ordinary
action `"on_load": true` to promote it into loading. Keep dependent initialization
steps in one explicitly ordered loading array rather than relying on promotion
order across imports.

Loading actions are evaluated once per action load/recompilation before ordinary
state actions, when automation is enabled, unpaused, player-valid, and past the
zone-entry delay. Conditions still apply; skipped steps are not retried. Keep work
short. Loading does not wait for asynchronous IPC replies. Settings-only reloads
do not recompile actions or rerun loading initialization.

## Test and troubleshoot

1. Create a child of the closest useful parent rather than copying base.
2. Add a common file with only the intended vars/contributions.
3. Select it with `gbt ns -set my-event`, or reload after edits with `gbt r`.
4. Use `gbt slots -t battle` to verify hook names and placement.
5. Inspect variables with `gbt eval getVar('ws.multi_stage')` or a narrower path.
6. Sync capabilities and run the staged test when changing skillchains.
7. Check movement, casts, and competing jobs on each participating character.

| Symptom | Check |
|---|---|
| Namespace missing from list | `.nsconfig` exists; logical/physical name resolves |
| Child folder ignores expected parent | Explicit `inherits_from`, not folder nesting |
| Parent job entrypoint wins | Normal entrypoint specificity; consider common contributions first |
| Contribution warning | `gbt slots`; spelling; job-dependent `required_for` |
| Contribution never runs | Earlier eligible actions; preconditions; replacement/fallback selection |
| Variables do not change | Closer files, character scope, `!` priority, whole-array replacement |
| Clearing with `null` fails | Use `$object.null` or `$array.empty` |
| Unexpected movement | Camp, waypoint, tank angle, engagement model and distances |
| Skillchain excludes someone | Live jobs/skills, static exclusions, selector resolution, compiled plan |
| Saved config disappears on namespace switch | Namespace `main.json` may shadow shared saved preferences |
| A Lua feature is unchanged after `gbt r` | Reload the addon; JSON reload does not reload Lua modules |

`gbt ns -clear` returns to global lookup; with legacy files archived it may no
longer provide your normal setup. Use a known working inherited namespace instead.
`gbt r -ns my-event` performs a temporary namespace load without changing the
saved selection. `gbt r -settings-only` is not sufficient for action-file edits.

## Existing namespaces to learn from

Paths are relative to `settings/_ns` and reflect the current repository.

| Example | Pattern |
|---|---|
| `xp/.nsconfig` | Small child inheriting `base` |
| `xp/actions/lib/common/common.json` | Shared variables, required caster slots, optional chain contribution |
| `xp/actions/lib/common/(melee).json` | Job-group pull and camp settings |
| `xp/_cleave/actions/lib/common/common.json` | Variable-only specialization: free melee and waypoint activation |
| `sortie/_leshonn/actions/lib/common/common.json` | Empty replacements, custom nuke imports, guarded battle contributions |
| `sortie/_ghatjot/actions/lib/common/common.json` | Encounter-specific contributions and weapon-skill policy |
| `_base/actions/lib/common/whm.json` | Job-targeted buff and healing defaults |
| `_base/actions/lib/ws/staged/four-part-light.json` | Reusable sequence with a participant preset |
| `_base/actions/lib/common/common.json` | Shared defaults and prioritized battle-action import |

Copy the pattern, not encounter-specific coordinates, restrictions, or target
names. To avoid duplicate JSON keys, merge new vars and contributions into the
existing objects instead of pasting a second `vars` or `contributions` block.

In particular, `xp/cleave` currently inherits `base` directly, not `xp`. Its
physical nesting does not mean it receives XP's camp or chain contributions.

Further details: [slots](action-slots.md), [entrypoints](action-entry-points.md),
[namespace paths](namespace-folders.md), [scoped variables](scoped-variables.md),
[multi-stage participants](multi-stage.md), and [commands](commands.md).
