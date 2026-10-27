# Gambit command reference

Panel controls: `gbt panel`, `gbt panel show`, `gbt panel hide`,
`gbt panel reset-position`, and `gbt panel reload`. Tracking controls:
`gbt panel tracking`, `gbt panel tracking -list`, and
`gbt panel tracking -set <name>`. Panel settings persist per character in the
global `main.json`; see [status panel configuration](status-panel.md).

`gbt slots` lists the current configuration's contribution slots grouped by action
type, with sections sorted alphabetically and slots in their placement order.
Repeated slots appear once at their first occurrence; fallback alternatives retain
their declared order. It includes automatic
section hooks, empty slots, and all fallback alternatives, even when an alternative
was not selected. Reload the configuration after adding or removing slots.
Use `gbt slots -t <action-type>` to show only one section, for example
`gbt slots -t battle`. The action type is case-insensitive.

Use `//gbt` in the FFXI chat input, or `gbt` in the Windower console and scripts. `gambit` is an equivalent addon prefix. Examples below use chat syntax.

`<value>` means a required value; `[option]` means optional. Do not type the angle or square brackets. Quote names containing spaces. Use lowercase command and option names as shown.

This reference describes the commands registered in [commands.lua](../lib/commands.lua). Lua helpers used inside JSON actions are a separate interface; see [functions](functions.md) and [actions](actions.md). Available named functions depend on your loaded gambit and its imports.

## Quick start

```text
//gbt status
//gbt r -a rdm
//gbt enable
//gbt disable
//gbt r -r
//gbt fn -list
```

| Task | Command |
| --- | --- |
| Show current gambit, automation status, and targeting strategy | `//gbt status` |
| Enable / disable all automation | `//gbt enable` / `//gbt disable` |
| Toggle automation | `//gbt toggle` |
| Reload the currently loaded gambit | `//gbt r -r` |
| Load a particular gambit | `//gbt r -a <name>` |
| Load from a namespace | `//gbt r -a <name> -ns <namespace>` |
| Toggle action execution separately | `//gbt actions -toggle` |
| Inspect a variable | `//gbt varget <name>` |
| Evaluate a Lua expression | `//gbt eval <expression>` |

## Automation and actions

| Command | Behavior |
| --- | --- |
| `enable [-quiet]` | Enable automation and reset its current target/timing. |
| `disable [-quiet]` | Disable automation and clear the current target. |
| `toggle` | Switch between enabled and disabled. |
| `status` | Report the loaded gambit, automation state, and strategy. |
| `actions` | Report whether action execution is enabled. |
| `actions -on` or `actions -enable` | Enable action execution. |
| `actions -off` | Disable action execution without disabling the whole automation system. |
| `actions -toggle` | Toggle action execution. |
| `actions -load <name>` | Load and compile a named action set. Prefer `reload -a` when also reloading settings or selecting a namespace. |
| `actions -save-default [-force]` | Write default actions for your character/job. `-force` allows overwriting. |
| `actions -save-local [name] [-force]` | Save a local action file, using the loaded action name when omitted. `-force` allows overwriting. |

Both `enable` and `disable` cancel an active smart-movement job. `-quiet` suppresses redundant status messages when the state is already correct.

## Reloading and namespaces

Namespaces may declare `"abstract": true` in `.nsconfig` to indicate they are
intended as inheritance bases. `ns -list` shows them in gray with `(abstract)`.
Direct loading still succeeds but prints a warning. Abstract ancestors do not
make their children abstract; the flag applies only to the namespace declaring
it. Omitted or `false` means concrete; non-boolean values are rejected.

Namespaces can be inherited by default. Set `"inheritable": false` in a namespace's `.nsconfig` to opt out; this does not prevent selecting that namespace directly. An existing `.nsconfig` containing `{}` permits inheritance. Missing folders or `.nsconfig` files are rejected for both selected namespaces and inherited parents; initialize them explicitly with `gbt ns -set <name> -force`.

`reload` has the alias `r`. It reloads settings/actions, not the addon itself.

| Option | Alias | Behavior |
| --- | --- | --- |
| `-actions <name>` | `-a` | Choose an action set. |
| `-reload` | `-r` | Reload the currently loaded action set, retaining its loaded namespace unless `-ns` overrides it. |
| `-settings-only` | `-so` | Reload settings while bypassing action reload. |
| `-ns <namespace>` | — | Select a namespace for this load. Cannot be combined with `-settings-only`. |
| `-verbose` | `-v` | Write processed JSON debugging output to `.output` folders for this reload. Off by default. |

Without `-a` or `-r`, a normal full reload selects actions for your current job. `-r` takes precedence over `-a` when a current action name exists. Reload's `-v` is independent of the logging verbosity setting.

```text
//gbt r
//gbt r -a rdm -ns bcnm/cleave
//gbt r -r -v
//gbt r -so
```

`namespace` has the alias `ns`:

| Command | Behavior |
| --- | --- |
| `namespace` | Show the selected namespace, or global mode. |
| `namespace -list` | List namespaces containing `.nsconfig`, alphabetically by full name (case-insensitive). Searches nested folders under the active namespace root, skipping reserved content folders. Underscore aliases are shortened when unambiguous. Does not change selection or reload settings. |
| `namespace -v` | Replay the loaded namespace's description sequence, respecting `!description`, without reloading settings. Outputs nothing when no descriptions are available. |
| `namespace -set <name> [-force] [-parent <namespace>]` | Select an existing namespace and perform a full settings reload for the current job. Missing folders or `.nsconfig` files warn with an initialization hint and leave selection unchanged unless `-force` is supplied. `-force` ensures the folder and `.nsconfig` exist; if it already exists, it warns and continues. `-parent` initializes a missing `.nsconfig` with `inherits_from` after validating the parent chain. Existing configuration must already name that parent; otherwise selection is rejected without changing it. |
| `namespace -clear` | Clear namespace selection and perform a full settings reload. |

`namespace -set` and `namespace -clear` remember the selection in `settings/<character>/main.json` as `default_namespace`, after a successful reload. Startup reads this field only from that base character file; namespace copies are ignored. Job changes retain the selection, and each settings load reports the active namespace. Invalid startup selections report an error and fall back to base settings without deleting the saved preference. `reload -ns` remains a temporary override.

## Target selection

`strategy` (alias `strat`) displays the current strategy with no argument, or sets and saves one:

```text
//gbt strategy manual
//gbt strategy leader
```

| Strategy | Intended behavior |
| --- | --- |
| `manual` | You choose targets by engaging manually. |
| `nearest` | Prefer the nearest aggroing mob. |
| `maxhp` | Prefer the aggroing mob with the most HP. |
| `minhp` | Prefer the aggroing mob with the least HP. |
| `aggressor` | Proactively acquire enemies rather than waiting for aggro. |
| `leader` | Follow the party leader's target, with an aggro fallback. |
| `puller` | Proactive targeting with additional restrictions on unclaimed mobs engaged with others. |

Targeting settings and eligibility checks still apply.

`target` (alias `ta`) changes your selected target:

```text
//gbt target Enemy Name
//gbt target -name "Enemy Name"
//gbt target -id 123456
//gbt target -index 123
```

`-n` aliases `-name`. IDs and indexes are distinct; this command explicitly supports both. Named targeting uses the context's `findByName` helper, not `findMobWhere`.

### Ignore list

| Command | Behavior |
| --- | --- |
| `ignore` or `ignore -t` | Add the current enemy by index and current zone. |
| `ignore -name "Enemy Name" [-zone]` | Add a name rule, optionally limited to this zone. |
| `ignore -t -name` | Create a name rule using the current target's name. |
| `ignore-list -show` | Display the list. Alias: `il`. |
| `ignore-list -remove <entry>` | Remove an entry by its list position. |
| `ignore-list -downgrade <entry>` | Toggle an entry's lower-priority behavior. Alias: `-down`. |

Options for `ignore`: `-target` aliases `-t`; `-note "text"` stores a note; `-always` ignores even aggroing enemies; `-downgrade` (or `-dg`) lowers targeting priority instead of completely excluding the mob. Ordinary ignore rules can still allow aggroing enemies. Changes are saved.

## Movement and interaction

| Command | Behavior |
| --- | --- |
| `follow -target [-distance <yalms>]` | Follow the current selected target. Aliases: `-t`, `-d`. Default distance comes from settings. |
| `follow -cancel` | Cancel smart movement. Alias: `-c`. |
| `follow -toggle [-d <yalms>]` | Cancel the current movement job, or start following the selected target. |
| `move -x <number> -y <number>` | Move to coordinates. If only one coordinate is supplied, retain your current value for the other. |
| `run -start` / `run -stop` | Start or stop running. |
| `walkmode [-on or -off]` | Set walk mode; no option toggles it. |
| `align [-target <name>] [-distance <yalms>] [-angle <degrees>] [-wait <seconds>]` | Align relative to the named or currently selected target. Defaults: distance 1, wait 10 seconds. Aliases: `-t`, `-d`, `-a`, `-w`. |
| `align -cancel` | Cancel smart movement. Alias: `-c`. |
| `touch -t` | Interact with the selected entity. Also accepts `-name <name>` (`-n`) or `-id <id>`. |
| `tap -t` | Interact, then press Escape twice to leave dialog/clear selection. Also accepts `-name <name>` or `-id <id>`. |
| `sendkey <key> [key ...]` | Send a sequence of Windower key names. Alias: `sk`. |

`touch` and `tap` operate at close range (the helpers default to 6 yalms); they do not automatically approach distant targets. Both accept `-all` to forward the interaction through the external Send addon to all characters. Without a target option, they do nothing.

`align -angle` also accepts `frontside`, `backside`, `left`, `right`, `side`, or a range such as `"180+/-30"` / `"150-210"`. Flexible ranges permit alternate destinations after movement timeouts. See [flexible alignment](functions.md#flexible-alignment). The command's default `-wait` remains 10 seconds, shared across attempts.

```text
//gbt follow -t -d 3
//gbt follow -c
//gbt move -x 12.5 -y -40
//gbt touch -name "Home Point"
//gbt sendkey escape escape
```

## Named functions

`function`, `func`, and `fn` are equivalent. These run functions registered by loaded gambit JSON files.

```text
//gbt fn -list
//gbt fn -name sneak_self
//gbt fn -name example amount:3 enabled:true
//gbt fn -name example -stop
//gbt fn -name example -retry
```

| Option | Behavior |
| --- | --- |
| `-list`, `-l` | List registered function names and descriptions. Also the default when no name is supplied. |
| `-name <name>`, `-n` | Select a function. |
| `key:value` | Supply a parameter exposed as `params.key`. Numbers and `true`/`false` are converted; other values remain strings. Quote the whole argument if it contains spaces. |
| `-silent` | Suppress routine execution messages. |
| `-stop`, `-cancel`, `-exit` | Request that the named running function exit. |
| `-retry` | Clear a non-running function's runtime-error quarantine and try again. Reload also clears quarantine. |
| `-send <recipient>` | Forward the function command through the external Send addon. |
| `-max <count>` | Intended iteration limit; currently passed through as text without numeric conversion. Prefer the function's JSON `max_iterations` property until this is corrected. |

Functions can repeat until their conditions fail or they explicitly stop. Reloading settings causes running functions to exit. Their JSON definitions can configure frequency, iteration limits, and re-entry behavior.

On load, Gambit also registers these Windower shortcuts:

| Shortcut | Expands to |
| --- | --- |
| `gbtfn <name>` | `gbt func -n <name>` |
| `gbtta <name>` | `gbt target -n <name>` |
| `varget <name>` | `gbt varget <name>` |
| `varset <name> <value>` | `gbt varset <name> <value>` |

## Variables and Lua evaluation

| Command | Behavior |
| --- | --- |
| `varget <name>` | Read a variable from the latest available action context. |
| `varset <name> <value>` | Set a variable. Converts numbers, `true`, `false`, and `nil`; other values are strings. Always supply a value. |
| `eval <Lua expression or script>` | Execute the rest of the command using a fresh temporary action context and print the first returned value. |

```text
//gbt varget keep_silence.targets
//gbt varset example_enabled true
//gbt eval 2 + 5
//gbt eval partyHasJob('WHM', 'SCH')
//gbt eval vars.keep_silence.targets
```

`eval` supports normal context helpers and guarded error reporting. It is not read-only: calling a movement, casting, or variable-setting helper performs that operation. Expressions return their value; scripts need an explicit `return` to produce a result. Windower command parsing still applies, so avoid assuming a semicolon will reach Lua unchanged.

## Configuration

`show` prints scalar settings. `config` accepts multiple options, for example:

```text
//gbt config -distance 20 -chasetime 15
//gbt config -cloudpanel on
//gbt verbosity -level normal
```

| `config` option | Aliases | Behavior / accepted range |
| --- | --- | --- |
| `-distance <number>` | `-d` | Maximum targeting distance; clamped to 3–50. |
| `-distancez <number>` | `-z` | Maximum vertical targeting distance; clamped to 1–50. |
| `-strategy <name>` | `-strat` | Set targeting strategy. |
| `-followd <number>` | `-fd` | Default follow-command distance; clamped to 0.25–10. |
| `-follow-offset <number>` | `-foff` | Nonnegative horizontal follow offset. |
| `-chasetime <seconds>` | `-ct` | Maximum chase time; clamped to 5–60. |
| `-skillchaindelay <seconds>` | `-scdelay`, `-scd` | Skillchain delay; requires a positive input and is capped by Gambit's maximum skillchain time. |
| `-targetingduration <seconds>` | `-td` | Targeting duration; clamped to 1–20. |
| `-cloudpanel on/off` | `-cp` | Enable or disable the cloud panel. |
| `-rawdistance on/off` | `-rd` | Toggle raw-distance mode. This option alone does not trigger a settings save. |
| `-debugging on/off` | — | Toggle additional debugging details. |
| `-stt on/off` | — | Toggle slower target transitions. |
| `-spt on/off` | — | Toggle skipping packet targeting. |
| `-pretarget on/off` | — | Toggle pre-targeting. |
| `-partytarget on/off` | `-pt` | Stores a setting currently marked unused by the implementation. |
| `-tabs` | — | Deprecated; reports that the setting is no longer used. |

Configuration changes normally save automatically. The raw-distance exception is noted above.

`verbosity` displays the current log level; `verbosity -level <level>` changes and saves it. Levels: `normal` (0), `verbose` (1), `comment` (2), `debug` (3), `trace` (4).

## Inspection and diagnostics

| Command | Alias | Behavior |
| --- | --- | --- |
| `iteminfo [-verbose]` | `ii`; option `-v` | Inventory occupancy and gil; verbose adds stored currency information and other bags/wardrobes. |
| `jobinfo [-name <character>]` | `ji`; option `-n` | Show your job information, or another character's cached IPC job information. |
| `jobinfo -send` | — | Broadcast your job information to other local Gambit instances. |
| `jobinfo -all` | `ji -all` | List all cached characters and yourself alphabetically, using live job information for yourself. |
| `wsinfo [-name <character>]` | option `-n` | Show a character heading followed by an indented list of weapon-skill names; defaults to yourself, refreshed from live abilities. |
| `wsinfo -all` | — | Show every cached character's weapon-skill names, with characters ordered alphabetically. |
| `wsinfo -send` | — | Broadcast your current weapon-skill capability IDs. |
| `wsinfo -sync` | — | Ask every local Gambit instance to broadcast its weapon-skill capabilities, including yourself. |
| `jobinfo -sync` | `ji -sync` | Ask all local Gambit instances to broadcast their job information, including your own. Also runs automatically on addon load and login. |
| `jobset <character> <job-spec>` | — | Set and broadcast a character's job information. Examples: `WHM`, `WHM/RDM`, `WHM75`, `WHM75/BLM37`. Omitted levels default to 1. |

| `targetinfo [-target <symbol>] [-save]` | `ti`; option `-t` | Show entity details. Defaults to `t`; examples include `me`, `p1`, and `player`. `-save` writes JSON under `data/`. |
| `rollinfo` | `ri` | Show tracked Corsair rolls; the latest roll is marked with `*`. |
| `buffs` | — | List your active buffs and their IDs. |
| `mobbuffs [-limit bt/trust/mob]` | `mb`; option `-l` | Show tracked effects and their sources, optionally filtered to battle target, trusts, or enemies. This is observed effect history, not a complete server buff query. |
| `equipment -slot <slot> [-verbose]` | Options `-s`, `-v` | Show the equipped item and augments in a slot; verbose adds bag and item IDs. |
| `cancelbuff -name <buff>` | `cb` | Queue cancellation of a buff. Option aliases: `-names`, `-buff`, `-buffs`, `-n`, `-b`. Always supply one of these options. |
| `colortest [number]` | — | Display the chat color palette, optionally printing a selected color first. |
| `exp` | — | Development diagnostic: prints language and a Refresh spell lookup. It does not manage experience points. |

Manual job records are session-only and use the same cache as live IPC updates.
Names are normalized (for example, `sTERIS` becomes `Steris`), and job abbreviations
are case-insensitive. Each update replaces the whole record; omitting a subjob
removes the previously recorded subjob. Subsequent live IPC broadcasts overwrite
manual entries normally. Your own context still uses live player information.
There is no clear option. Existing inspection (`jobinfo -n Steris`) and `-send`
remain available; level-up-triggered broadcasts are not introduced by this command.
| `face` | — | Registered placeholder; prints “Not implemented.” |
| `showfollow` | — | Registered placeholder; prints “Not implemented.” |

```text
//gbt ti -t me
//gbt mb -l bt
//gbt equipment -s main -v
//gbt cb -n "Sneak"
```

There is currently no registered `gbt help` command. This document covers the built-in command handlers; named functions and their parameters are defined by the loaded JSON files.
