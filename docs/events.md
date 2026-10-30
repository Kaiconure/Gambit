# Events: user guide

Gambit events react to actions you initiate and to status or zone changes. They
run even when normal Gambit automation is disabled. Manual actions and actions
issued by Gambit use the same event rules.

For gear configuration without writing your own rules, start with
[Using the stock events](stock-events.md). This guide explains the event interface
and serves as a reference when writing or extending rules.

## Quick reference

| I want to… | Use |
|---|---|
| Configure the shipped gear rules | A character/job `.vars.json` file; see the [stock guide](stock-events.md) |
| Check the active rule and variable files | `//gbt events status` |
| Reload event JSON only | `//gbt events reload` |
| See the fully processed configuration | `//gbt events reload -v` |
| Load changed Lua implementation code | `//lua reload Gambit` |
| React to a spell or ability | `pre`, `mid`, and `post` arrays |
| React to engagement, disengagement, or death | `statuses.<category>.enter` / `.leave` |
| React to zoning | `zones.enter` / `.leave` |
| Initialize variables once per load | `loading.actions` |
| Reuse complete rule modules | Top-level `imports` |
| Extend stock behavior without replacing it | Top-level `contributions`, including in `.vars.json` files |
| Stop later rules in this phase | `"stop": true` or `stopEvent()` |
| Cancel an outgoing action in `pre` | `cancelEvent('reason')` or `stopEvent(true)` |

## Where files go and which one wins

Rule files contain event sections. Variable files configure those rules and may
also contribute rules at named slots.

| Purpose | Global settings path |
|---|---|
| Shared job configuration | `settings/events/geo.vars.json` |
| Character job configuration | `settings/Aidelle/events/geo.vars.json` |
| Character rule override | `settings/Aidelle/events/geo.json` |
| Shipped rule defaults | `events/geo.json`, or `events/common.json` |

Namespace equivalents are
`settings/_ns/<namespace>/events/` and
`settings/_ns/<namespace>/players/<character>/events/`.

**Exactly one rule entry point is selected.** The search order is:

1. Active namespace, then inherited namespaces from closest to furthest.
2. Global settings.
3. The addon's top-level `events/` directory.

Within each settings scope, character directories precede shared directories.
Within a directory, exact main-job files precede matching positive group files,
then matching inverse groups, then `common.json`. Job filenames are lowercase.
Examples include `(mages).json`, `(healers).json`, and `(~melee).json`.

Smaller matching job groups win; inverse groups use their complement's size.
Equal sizes use alphabetical order. `(leader)` keeps its established alphabetical
position among matching positive selectors. Scope/location precedence comes
before filename specificity. Event entry points do not use `(all).json` or
important `(!group)` selectors.

An empty matching rule file deliberately overrides all more distant defaults.
To extend defaults instead, import them or use contributions. All matching
`.vars.json` files are layered independently of the selected entry point.

## Writing rules

Every phase is an ordered array. A rule can have `when`, `commands`, `stop`,
`id`, `disabled`, and `comment`.

```json
{
  "spells": {
    "pre": [
      {
        "when": ["event.name == 'Dispel'"],
        "stop": true,
        "id": "leave-dispel-alone"
      },
      {
        "when": ["event.curing"],
        "commands": ["log('Casting', event.name)"],
        "id": "announce-cures"
      }
    ]
  }
}
```

- `when` accepts a Lua expression string or an array. Arrays mean AND and
  short-circuit in order. Omitted or empty conditions match unconditionally.
- `commands` accepts a string or array of Lua expressions/scripts, executed
  in order. Commands are optional; a matching stop-only rule is valid.
- All matching rules run unless processing is stopped. A false/nil command
  return does not skip subsequent commands or rules.
- Each string in a rule's `commands` array is its own function. Shared context
  fields and `vars` are available throughout; local variables do not cross
  command strings. Use a single script string for shared locals or a loop.
- `comment` accepts any JSON value. It is discarded; comment-only entries do
  nothing and never execute Lua.
- Rules must finish synchronously. Do not use waits, sleeps, or yielding helpers.

### Stopping versus cancelling

| Mechanism | Effect |
|---|---|
| `"stop": true` | On a matching successful rule, finish its commands, then skip later rules in this phase |
| `stopEvent()` / `stopEvent(false)` | Conditionally request the same phase stop; remaining commands in the current rule still execute |
| `cancelEvent('reason')` | In action `pre` only, cancel dispatch; later pre rules still get a chance to run |
| `stopEvent(true)` | In action `pre` only, cancel dispatch and stop later pre rules |

For example, `"commands": ["me.hpp < 20 and stopEvent(true)"]` makes cancellation
conditional. A stopped phase does not suppress later lifecycle phases.
Cancellation still generates local `post` cleanup. Status, zone, and loading
handlers cannot cancel their already-observed event.

### Rule IDs

IDs identify definitions at load time, not first-match groups. Within one final
section/phase, a later same-ID rule removes the earlier definition and takes its
later position. `{"id": "some-rule", "disabled": true}` removes it without
adding executable work. IDs can replace imported or contributed rules.

## Event types and timing

| Configuration | `event.kind` | Phases |
|---|---|---|
| `spells` | `spell` | `pre`, `mid`, `post` |
| `job_abilities` | `job_ability` | `pre`, `mid`, `post` |
| `weapon_skills` | `weapon_skill` | `pre`, `mid`, `post` |
| `pet_abilities` | `pet_ability` | `pre`, observed `mid`, `post` |
| `statuses.battle`, `.idle`, `.death` | `status` | `enter`, `leave` |
| `zones` | `zone` | `enter`, `leave` |
| `loading` | `loading` | `actions` |

### Spells, job abilities, and weapon skills

- **Pre:** before releasing the outgoing action. Equipment requests are batched
  and acknowledged before dispatch. Use this for Fast Cast, weapon-skill gear,
  job-ability enhancement gear, and essential gear for very fast/instant spells.
- **Mid:** immediately after dispatch. For spells, this is where result-enhancing
  gear generally belongs. It is not confirmation that the spell will complete,
  and very fast casts may resolve before mid gear arrives.
- **Post:** after a matching result, interruption, recognized failure, or lifecycle
  cleanup. Weapon-skill post can arrive before its visible animation finishes.

### Pet abilities

Player commands using `/pet` resources route to `pet_abilities`, not
`job_abilities`. `pre` occurs before dispatching the player's command. `mid`
occurs when the recorded pet's ability-start notification arrives. `post` follows
the pet result or terminal failure. A lifecycle may go straight from pre to post;
mid is not synthesized when no start notification is available.

Use `event.type == 'BloodPactRage'` or `'BloodPactWard'` for pacts.
`event.actor_id` remains the initiating player; `event.pet.id`, `.name`, and
`.index` identify the pet. Simple commands such as Heel can complete on the
player's acknowledgment. Unknown results use timeout cleanup. Uncommanded
automaton actions and random Sic move correlation are not covered.

### Statuses

```json
{
  "statuses": {
    "battle": {"enter": [{"commands": ["log('Engaged')"]}]},
    "idle": {"enter": [{"commands": ["log('Idle')"]}]},
    "death": {"enter": [{"commands": ["log('Dead')"]}]}
  }
}
```

Categories are `battle` = status 1, `idle` = 0, and `death` = 2 or 3.
A category transition runs the old category's leave handlers first, then the
new category's enter handlers. Changing 2 to 3 does not re-enter death.
Uncategorized statuses can leave/enter known categories but have no handlers
of their own. Fields are `event.category`, `event.status`, and `event.old_status`.
Zoning suppresses category notifications while departure/arrival is in progress.

### Zones

`zones.leave` runs on departure after pending action cleanup. Destination fields
can be nil because the zone-out notification does not identify the destination.
If departure wasn't observed, the zone-change callback supplies a fallback leave.
`zones.enter` waits for matching destination game info and a valid player mob.
These are transitions, not callbacks on every render or addon load.

| Current/destination field | Previous field |
|---|---|
| `event.zone` — numeric ID | `event.old_zone` |
| `event.zone_name` — English resource name | `event.old_zone_name` |
| `event.zone_search` — zone search name | `event.old_zone_search` |

### Loading

```json
{
  "vars": {"mode": "default"},
  "loading": {
    "actions": [{"commands": ["setVar('mode', 'ready')"]}]
  }
}
```

Loading actions run once per successful configuration load/reload, after imports,
variable merging, CSV expansion, and contributions. Successful variable changes
become the defaults copied by later events. Reload starts from files again.
Equipment changes persist. On a loading-rule error, its phase gear and variable
changes are discarded; the new configuration keeps its file-defined defaults.

## Event fields and useful checks

Action, element, and skill names are English on every client. Use `event.name`,
not `event.en` or `event.ja`; those fields are not exposed. Target/pet names are
observed game names.

| Fields | Use |
|---|---|
| `event.id`, `.name`, `.type` | Triggering resource; type examples: `WhiteMagic`, `CorsairRoll`, `BloodPactRage` |
| `event.element`, `.element_name` | Numeric element and English name such as `Dark` |
| `event.skill`, `.skill_name` | Numeric skill and English name such as `Enfeebling Magic` |
| `event.kind`, `.phase` | Event and phase identifiers from the table above |
| `event.source`, `.rule_id` | Current rule's source and ID |
| `event.actor_id`, `.request_id`, `.time`, `.injected` | Action identity and interception information |
| `event.target.id`, `.name`, `.index` | Fixed target identity for the action lifecycle |
| `event.target.valid_target`, `.status`, `.spawn_type` | Refreshed target metadata |
| `event.target.is_mob`, `.is_player`, `.is_trust`, `.is_me` | Classification flags |
| `event.target.is_idle`, `.is_engaged`, `.is_dead`, `.is_resting`, `.is_mounted` | Current target status |
| `event.target.in_party`, `.in_alliance`, `.is_party_member`, `.is_alliance_member` | Membership |

Action events always have a target table; unavailable live details can be nil.
A useful guard is `event.target.valid_target and event.target.is_mob`.
Validity does not imply alive. Classification, status, coordinates, heading, and
target index refresh each phase without changing recorded ID/name/index.
Status, zone, and loading events do not guarantee a target.

Spell events expose boolean skill flags: `divine`, `healing`, `enhancing`,
`enfeebling`, `elemental`, `dark`, `summoning`, `ninjutsu`, `singing`, `blue`,
and `geomancy`. These describe **skills**, not elements. Instrument/handbell
skill flags also reflect the spell resource, not the equipped instrument.

| Check | Meaning |
|---|---|
| `event.curing` / `isCureSpell(event)` | Cure I–VI, Curaga I–V, Cura I–III, Full Cure; excludes status removal, Raise, Regen, and Blue Magic cures |
| `isEnfeeblingSpell('Dispel')` | Resource-based spell skill classification |
| `spellHasSkill(event, 'enhancing')` | Generic skill check; also accepts a numeric skill ID |
| `canMagicBurst(event)` | Matching element and active tracked skillchain on the target, not a guaranteed future burst |

Equivalent skill helpers include `isDivineSpell`, `isHealingSpell`,
`isEnhancingSpell`, `isElementalSpell`, `isDarkSpell`, `isSummoningSpell`,
`isNinjutsuSpell`, `isSingingSpell`, `isBlueSpell`, and `isGeomancySpell`.
Spell helpers accept names, IDs, resources, or spell events. `canMagicBurst`
uses an explicit target if provided, then the object's target, then `bt`; it
does not check MP, recast, range, or predicted landing time.

### Outcomes in post

`event.outcome` can be `completed`, `interrupted`, `failed`, `cancelled`,
`timeout`, `reloaded`, `zoned`, `logout`, or `unloaded`.
`event.completed_at` records the terminal time.

`event.completed`, `.interrupted`, `.failed`, and `.timed_out` are post-only
booleans corresponding to the first, second, third, and timeout outcomes.
They are false for other outcomes and nil before post. `event.cancelled` is
available throughout and becomes true immediately on local cancellation.
An optional `event.reason` describes that cancellation.

Post is cleanup, not proof of success. Recognized rejections, pet/target loss
(where tracked), and timeouts can also finish a lifecycle. Known positive recasts
are blocked before pre, so those attempts have no lifecycle or post.

## Variables, imports, and composition

### Variables and their lifetime

`.vars.json` files accept `vars` and/or `contributions`. They cannot contain
event sections or imports. Values merge through the search hierarchy; nested
objects combine, arrays take the winning definition, and more specific values
win at equal priority.

Inline rule-file vars are implicit `^` defaults. Explicit `!` priorities and `^`
defaults retain their normal meaning; normal clearing markers also work.
Imported defaults lose to their importer at equal priority, with later sibling
imports ahead of earlier siblings. Prefixes are stripped during loading.

**Ordinary event vars are still lifecycle-local.** Pre/mid/post share one copy;
the next lifecycle gets a fresh copy of initialized defaults. Status and zone
notifications each get their own copy. `setVar`, `setVarGlobal`, and related
helpers do not modify normal Gambit action vars or save JSON. Loading actions
can initialize future defaults. Cross-lifecycle shared runtime vars and a
read-only `configs` store are not implemented. `vars._` is reserved.

Use `"csv(Savage Blade, Shining Blade)"` as a variable key to create independent
copies at that location. Whitespace is trimmed; nesting and `!csv(...)` /
`^csv(...)` work. Explicit sibling keys win at equal priority. Empty names,
malformed keys, and equal-priority overlapping CSV declarations in one object
are errors. Commas cannot be escaped inside a name.

### Imports

```json
{
  "imports": ["lib/spells/all", "lib/job_abilities/all"]
}
```

Imports resolve through **event directories**, not action libraries or relative
to the importing file. An optional `.json` suffix is allowed. Namespace/player
overrides precede shipped `events/`. The first existing match wins.

Dependencies expand first, imports in listed order, then the importing file's
own rules. Thus parent → [A, B] and A → [C] gives C → A → B → parent in each
phase. Each resolved file is included once at its first occurrence. A later
`stop` can skip subsequent modules. Missing imports, cycles, and invalid files
fail reload and retain the old configuration. Imports do not discover extra
companion variable files. Inline imports inside rule arrays are unsupported.

### Slots and contributions

Every phase has automatic `<section>.<phase>.before` and `.after` slots, even
when its ordinary array is empty. Examples: `spells.pre.before`,
`pet_abilities.mid.after`, `statuses.idle.enter.after`, `zones.enter.before`,
and `loading.actions.after`.

```json
{
  "contributions": {
    "spells.pre.after": [
      {"when": ["event.name == 'Dispel'"],
       "commands": ["log('Dispel requested')"], "id": "my-dispel-note"}
    ]
  }
}
```

Before contributions → composed rules → after contributions is execution order.
An earlier stop can prevent after contributions from running. Both rule files
and matching `.vars.json` files can declare contributions.

Custom placeholders such as `{"slot": "my-spell-hook"}` can appear inside a
phase. Names must be unique. Built-in names cannot be redeclared or moved.
Normal `slot`/`slots` arrays and ordered alternatives are supported.
Placeholders cannot also execute commands; contributions cannot contain slots
or inline imports.

| Contribution feature | Meaning |
|---|---|
| `"<slot-name>": [rules]` in `contributions` | Add rules at that slot |
| `{"actions": [rules], "optional": true}` | Suppress missing-slot diagnostics |
| `required_for: ["GEO", "BLM"]` | Require a matching slot only for matching loading players; overrides optional |
| `"^slot"` | Default definition; ignored if any ordinary/`!` definition exists; otherwise closest default wins |
| `"!slot"` | Retain higher-precedence additions and replace lower-precedence definitions |
| Comma-separated slot names | Contribute to multiple hooks; any alias satisfies a grouped `required_for` requirement |
| Rule `priority` | Finite number or `highest/high/normal/low/lowest`; lower values run first within that slot |

`optional` and `required_for` control diagnostics, **not execution**. Requirements
use normal job/group/player-name/leader selectors and exclusions. An empty
requirements array requires nothing. Missing nonoptional slots warn; malformed
rules, nested slots, duplicate custom hooks, and reserved-name declarations
fail loading. Source precedence follows event location/specificity, then discovery
order; explicit libraries have entry/library precedence within their location.
IDs resolve across the final expanded phase. Slots have no runtime lookup cost.

## Equipment and restoration

Equipment requests from one phase form one final batch. Later requests win
overlapping slots; phase queries see the local planned gear. Pre waits for
acknowledgment before dispatch. Ordinary helper calls return after requesting
changes, not after the server has confirmed them.

```lua
equipMany(vars.gear.casting)
equipment_set and equipment_set.meta and equipment_set.meta.stop and stopEvent()
```

`equipment_set` exposes the original table passed to `equipMany`/`equipPush`,
including `meta`, even for no-op swaps. Each call clears the previous value first;
each new context/phase starts without it. No-argument `equipPush()` leaves it nil.
Positive change counts are truthy; `equipMany` returns nil when no changes are
requested, so keep metadata stopping in a separate command.

Each action lifecycle starts with a baseline at the bottom of its private
equipment stack. `equipPush()` saves the current effective set; `equipPush(set)`
saves it and applies gear. `equipPop()` restores the latest exact snapshot,
including originally empty slots. An extra pop can consume the original baseline.
An empty stack pop does nothing.

Setting `use_equipment_snapshot: true` on an action section restores any remaining
baseline after post and discards the stack. If the baseline was already popped,
cleanup does not restore it twice. With the flag off, unpopped snapshots are
discarded without restoring. Status/zone/loading notifications have no implicit
baseline or automatic restoration.

Stacks are private but equipment is global: restoring a baseline can overwrite
intentional gear changes made since it was captured. A partial set only affects
its listed slots. See the [stock guide](stock-events.md#restoration-and-partial-sets)
for restoring first and then applying idle/battle gear, and
[equipment reference](equipment.md) for candidates, augments, and queue details.

## Reloading and troubleshooting

- `//gbt events status` lists the entry file, imports, and variable files.
- `//gbt events reload` reloads only events; `//gbt r` also reloads normal settings.
- `//gbt events reload -v` writes processed JSON. Normal `//gbt reload -v` does too.
- Output is in the character's current settings write location:
  `.output/<entry-name>.events.processed.json` (under namespace `players/` when active).
- The diagnostic shows final ordering/IDs, merged and CSV-expanded vars,
  `_sources.slots`, and each rule's `_source`. It is captured before loading
  actions and is not an input file.
- Normal loading announces the entry point. Per-import/variable-file load
  messages are debug-level; explicit status output still shows them.

| Symptom | Check |
|---|---|
| Stock rules aren't running | A closer or empty rule file may be overriding them; inspect status output |
| A named gear override is ignored | Exact English name, correct variable path and phase, and earlier stops |
| Casting gear stays on | Configure idle/battle slots or opt into baseline restoration; partial sets don't restore other slots |
| Mid gear misses a fast action | Put essential gear in pre for fast/instant spells, JAs, and weapon skills |
| A corrected rule still won't run | Reload events; errored rules are disabled until reload |
| A contribution does nothing | Slot name, optional/required diagnostics, earlier stops, replacement/default selection, and processed output |
| A pet action has no mid | It may have no observable start; post must handle direct pre → post |

Rule errors discard the phase's gear plan and roll back its stack edits. Pre
errors cancel dispatch. Other command side effects are not rolled back.
Handlers must remain short; don't initiate nested casts/abilities from them.
`sendWindowerCommands(array)` dispatches literal command strings separately
without Lua evaluation or waiting, but does not wait for equipment or guarantee
completion order of the receiving commands.

Login/job/namespace/settings changes can reload event configuration. Missing or
unidentifiable server results use timeout cleanup (currently 120 seconds).
An event request that never reaches the outgoing listener cannot create a
lifecycle. Test your gear and failure paths in game during beta; JSON compilation
alone cannot verify equipment ownership or timing.
