### Please refer to the [wiki](https://github.com/Kaiconure/Gambit/wiki) for my ongoing attempt at documenting the entire Gambit rules interface.
---

| Tips                                                         |
| ------------------------------------------------------------ |
| *Shift+Alt+G* on the keyboard will toggle automation on or off. |
| *Ctrl+F* on the keyboard will toggle a custom "follow" operation on your current target. Hitting the hotkey again will cancel your follow. |



# Gambit

[Command reference](docs/commands.md) — chat/console commands, aliases, options, and examples.

## Overview

Gambit is a Windower 4 addon that allows you to define data-driven, customizable, scripted action sequences for use in FFXI. It is used to automate all manner of operations within the game.

The automation documentation is broken down into several categories:

- Actions
  - [An introduction to actions](./docs/actions.md) - An overview of the basic action structure; how they are defined, how they are triggered, and how they are configured.
  - Libraries - Pre-defined actions ready for you to use
- Lua interface
  - [Action properties](./docs/properties.md) - An overview of the properties available for use in your action conditions and commands.
  - [Action functions](./docs/functions.md) - An overview of the functions available for use in your action conditions and commands. 



## The Basics

Once you've got the addon installed, it can be loaded in the standard way.

```bash
//lua r gambit
```

Doing so, it will show you some information including how to enable automation with the `Shift+Alt+G` hotkey. The same hotkey will disable automation again, and the addon will output information about its current enabled/disabled state as you change it.

The default actions will cause you to engage with any aggroing mob near you, and will use the best available XP or CP rings on hand.

If you want to *initiate* aggro, you can change the *targeting strategy* to "aggressor". As the name suggests, the aggressor strategy will pick the nearest mob and fight it. If you already have aggro, the aggroing mob will take priority. That is, Gambit won't engage with an idle mob while another one is coming for you.

To change the strategy to aggressor, run the following command:

```bash
//gbt config -strategy aggressor
```

So switch back, you can use the following:

```bash
//gbt config -strategy leader
```

The "leader" strategy (default) will have you engage whatever mob your party leader is engaged with. It's smart enough to detect if you *are* the party leader, and will instead fall back to the default "nearest aggroing mob" behavior.

By default, Gambit will only "see" mobs within 25 yalms of your position. You can set this to 50 (the max that FFXI allows) using the following command:

```bash
//gbt config -d 50
```

Any value between 5 and 50 (inclusive) is accepted; any other value will be clamped to this range.

Similarly, Gambit gives you the ability to control the maximum vertical ("Z") distance it will look for. This is useful on multi-leveled areas (think of Escha Ru'Aun) where you wouldn't want to try to attack something 20 yalms directly below you.

The default Z distance is 5.0 yalms, and it can be configured with the following command:

```bash
//gbt config -z 3
```

As you've likely already guessed, this will set the Z distance to 3 rather than the default 5.

The custom follow mentioned in the tips at the very top of this document has a few added benefits. Firstly, it will try to "jitter" itself out of corners if it detects that it's stuck. This isn't true pathfinding, but it will try to backup for a bit and course correct. This won't get you out of a maze, but it will get you around pillars or sharp corners.

The second thing that the custom follow will get you is a configurable follow distance. For example, if you run the following your follow will not get closer than 4 yalms from the target;

```bash
//gbt config -fd 4
```

Note that there will be some variation here while you're moving, as server latency can cause things to get out of sync. Once you're stationary, it will end up at roughly the distance you've set.

***Note:*** *One weird thing about this is that you won't actually follow your target out of the zone. Once they exit, you'd stop 4 yalms from the zone line (if going by the above example). This may or may not be desirable, and I'll consider ways to change this in the future.*

## Addon Commands

Gambit provides a handful of commands and hotkeys to help you configure the addon from within FFXI. These are broken down into what I call *user commands* (those intended to be used by you) and *system commands* (those intended to be used by the addon itself to manage its own state).

Windower addon commands can be executed directly via the FFXI chat. This is done by typing forward slashes, followed by the addon name (or alias), followed by the actual commands to send. For Gambit, this could look like the following:

```bash
//gambit verbosity -level verbose
```

This would set the addon's chat log output level to `verbose`, which is the highest level recommended for non-developers.

Gambit can be aliased as `gbt`, so the following command is equivalent to the one above:

```bash
//gbt verbosity -level verbose
```

For brevity, all commands listed below will omit the initial `//gambit` or `//gbt` part. Just keep in mind that these *are* required -- they are how Windower determines which addon to route the rest of the command to.



---

**Before we get into the actual commands,** I'll leave a few notes on how to read their description:

- Items in *[square brackets]* represent something that is optional.
- Items in *{curly braces}* represent a placeholder for something you must fill in.
- The vertical bar *|* can be thought of as "OR"; it separates a list of options that you can from.



### User Commands

#### **disable**

Disables automation. Has no effect if automation is already disabled. See also: `enable`, `toggle`

#### **enable**

Enables automation. Has no effect if automation is already enabled. See also: `disable`, `toggle`

#### **reload** [-settings-only] [-actions {action-name}] [-ns {namespace}] [-r] [-verbose]

Forces the addon to reload all settings and actions, resetting the action processing state. This *does not* affect whether automation is enabled.

- `-settings-only`, `-so` - Force the addon to reload settings but not actions. This is primarily useful if you've modified the settings file directly, and want to reload those without resetting the action state.
- `-verbose`, `-v` - Write processed action JSON to the loaded configuration's `.output` folder for this reload only (for example, `gbt r -r -v`). Normal reloads and automatic loads do not write this diagnostic output. Existing output files are left in place. This flag does not change logging verbosity.
- `-actions {action-name}` - Perform a full reload, but load the specified action set rather than the default job-based one. This is completely ignored if you've asked for a settings-only reload.
- `-ns {namespace}` - Load once from this namespace without changing the session selection reported by `gbt ns`. For example, `gbt r -a xp-leveler -ns common`. Cannot be combined with `-settings-only`.
- `-r`, `-reload` - Reload the currently loaded action name and its namespace, including a previous one-time namespace override. An explicit `-ns` takes precedence over the remembered namespace.

A plain `gbt r` returns to job-based actions in the selected namespace. Main settings saves always write to settings/<character>/main.json. Action saves and processed output use the loaded configuration's namespace; settings-only reloads retain that context too. `gbt ns -set` remembers the selection as `default_namespace` in the base `settings/<character>/main.json`; `gbt ns -clear` removes that preference. Startup reads it only from this base character file, ignoring namespace copies. Job changes retain the selection. Every successful settings load reports its job and namespace. Invalid startup selections fall back to base settings with an error, preserving the preference for correction. `reload -ns` overrides only the current load and does not change the saved preference.

#### **eval** <Lua expression or script>

`gbt eval partyCount('is_participant')` evaluates Lua through a fresh, dedicated context's `execute` function and displays its first returned value (including `false` or `nil`). Full scripts are supported, for example `gbt eval local n = partyCount('in_spell_range'); return n`. Each invocation owns a temporary action with its own enumeration, scope, and scheduling state; it does not replace the saved latest context. A player and loaded settings must be available. Evaluation errors use the existing error outputs/log without quarantining the current gambit action; waits use the existing yield-safe guard. Shared settings, variables, and game operations remain shared: intentional script side effects still take effect normally.

Windower supplies parsed command arguments, which are joined with spaces. Preserve Lua string quotes when entering expressions; this command cannot restore quoting or whitespace already removed by Windower's command parser.

#### Target job selectors

Prefix a selector with `~` to exclude its matches from the entire selection. Positive matches are combined first, then all exclusions apply, regardless of list order: `["melee", "~support"]`. Explicit names do not override an exclusion. Exclusions accept jobs, roles, names, and semantic markers such as `me` and `leader`. Use `["*", "~ranged"]` for everyone except ranged; a list containing only exclusions selects nobody. `^` remains local self-exclusion; `~^mages` removes other mages while leaving yourself eligible if a positive selector includes you. Existing job/role expansion remains party-based, including when used with alliance selectors. Randomization and self-first ordering apply to the surviving matches. `partyHasJob` also honors exclusions while retaining its positive job/role/leader and participant requirements.

`leader` selects the current party member marked `is_party_leader`, without requiring known job information. Matching is case-insensitive; `^leader` excludes yourself. If no party member is marked as leader, it produces no matches. It can be combined with other selectors, for example `["^leader", "WHM"]`, with normal deduplication. `partyHasJob('leader')` and `partyHasJob('^leader')` also support this selector, retaining their alive/within-20-yalms participant requirement. Selection follows the context's existing leader fallback rules.

`mobById(id)` resolves a numeric entity ID into a context entity suitable for `hasBuff`, `hasEffectOf`, `useSpell`, and `useAbility`, without changing cursor or enumeration state. It uses the existing context initialization for target flags and tracked buffs (including party/self handling). For example: `hasEffectOf(mobById(id), 'Silence')`. Missing buff information produces no known effect, not proof that an effect is absent. Invalid or unavailable IDs raise an error rather than returning nil and accidentally selecting yourself through optional-target defaults; inside a gambit, the normal error guard quarantines that action. Use `findMob` for normal conditional searches where a missing enemy is expected.

`useSpell(mob, 'Silence')` and `useAbility(mob, 'Provoke')` send outgoing action packets when explicitly passed a mob/context symbol object with numeric `id` and `index`. They refresh the target index before dispatch and do not switch the cursor or broadcast a battle-target change. This does not require GearSwap, and bypasses its normal outgoing-text precast/midcast pipeline; use explicit Gambit equipment commands if needed. Invalid explicit targets are skipped, and incompatible context target flags do not fall back to yourself. Spell completion is checked against the requested spell and target; no matching completion or an interruption reports failure. Ability success indicates submission, as with the existing timed ability path, not server-confirmed effect application. Semantic strings such as `'me'` and `'t'`, and omitted-target behavior, retain their existing command path. To supply a spell/ability with a default target, use `useSpell(nil, spell)` or `useAbility(nil, ability)`: the first parameter is always the target. Normal server restrictions still apply; weapon skill targeting is unchanged. `setTargetCursor` remains available for intentional target/engagement changes.

Prefix a job or role selector with `^` to exclude yourself from that selector: `^WHM`, `^mages`, or `^healers`. Matching remains case-insensitive. Exclusion is local to that entry, so `["me", "^mages"]` still includes you, and an unprefixed overlapping selector can also include you. `partyHasJob('^healers')` checks for another living healer within 20 yalms. The prefix applies to job/role selectors, not arbitrary names or markers.

An explicit empty array (`partyByName({})` or `alliesByName({})`) selects nobody and clears the action's current member enumeration. No arguments, a nil argument, or `'*'` retain unrestricted selection. Use `["*"]` in a JSON target list when everyone is intended.

Context member symbols expose `is_participant`: true when alive and within 20 yalms (inclusive). `partyHasJob` uses this flag. For example, `me.is_party_leader or not party_leader or not party_leader.is_participant` allows an action when you lead, no leader is available, or the leader is dead or out of range.

`partyHasJob` only counts matching members who are alive and within the context's spell range (20 yalms, inclusive). Dead members and members outside that range—or without known range information—do not count. Another living, nearby match can still satisfy the check. This availability check does not change `partyByName` or `alliesByName` selection.

`partyHasJob('WHM', 'SCH')` returns a boolean indicating whether any current party member has either main job, without changing target selection or member enumeration. It also accepts an array, role categories, and plural aliases, all case-insensitively: `partyHasJob({'healers', 'GEO'})`. No arguments, unknown selectors, and unknown member jobs do not match. This includes yourself and trusts with known jobs, but excludes alliance-only members. For an RDM main-healer precondition, use `not partyHasJob('WHM', 'SCH')`; for backup healing, use `partyHasJob('WHM', 'SCH')`.

`mages`, `healers`, `nukers`, and `tanks` are aliases for their singular categories. Both forms are case-insensitive and can be mixed without duplicating targets. `melee`, `ranged`, and `support` retain their collective names.

Job categories are also case-insensitive and can overlap. For example, `partyByName({'me', 'healer', 'nuker'})` selects matching party members without duplicating names. These categories describe known main jobs, not equipment or assigned roles. A category with no matching members selects nobody.

| Selector | Main jobs |
| --- | --- |
| `melee` | WAR, MNK, THF, PLD, DRK, BST, SAM, NIN, DRG, BLU, PUP, DNC, RUN |
| `ranged` | RNG, COR |
| `mage` | WHM, BLM, RDM, BRD, SMN, BLU, SCH, GEO |
| `healer` | WHM, RDM, SCH |
| `nuker` | BLM, RDM, BLU, SCH, GEO |
| `support` | RDM, BRD, COR, SMN, DNC, SCH, GEO |
| `tank` | PLD, NIN, RUN |

Fresh `partyByName` and `alliesByName` enumerations preserve explicit selector order. Each job/role expands alphabetically (case-insensitive); entity ID breaks name ties. Duplicates retain their first position and exclusions apply last. Yourself is not automatically promoted: use `["me", "mages"]` to prefer yourself. Continuing enumerations retain their order. Expression-based party/alliance selection is alphabetical too. Selection is not automatically randomized. To opt in, pass a trailing options table to `partyByName` or `alliesByName`: `partyByName(vars.targets, {randomize = true, self_first = true})`. Both options default to false. Randomization shuffles resolved, filtered members once per fresh enumeration; `self_first` then promotes yourself only if already selected. Continuing an enumeration does not reshuffle. Separate target arguments also work: `partyByName("WHM", "SCH", {randomize = true})`. Empty target arrays still select nobody. Existing actions do not enable these options.

`partyByName` and `alliesByName` accept case-insensitive main-job abbreviations alongside names and semantic markers: for example, `partyByName({'me', 'PLD', 'rdm'})`. Job selectors expand to matching members of the current party using context job information (including trusts and IPC-connected alts). Unknown jobs and unmatched job selectors contribute no targets. Explicit names and markers keep their existing behavior. Job expansion is limited to the party even when using `alliesByName`; explicit alliance names remain supported. Repeated names are deduplicated, and job membership is resolved on each fresh enumeration.

#### Action frequencies

An action may specify `"else": ["log('Condition was false')"]` (or a single command string). When preconditions pass and `when` returns false/nil, this branch executes instead of `commands`. It counts as an action hit and ends the scheduler iteration, using `miss_frequency` for its cooldown. For a nonempty `else`, the miss interval uses the first supplied value in this order: `miss_frequency`, `frequencies`, then explicit `frequency`; otherwise it defaults to one second. An explicit zero removes this safeguard. Preconditions that fail skip both branches. Evaluation errors quarantine the action and never trigger `else`; errors within `else` stop its remaining commands and use the existing error logs.

Missing/nil `else`, empty arrays, and arrays containing only nil or blank strings preserve existing behavior. Both branches share the action's scope and availability time. Values such as `member` or `spell` may not have been selected when `when` fails. Named functions execute `else` once before exiting on a false condition; loading actions also support either branch.

**Scheduling:** once eligible and past its preconditions, an action with executable commands in both branches executes something regardless of its `when` result. Configure both intervals thoughtfully so lower-priority actions can run. Zero intervals can starve lower-priority actions.

`frequencies` supplies a shared default for an action's `frequency` (after execution) and `miss_frequency` (when conditions fail). Either explicit property takes precedence, including zero. For example, `"frequencies": 5, "frequency": 1` means one second after execution and five seconds after a miss. If both individual properties are set, `frequencies` has no effect. Existing interval normalization and the minimum one-second execution interval for actions without a `when` clause still apply.

#### Preconditions

`import` and `imports` are interchangeable: either accepts a single reference string or an array of references. If both are present, `import` entries come first, followed by `imports` entries, preserving order within each array. Preconditions apply to every referenced branch.

Named `slot` placeholders allow common files and imported libraries to insert actions through a top-level `contributions` object. See [Action slots](docs/action-slots.md) for placement, ordering, scopes, and examples.

Executable sections also get automatic `<action-type>-setup`, `<action-type>-priority`, and `<action-type>-fallback` slots: setup and priority precede normal actions, and fallback follows them. For example, contribute to `battle-setup` without adding a placeholder to every job file. These hooks exist even for omitted sections; `imports` and `functions` are excluded. An explicit reference to the same slot retains its placement and suppresses the automatic copy. Slot names control ordering; once-per-battle behavior still requires an appropriate scope and frequency. See [Automatic section slots](docs/action-slots.md#automatic-section-slots) for details.

Any action or import can specify `"precondition": "isBattlefield()"` or an array such as `"precondition": ["isBattlefield()", "player.hpp > 50"]`. Each entry is a Lua expression evaluated in the same context as `when`.

Preconditions accumulate through nested imports: outer conditions run first, followed by inner conditions, the action's own preconditions, and finally its `when`. Every expression must be truthy; false or nil skips the action without evaluating later conditions or commands. Each import branch inherits its own conditions, including imported loading actions and named functions. Variables and macro definitions are still imported normally.

Missing/nil values, empty or whitespace-only strings, empty arrays, and empty string entries add no restriction. They do not clear inherited conditions. Invalid expressions use the action error guard, with the precondition's source included in the error report. Preconditions compile when actions load and are evaluated each time the action's `when` would be checked.

#### Action errors

Errors also append to `.data/action-errors/<Character>-YYYYMMDD.log`, using local dates and timestamps. Each entry includes the action label, source (when available), evaluation stage, error message, and complete failing `when` or command expression, including embedded newlines. Each action is logged once when quarantined. File logging failures are reported without interrupting automation; both existing chat and print outputs remain enabled.

Action evaluation errors are contained per compiled action: a failing `when` or command prints its source and expression once, then quarantines that action until a full action reload (`gbt r -r`). Commands after the failure are skipped; completed side effects are not rolled back. The JSON `disabled` setting is unchanged. A settings-only reload does not clear quarantine. Loading actions and named functions use the same protection. Named functions may also be explicitly retried by adding `-retry` to their usual invocation. Syntax errors are reported during compilation and the invalid action is omitted.

Protected execution uses a coroutine boundary to catch errors while forwarding yields and resume values to the caller, allowing sleeping commands on Lua 5.1 without yielding through `pcall`. Windower's sleep scheduling still requires in-game verification. These guards contain Lua evaluation errors, not native crashes or infinite loops.

#### **namespace** / **ns** [-set {name} | -clear]

Namespaces group activity-specific settings under `settings/.ns/{name}/`, mirroring the normal settings structure. For example, `settings/.ns/abyssea/Carbonite/actions/pld.json` supplies Carbonite's PLD actions, while `settings/.ns/abyssea/actions/lib/` holds shared library gambits.

- `gbt ns` reports the current namespace (or global).
- `gbt ns -list` lists namespaces marked by a `.nsconfig` file, alphabetically, including nested namespaces. Organizational folders without that file are traversed but not listed. Names use underscore aliases where unambiguous; reserved `actions` and `players` folders are skipped. A namespace requires `.nsconfig` to be selected or inherited.
- `gbt ns -set abyssea` selects an existing namespace and reloads settings and job-based actions. If its folder or `.nsconfig` is missing, the command warns with a `-force` hint and leaves selection and files unchanged. Add `-force` to create it: this initializes `actions`, `actions/lib`, and a missing `.nsconfig` containing `{}`. If it already exists, `-force` warns and continues, preserving existing configuration. Character folders are created only when needed for a write.
- `gbt ns -clear` returns to global settings and fully reloads.
- `gbt r` and other settings reloads retain the current namespace. Reloading the addon resets it to global. Selection is local to each character and is never saved to disk.

Lookup order is namespace character, namespace common, base character, base common, then shipped defaults where applicable. This applies to `main.json`, action entry points, explicit library imports, and default actions. The first matching file wins; namespace files do not merge with lower-priority versions. Automatic common imports are the additive exception described below. Existing action-import variable merging is unchanged.

Explicit `$(PlayerLib)` and `$(SettingsLib)` imports search their respective scope through the namespace inheritance chain and then base settings; `$(GlobalLib)` references shipped libraries directly. Namespace character files live under `players/<character>/`: `main.json`, `actions/`, `actions/lib/`, and `.output/`. Shared namespace files remain at the root and under `actions/`. Main settings saves always update `settings/<character>/main.json`, so changed preferences are shared across namespaces. Namespace-specific `main.json` files are still used when loading and can override the base file; namespace save routing is retained but disabled. Unchanged settings do not trigger a write.

Names may contain letters, numbers, underscores, and hyphens, with forward slashes separating folders. For example, `gbt ns -set ambuscade/dragon` selects `settings/.ns/ambuscade/dragon/`. These folders are purely organizational: the parent `ambuscade` namespace is not searched as an additional fallback. Leading, trailing, or repeated slashes and `.` or `..` segments are not allowed. A namespace must have its folder and `.nsconfig` before loading; initialize it with `gbt ns -set <name> -force`. Missing ordinary settings files still fall back to base settings.

Common files are automatically included before explicit imports, from lowest to highest priority: global library, base settings library, base player library, namespace settings library, then namespace player library. Within each library, the order is `common/common.json`, `common/{main_job}.json`, then `common.json` directly under the library folder. All existing files are included; namespace common files supplement rather than hide base common files. Missing files are silently skipped. Imports are processed backward, so more specific common files supply variable and macro defaults first; the main action file and explicit imports retain their existing precedence. Explicit imports, including imports inside common files, still use first-match namespace lookup.

#### **show**

Displays all of your configured settings in the chat log.

#### **toggle**

Toggle automation on or off. This is identical to running `enable` when disabled, or `disable` when enabled. Se also: `disable`, `enable`

> The `toggle` command is bound to the hotkey **Shift+Alt+G**

#### **verbosity -level {normal|verbose|comment|debug|trace}**

Controls the chat log output level. Gambit will only show output that is at or below the configured level. Valid values for *verbosity* are as follows:

- ```normal``` - Minimal output. You don't want to see much at all.
- ```verbose``` - More detailed output, helping you track what the addon is doing. This is the default, and is generally recommended.
- `comment` - This is similar to verbose, but it will include things that could be considered more informational and noisy.
- ```debug``` - This starts to get objectively noisy. This mode is mostly helpful if you're an addon developer, or if you're having trouble understanding what your actions are doing. This can be like drinking from a fire hose.
- ```trace``` - This is the highest level of output. Think of it as similar to `debug`, but every triggered action is written to the chat. This can be like drinking from a fire hydrant. 

## Settings

TBD

### Prioritized variable defaults

Variable definitions have three load-time priority levels: `!name` (high), `name` (ordinary), and `^name` (fallback default). Higher priority wins regardless of load order; conflicting definitions at the same priority retain the first loaded value. Prefixes are removed from runtime names.

Shipped variable defaults under `actions/lib`, `actions/standard`, and `actions/defaults` use `^` on their top-level variable names. Ordinary character and namespace configuration can override these defaults, including nested fields, regardless of import order. User files under `settings/` retain their explicitly chosen priorities.

For example, a reusable library can declare `"^allow_cleave": false`, and an imported user configuration can set `"allow_cleave": true` without depending on which file loads first. `"^keep_silence": {"targets": ["bt"], "spells": ["Silence"]}` gives the supplied descendants fallback priority while still allowing normal recursive merging. Explicit nested prefixes override inherited priority, so `"^settings": {"!enabled": true}` supplies a high-priority `enabled` value.

Arrays remain whole values. A higher-priority definition replaces a lower-priority array; equally prioritized arrays retain the first loaded list. Clearing markers honor priority too: a `^` clearing marker cannot erase ordinary or high-priority values. Ordinary unprefixed clearing markers retain their pre-existing special behavior of clearing earlier ordinary definitions; this is an explicit clearing operation, rather than a normal conflicting assignment.

`getOriginalVar(name)` reads the variable value from the most recent action load/compilation, before loading actions execute. It supports the same dotted paths, optional `vars.` prefix, numeric array indexes, and computed `$length`/`$type` queries as `getVar`. Tables are returned as fresh deep copies; missing values return nil.

`resetVar(name)` restores that loaded value through `setVar`, returning the assigned value. For example, `resetVar('keep_silence.targets')` restores the loaded target list. Resetting an object restores its entire subtree and removes runtime-added children. Resetting an absent variable assigns nil. Existing setter restrictions still apply: computed fields cannot be assigned, and nested assignments cannot traverse a scalar parent. Runtime assignments remain unrestricted by load-time priority. A settings-only reload that does not recompile actions leaves the snapshot unchanged.

Prefix a key in an action file's `vars` with `!` to give its supplied values priority during loading:

```json
"vars": {
  "!allow_cleave": true,
  "!keep_silence": {
    "targets": ["bt", "Enemy Name"]
  }
}
```

Actions still read `vars.allow_cleave` and `vars.keep_silence.targets`. The prefix is removed during loading. Marked values beat ordinary definitions regardless of import order, including ordinary values in the main gambit file. Two conflicting marked values keep the first loaded definition and produce a warning identifying the variable and source. Within a single object, marked keys are applied after ordinary keys.

Objects continue merging recursively: marking `keep_silence` prioritizes its supplied `targets`, while other imports can still provide `spells` and other missing properties. Alternatively, mark only a nested key, such as `"keep_silence": {"!targets": ["bt"]}`. Arrays are whole values, not combined lists. An incoming scalar, array, or clearing marker cannot discard an object containing an earlier prioritized descendant.

Use `"!name": "$object.null"` for prioritized clearing to nil, or `"!name": "$array.empty"` (also `$object.empty` / `$table.empty`) for a protected empty table. Ordinary JSON `null` is removed by the parser and does not establish priority. An empty JSON object supplies no child values; use an explicit empty marker when clearing is intended.

Priority metadata exists only during loading and is discarded afterward. Runtime assignments, including `setVar`, remain unrestricted. Ordinary definitions retain the existing merge rules. Reserve priority markers for configuration overrides rather than reusable library defaults.

`mobByIndex(index)` provides the same context entity through an entity index. Both helpers leave targeting and enumeration unchanged.

The finders `findMob`, `findMobWhere`, and `findMobs` also accept the case-insensitive selector `"bt"`, alone or in a list such as `"targets": ["bt", "Enemy Name"]`. It resolves to the current battle target's ID on each search and matches nothing when that target is unavailable. All existing enemy, range, engagement, and predicate filters still apply; `bt` receives no special priority over nearer qualifying enemies.

`findMobWhere(identifier, expression, distance, withAggro)` returns the nearest matching enemy whose Lua predicate is truthy, or nil if none matches. It accepts the same names/IDs and defaults as `findMob`. For example: `findMobWhere({'Boss A', 'Boss B'}, "not hasEffectOf(mob, 'Silence')", 20, true)`. Within the predicate, `mob` is the candidate with tracked buffs; its fields are also available directly (for example, `distance < 15`, in yalms), with other names resolved from the action context. Pass `mob` explicitly to target-taking helpers. Unknown buffs mean no known effect, not proof of absence. Compilation is cached; predicate errors propagate to the action error guard. Predicates should be free of side effects: evaluation order is unspecified and candidates farther than an accepted match may be skipped. Only the successful result is assigned to the action context's `mob`, as with `findMob`.

`findMob(identifier, distance, withAggro)` accepts a name, entity ID, or array of names/IDs and returns the nearest matching enemy. Names are case-insensitive; numeric selectors now mean IDs, not indexes. For an index, use `findMob(mobByIndex(index).id, 20)`. `findMobs` retains its optional leading numeric search radius and accepts names/IDs afterward, including arrays: `findMobs(20, {123456, 'Enemy Name'})`. Its existing array-or-nil return behavior is unchanged.
Namespace path segments `actions` and `players` are reserved for namespace contents. Windows device names (`CON`, `NUL`, `AUX`, `PRN`, `COM1`–`COM9`, and `LPT1`–`LPT9`) are also rejected. These checks are case-insensitive and apply to every segment, including names in `inherits_from`. Names such as `actions-test`, `common`, and `lib` remain allowed.

# Namespace inheritance

Multi-stage weapon-skill participant lists, stage overrides, and exclusion keys support party target selectors as well as character names. See [Multi-stage participants](docs/multi-stage.md) for ordering, stage rules, roster refresh, and coordination caveats.

Sortie sector configurations inherit shared behavior from `sortie`. Select `gbt ns -set sortie/a` for Sector A's repeated WAR/PLD two-part Light sequence and GEO's low-HP finishing nukes. The parent keeps common buffs, burst support, and elemental/Umbril mitigation; it no longer supplies that sector's chain or finishing thresholds. Reusable WS libraries remain in the parent for future sector namespaces. Bosses continue to use the separate `sortie/boss` chain.

`sortie/leshonn` also inherits `sortie/boss`. Load it before fighting Sector B's boss after obtaining Shard B and preferably Metal B. It enables all-out melee restricted to Savage Blade, with cleaving disabled; all melee must equip a main-hand sword and have Savage Blade available. Planned chain contributions, bursts, and the priority/normal debuff slots are disabled. On each nuker, select the visible aura with `gbt eval vars.leshonn.mode = 'wind'` (Blizzard) or `'thunder'` (Stone), updating it when the aura changes. The default `'unknown'` prevents nuking; visual aura detection is not automated. Wind/Thunder damage and Light/Fragmentation chains can heal this boss. WHM prepares Baraera and Barsilencera through inherited idle actions. Bring Echo Drops and review Leshonn's buff-stealing and debuff-copying mechanics before engaging.

The Sortie configurations use two explicit chains: `sortie` inherits `base` for ordinary objectives, while `sortie/ghatjot` inherits `sortie/boss`, then `boss`, then `base`. The shared Sortie boss layer supplies casting contributions and disables free offensive weapon skills; individual bosses supply their chains and mechanics. The boss chain does not inherit the ordinary Sortie two-part chain. Select Ghatjot with `gbt ns -set sortie/ghatjot`.

Use `!description` instead of `description` to hide descriptions from all ancestors above that namespace. It accepts the same string or array of strings. Output starts at the closest `!description` in the selected namespace's inheritance chain and continues down to the selected namespace. An empty array suppresses ancestor descriptions without adding text. If both keys are present, `!description` takes precedence. Settings inheritance is unaffected.

An optional `description` in `.nsconfig` is printed to chat after settings load successfully. Use a string or an array of strings for separate lines, for example `{"description": ["Recommended jobs: PLD, WHM, BLM", "Enable magic bursts."]}`. Descriptions appear in inheritance order, oldest ancestor first and selected namespace last. Each block is labeled "Description from namespace:" to identify its source. Namespaces without descriptions or with empty description arrays are skipped.

Use `gbt ns -set xp -force -parent base` to create `xp`, initialize a missing `xp/.nsconfig` with `{"inherits_from":"base"}`, and switch to it. The parent must exist, must not explicitly set `inheritable: false`, and must have a valid inheritance chain. Validation happens before namespace folders or configuration are created. An existing `.nsconfig` is preserved: it must already name the requested parent, otherwise the command reports a conflict (including when it contains only `{}`). The child is inheritable by default; no explicit flag is written. `-force` and `-parent` may appear in either order.

A namespace may declare one parent in `settings/.ns/<namespace>/.nsconfig`:

```json
{ "inherits_from": "bcnm/single" }
```

Namespaces with an existing `.nsconfig` are inheritable by default, including those containing only `{}`. Missing `.nsconfig` files are rejected; `-force` initializes only the selected namespace, so missing parents must be initialized separately. Set `{"inheritable": false}` to prevent other namespaces from inheriting one; direct selection remains allowed. This flag is local to each namespace, and every ancestor in an inheritance chain must permit inheritance. Explicit `true` remains supported; other non-boolean values are rejected. A missing `inherits_from` still means no parent is selected automatically. Parent names are relative to `settings/.ns`, not the current namespace folder.

Ordinary settings, action files, and imports search the active namespace, then its parent chain, then the existing global fallbacks. Imports inside inherited files use the active namespace's search chain too. Automatic common files load additively from base to derived priority, preserving character-over-shared precedence within each namespace. Explicit variable priorities (`!` and `^`) still apply. This is file fallback, not automatic merging of ordinary job or main configuration files.

Saving settings in a namespace writes to an existing main configuration in that active namespace, or creates a character override there; it does not modify an inherited or global file. Cycles, missing parents, and parents explicitly declaring `inheritable: false` fail with an error. Only a single string is supported for `inherits_from`; arrays are rejected. Internally, lookups use a resolved precedence list to allow future multiple-inheritance support.
