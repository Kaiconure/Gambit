# Gambit

Gambit is a Windower 4 addon for FFXI that runs customizable action sequences
written in JSON, with Lua expressions for conditions and commands. Action sets
can coordinate combat, healing, buffs, positioning, and other tasks across
characters running the addon locally.

## Documentation

| Guide | Covers |
|---|---|
| [Commands](docs/commands.md) | Commands, aliases, options, and examples |
| [Actions](docs/actions.md) | Action files, conditions, and commands |
| [Variables](docs/variables.md) | Definitions, references, merging, CSV keys, and runtime state |
| [Event rules](docs/events.md) | Event types, rules, context, ordering, and troubleshooting |
| [Stock events](docs/stock-events.md) | Configure shipped gear rules with variables and contributions |
| [Equipment queue](docs/equipment.md) | Ordered swaps, pending/confirmed queries, retries, and action barriers |
| [Action properties](docs/properties.md) | Values available in action contexts |
| [Action functions](docs/functions.md) | Lua helpers used by actions |
| [Action slots](docs/action-slots.md) | Contributions, replacements, fallbacks, and priorities |
| [Action entrypoints](docs/action-entry-points.md) | Job, group, inverse-group, and leader filenames |
| [Namespace paths](docs/namespace-folders.md) | Folder layout and underscore aliases |
| [Scoped variables](docs/scoped-variables.md) | Private configuration for imported branches |
| [Multi-stage weapon skills](docs/multi-stage.md) | Participants, exclusions, and capability sharing |
| [Status panel prototype](docs/status-panel.md) | Movable status toggle, recent output, and tracked expressions |

The [base-extension cheatsheet](docs/extending-base-cheatsheet.md) is a worked
example based on the author's private namespace layout. Its `base`, `xp`, and
encounter profiles are **not shipped configurations**. Use its patterns with
namespaces and libraries you create yourself. The [wiki](https://github.com/Kaiconure/Gambit/wiki)
provides additional interface documentation.

## What is included

Reusable action libraries live under `actions/lib`, and the starter action set
is `actions/defaults/default-actions.json`. Files under `settings/` are local
user configuration and are not distributed with Gambit. This includes character
settings, namespaces, shared user libraries, and encounter profiles.

Names such as `base` and `my-event` below are examples, not built-in namespaces.
Creating a namespace creates its structure; it does not install a ready-made
combat profile or populate job actions.

## Getting started

Place the addon in your Windower addons directory, then load it in FFXI:

```text
//lua load gambit
```

| Control | Effect |
|---|---|
| Shift+Alt+G | Toggle automation |
| Ctrl+F | Toggle Gambit's custom follow on the current target |
| `//gbt enable` | Enable automation |
| `//gbt disable` | Disable automation |
| `//gbt status` | Show current status |

Use `//gbt` or `//gambit` in game chat. In the Windower console, omit the `//`.
Examples below use chat syntax. Review the loaded action set before enabling it:
behavior depends on your configuration and imported libraries.

Without a matching user entrypoint, Gambit uses its starter fallback. That set
includes frontline engagement, idle leader following, configured trust summoning,
and XP/CP ring use. It is a starting point for customization.

## Targeting and following

The default `leader` strategy follows the party leader's engaged target; when you
are the leader, it falls back to nearby aggroing enemies. `aggressor` can initiate
combat against idle enemies, prioritizing existing aggro.

```text
//gbt config -strategy leader
//gbt config -strategy aggressor
//gbt config -d 25
//gbt config -z 5
//gbt config -fd 4
```

`-d` controls horizontal targeting range, clamped to 5–50 yalms. `-z` controls
vertical range. `-fd` sets custom follow distance. Follow includes stuck-recovery
attempts, but does not provide full pathfinding or automatically follow someone
through a zone boundary.

## Organize your configuration

You can use global character action files, namespace configurations, or both:

```text
settings/
  CharacterName/
    main.json
    actions/
      whm.json
      lib/
  actions/
    lib/
  _ns/
    my-event/
      .nsconfig
      actions/
        whm.json
        lib/
          common/
            common.json
            whm.json
            (mages).json
            (~mages).json
      players/
        CharacterName/
          main.json
          actions/
            lib/
```

Only create the files you need. Ordinary file lookup uses the selected namespace,
its explicit parent chain, then global user configuration and shipped fallbacks
where applicable. Character-specific locations precede shared locations within a
namespace. The first matching ordinary file wins; whole job entrypoints and
`main.json` files are not automatically merged with their parent versions.

For automatic action selection, job/subjob and job files take precedence over
positive role selectors, inverse role selectors, and `(all).json`. For example,
`whm-rdm.json` is more specific than `whm.json`; `(~mages).json` matches main jobs
outside the mages group. Positive role matches across the hierarchy beat inverse
matches. See [entrypoint rules](docs/action-entry-points.md) for important
`(!group)` overrides and leader selectors.

An explicit library import such as `"import": "my-buffs"` searches the active
hierarchy. `$(PlayerLib)` and `$(SettingsLib)` constrain lookup to character and
shared user libraries; `$(GlobalLib)` addresses shipped `actions/lib` directly.
`import` and `imports` each accept a string or an array of references.

### Create and inherit namespaces

```text
//gbt ns -set my-event -force
//gbt ns -list
//gbt ns
```

Namespaces require a `.nsconfig`. `-force` initializes a missing namespace;
without it, selecting a missing namespace leaves the current configuration
unchanged. To build your own reusable parent, first create `base` and configure
it, then create a child:

```text
//gbt ns -set base -force
//gbt ns -set my-event -force -parent base
```

The child's `.nsconfig` can contain:

```json
{
  "inherits_from": "base",
  "description": ["My event configuration"]
}
```

Parent names are relative to the namespace root. Folder nesting alone does not
imply inheritance. Each namespace has at most one parent; missing parents and
cycles are rejected. Existing namespaces are inheritable by default. Set
`"inheritable": false` to forbid inheritance, or `"abstract": true` for a shared
parent that cannot be selected directly.

`settings/_ns` is preferred; an existing `settings/.ns` remains a compatibility
fallback when `_ns` is absent. Exact directory names win, with underscore-prefixed
aliases supported per segment: logical `base` can resolve to `_base`. Namespace
segments cannot use reserved `actions`/`players` names or Windows device names.

Selecting a namespace saves `default_namespace` in the character's global
`settings/<character>/main.json`. Addon startup restores that preference; job
changes retain it. `//gbt ns -clear` removes the preference and returns to global
lookup. `//gbt r -ns my-event` performs a temporary namespace load instead.

### Common files and variable precedence

Automatic common imports are additive across scopes and inherited namespaces.
They let a child extend a parent without copying its job entrypoints. Within the
same namespace and scope, ordinary variable conflicts favor exact-job common
files over positive groups, inverse groups, and general common defaults:

```text
common/pld.json > common/(melee).json > common/(~mages).json > common/common.json
```

The separate `actions/lib/common.json` path is also supported. More specific
namespace and character scopes retain their precedence. Explicit action-file
variables and imports retain their existing loading precedence. See the detailed
references for ordering among overlapping groups.

Variables support three explicit priorities:

| Definition | Priority |
|---|---|
| `"!name": value` | High |
| `"name": value` | Ordinary |
| `"^name": value` | Fallback default |

Higher priorities win regardless of load order; conflicting ordinary values at
the same priority keep the first loaded definition. Prefixes are removed from
runtime names. Shipped reusable defaults use fallback priority so user values
can override them.

Objects merge recursively; arrays are whole values. Use `$array.empty` or
`$object.empty` for an explicit empty table, and `$object.null` to clear a value.
Ordinary JSON `null` is discarded by parsing; `{}` does not erase inherited
children. Clearing markers also support priority prefixes. `with_vars` provides
private branch configuration for imports without changing shared defaults.

`getOriginalVar()` reads the loaded value before initialization actions execute;
`resetVar()` restores it. Runtime `setVar()` changes are not restricted by
load-time priorities.

### Saving and reloading

Main configuration changes save to `settings/<character>/main.json`, even while
using a namespace. Existing namespace `main.json` files can still override that
file when loading; automatic saves do not create or update namespace overrides.
Unchanged settings do not trigger a write.

```text
//gbt r
//gbt r -r
//gbt r -a my-actions
//gbt r -settings-only
//gbt r -r -v
```

- `r`: reload settings and job-based actions in the selected namespace.
- `r -r`: reload the current action name and its loaded namespace.
- `r -a my-actions`: load a named action set you provide.
- `r -settings-only`: reload main settings without recompiling actions.
- `r -r -v`: also write processed action JSON to the loaded configuration's
  `.output` directory. This does not change logging verbosity.

A full action reload resets action processing state without changing whether
automation is enabled. Action saves and processed output use the loaded action
configuration's namespace context. Lua code changes require an addon reload;
reloading JSON settings does not reload Lua modules.

## Extend actions with contribution slots

```text
//gbt slots
//gbt slots -t battle
```

Slot listings show the current configuration's insertion points by action type,
in placement order. They include empty hooks and fallback alternatives. Every
executable section has automatic `<type>-setup`, `<type>-priority`, and
`<type>-fallback` hooks; other names exist only when the loaded action set declares
them. There is no built-in guarantee of private-profile slots such as `sc-priority`.

For example, a user common file can add battle actions:

```json
{
  "contributions": {
    "battle-priority": [
      { "priority": "high", "import": "my-battle-actions" }
    ]
  }
}
```

This example requires you to supply `actions/lib/my-battle-actions.json` in a
user library location. Normal contributions accumulate; `!slot-name` replaces
lower-precedence contributions, and `^slot-name` supplies a fallback when no
explicit definition exists. An empty replacement disables inherited contributions
for that hook. `optional` and `required_for` control missing-slot warnings.

Contribution action priorities accept finite numbers or `highest` (-1000),
`high` (-100), `normal` (0), `low` (100), and `lowest` (1000). Lower runs first
within the slot. Ties preserve existing order; an imported block stays together.
Priority does not move an action across slot boundaries or change replacement
and fallback selection. See [action slots](docs/action-slots.md) for complete rules.

## Conditions, initialization, and errors

Actions run in order within their section. An earlier eligible action can consume
the cycle, so configure conditions and frequencies to allow later actions to run.
`precondition` expressions accumulate through imports and run before an action's
`when`; they do not prevent imported variable defaults from loading.

`frequency` controls the execution interval, `miss_frequency` the failed-condition
interval, and `frequencies` supplies a default for both. Explicit individual values
win. An optional `else` command branch executes on a false condition and consumes
the action opportunity too. Failed preconditions skip both branches.

Use a `loading` array for initialization, or `"on_load": true` to promote an
action into loading. Loading runs before ordinary state actions when automation
is enabled and eligible after zone entry. Each loading action is evaluated once;
false conditions are not retried. Dependent steps should use an explicitly
ordered loading array. A settings-only reload does not rerun initialization.

Runtime expression/command errors quarantine the affected action until a full
action reload; commands after the failure are skipped. Errors are reported in
chat and `.data/action-errors/<Character>-YYYYMMDD.log`. Named functions support
explicit retry with `-retry`. Syntax errors omit the invalid action during
compilation. See [commands](docs/commands.md) for diagnostics and retry syntax.

```text
//gbt eval getVar('my_settings')
//gbt verbosity -level verbose
```

`eval` executes Lua in a temporary action context and reports its first result.
It can have real side effects; it is not a read-only expression viewer.

## Character coordination and multi-stage weapon skills

Local instances exchange job information and available weapon-skill IDs over IPC:

```text
//gbt jobinfo -sync
//gbt jobinfo -all
//gbt wsinfo -sync
//gbt wsinfo -all
```

Both commands support `-send` to broadcast local information. Sync requests run
on addon load/login. The IPC loop broadcasts weapon-skill capability changes,
including changes caused by equipment, when the available ability list changes.
`wsinfo` displays weapon-skill names grouped by character.

Multi-stage configurations can use job/group selectors, character names,
stage-specific participants, static exclusions, and rotation. Capability filtering
adds derived exclusions while preserving manual rules. Unknown characters cannot
be assigned until their capabilities arrive. Capability/roster changes rebuild
cached plans on their next evaluation. Compiled diagnostics are written under
`.data/<character>/multi-stage/compiled/`.

`compileMultiStage(config)` prepares a plan without checking combat readiness;
normal opener/closer checks retain lazy compilation. The shipped
`ws/multi-stage` library provides loading initialization and a named
`test/multi-stage` function when imported. The sequence and participant settings
are user-supplied: named encounter chains and namespace profiles are not included
under `settings`. See [multi-stage documentation](docs/multi-stage.md).

Target lists support job abbreviations and overlapping groups such as `melee`,
`mages`, and `ranged`. `^mages` means other mages, while `["*", "~mages"]` means
everyone except mages. These runtime selectors differ from inverse filenames.
Use the [function reference](docs/functions.md) for targeting helpers and the
[entrypoint reference](docs/action-entry-points.md) for filename matching.
