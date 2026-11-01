# Events: user guide

Gambit events react to your actions, enemy spells/abilities, and buff, status,
or zone changes. They
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
| Temporarily select a different event file | `//gbt events r -e empty` |
| See the fully processed configuration | `//gbt events reload -v` |
| Load changed Lua implementation code | `//lua reload Gambit` |
| React to a spell or ability | `pre`, `mid`, and `post` arrays |
| React to engagement, disengagement, or death | `statuses.<category>.enter` / `.leave` |
| React to zoning | `zones.enter` / `.leave` |
| React to buffs received or lost | `buffs.added` / `.removed`, filtered with `event.matches(nameOrId)` |
| React to enemy casting or readying | `enemy_spells.pre` / `.post`, `enemy_abilities.pre` / `.post` |
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
        "when": ["event.matches('Dispel')"],
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

### Event identity fields: complete reference

Every rule can read `event.kind` (event type) and `event.phase` (the phase being
executed). `event.category` is only set for status events. The complete supported
values and combinations are:

| Configuration | `event.kind` | `event.phase` | `event.category` |
|---|---|---|---|
| `spells` | `spell` | `pre`, `mid`, `post` | nil |
| `job_abilities` | `job_ability` | `pre`, `mid`, `post` | nil |
| `weapon_skills` | `weapon_skill` | `pre`, `mid`, `post` | nil |
| `pet_abilities` | `pet_ability` | `pre`, `mid`, `post` | nil |
| `statuses.battle` | `status` | `enter`, `leave` | `battle` |
| `statuses.idle` | `status` | `enter`, `leave` | `idle` |
| `statuses.death` | `status` | `enter`, `leave` | `death` |
| `zones` | `zone` | `enter`, `leave` | nil |
| `buffs` | `buff` | `added`, `removed` | nil |
| `enemy_spells` | `enemy_spell` | `pre`, `post` | nil |
| `enemy_abilities` | `enemy_ability` | `pre`, `post` | nil |
| `loading` | `loading` | `actions` | nil |

These values use singular event kinds even where the JSON section is plural.
`event.category` is not the raw numeric action-packet category or a substitute
for `event.kind`. Raw player status values are exposed separately as
`event.status` and `event.old_status`.

Contribution suffixes `before` and `after` describe positions within a phase,
not additional phases or categories. A rule contributed to
`enemy_abilities.pre.after` sees `event.kind == 'enemy_ability'` and
`event.phase == 'pre'`. A contribution to `statuses.idle.enter.before` sees
`event.kind == 'status'`, `event.phase == 'enter'`, and
`event.category == 'idle'`. There is no `event.phase == 'before'` or `'after'`.

### Spells, job abilities, and weapon skills

- **Pre:** before releasing the outgoing action. Equipment requests are batched
  and acknowledged before dispatch. Use this for Fast Cast, weapon-skill gear,
  job-ability enhancement gear, and essential gear for very fast/instant spells.
- **Mid:** immediately after dispatch. For spells, this is where result-enhancing
  gear generally belongs. It is not confirmation that the spell will complete,
  and very fast casts may resolve before mid gear arrives.
- **Post:** after a matching result, interruption, recognized failure, or lifecycle
  cleanup. Weapon-skill post can arrive before its visible animation finishes.

### Match event names and IDs

Prefer `event.matches(value)` for identity conditions instead of comparing
`event.name` directly. It accepts English names case-insensitively, numeric IDs,
or numeric strings:

```json
{
  "when": ["event.matches('Dispel')"],
  "commands": ["log(event.name)"]
}
```

For buffs, spells, job abilities, weapon skills, pet abilities, and enemy action events it compares
`event.name` or `event.id`. Buff names use the resource name, not condition
descriptions such as `doomed`. `event.matches('Doom')`, `event.matches('doom')`,
and `event.matches('DOOM')` are equivalent. `event.matches(15)` and
`event.matches('15')` both select buff ID 15. Missing names still allow ID matches;
unsupported values and events without an applicable identity return false.

Action events also recognize the explicit [English resource-name aliases](functions.md#english-resource-name-aliases).
For example, `event.matches('Nat. Meditation')` and
`event.matches("Nature's Meditation")` match either resource spelling.
This does not rewrite `event.name`, merge IDs, or alias buff condition descriptions.
Configured table keys can opt into the same pairs with `resourceAliasKeys(table)`
in a loading action; matching does not automatically rewrite variables.

For status events, names match the category (`battle`, `idle`, `death`); numeric
values match the old status on leave and current status on enter. Zone events
match the departing zone's English name/ID on leave and the destination's on
enter. Zone search names are not aliases. `event.name` and all other metadata
retain their original values for display.

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

### Enemy spells and abilities

Enemy events observe nearby monster actions independently of normal automation.
`enemy_spells.pre` means casting was observed starting; `enemy_abilities.pre`
means a monster ability was observed readying. `post` reports the observed result
or interruption. These are notifications, not opportunities to intercept or
cancel the enemy's action. There is no `mid` phase or equipment dispatch barrier
holding up the enemy.

```json
{
  "enemy_spells": {
    "pre": [
      {
        "when": ["event.matches('Firaga III')", "bt and event.actor.id == bt.id"],
        "commands": ["log('Battle target started casting', event.name)"]
      }
    ]
  },
  "enemy_abilities": {
    "post": [
      {
        "when": ["event.matches('Mortal Ray')"],
        "commands": ["log(event.actor.name, event.outcome)"]
      }
    ]
  }
}
```

Lua observes monster actors (`spawn_type == 16`) generally; custom rules may
select any actor. The stock gear rules explicitly require the current `bt` in
JSON. They are not a restriction on contributions or custom event files.

| Field | Meaning |
|---|---|
| `event.id`, `.name`, `.matches(value)` | Spell or monster-ability resource identity and English name |
| `event.actor_id`, `.actor` | Acting monster; actor includes shared target classification and live metadata |
| `event.target`, `.targets` | First reported target (always a table) and all reported target snapshots; an AoE packet dispatches once, not once per target |
| `event.element`, `.element_name`, `.type` | Resource metadata, when available |
| `event.skill`, `.skill_name`, `.cast_time` | Spell metadata, when available; spell classification flags are also exposed |
| `event.outcome` | Post only: `completed`, `interrupted`, or a recognized `failed` result |
| `event.completed`, `.interrupted`, `.failed` | Corresponding booleans; false in pre |

Unknown resources retain a reported ID when available, with a nil name.
Interruption packets may omit the action identity altogether; those posts still
identify the actor and outcome, but cannot match a name or ID. There is no
remembered lifecycle used to guess missing identity or synthesize outcomes.
This initially covers casting packets (categories 8/4) and monster ability
readying/results (7/11), not melee swings, ranged attacks, or player job abilities.

Pre and post are independent: instant actions and missed starts can produce
post-only notifications, while missing results do not produce timeout posts.
Each notification has isolated event variables and its own equipment batch.
Gear persists, and automatic equipment snapshots are not supported. Do not rely
on a pre push being balanced by a post pop, especially if `bt` changes. Request
explicit gear sets instead. `stopEvent()` is supported; cancellation is not.

Imports, contributions, and processed exports work normally. Built-in hooks
include `enemy_spells.pre.before`, `.pre.after`, `.post.before`, `.post.after`,
and the corresponding `enemy_abilities` hooks. These observations currently do
not change the backing state of `enemyUsedAbility` or `enemyCastingSpell`.

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

### Buffs received and removed

`buffs.added` and `buffs.removed` are ordered rule arrays for buffs gained or
lost by your own character. They use Windower's gain/lose buff notifications and
run even when automation is disabled. They do not observe party-member buffs or
synthesize notifications for buffs already active when events load/reload.

```json
{
  "buffs": {
    "added": [
      {
        "when": ["event.matches('Doom')"],
        "commands": ["equipMany({ring1={name=\"Eshmun's Ring\", lock_when={\"hasBuff('Doom')\"}}})"],
        "id": "doom-ring"
      }
    ],
    "removed": [
      {
        "when": ["event.matches('Doom')"],
        "commands": ["log('Doom removed')"],
        "id": "doom-removed"
      }
    ]
  }
}
```

| Field | Meaning |
|---|---|
| `event.kind` | `buff` |
| `event.phase` | `added` or `removed` |
| `event.id` | Numeric buff ID, including for unknown resource entries |
| `event.name` | English resource name; nil for an unknown buff ID |
| `event.name_lower` | Precomputed lowercase English buff name; nil when the name is unknown |
| `event.actor_id` | Your character's ID |
| `event.time` / `event.request_id` | Notification time and runtime sequence ID |

Use `event.matches(15)` or `event.matches('15')` to select an exact buff ID.
`event.matches('Doom')` compares English names without regard to capitalization.
Name conditions
intentionally match all IDs carrying that name; they do not identify the caster
or source spell. Filter within the arrays using `when`, rather than nested
name-keyed event sections. Every matching rule runs in order unless stopped.

These are observations, not cancellable action lifecycles: no `pre`/`mid`/`post`,
automatic snapshot restoration, or `use_equipment_snapshot`. Each notification
has isolated event variables and one batched equipment phase; its gear persists.
`stopEvent()` and rule `stop` work; `cancelEvent()` and `stopEvent(true)` do not.

Use [conditional equipment locks](equipment.md#conditional-slot-locks) to keep a
buff-triggered piece on through later battle/idle swaps. Removing the buff lets
the next competing equipment request expire its lock; it does not itself restore
gear. Configure a removed handler to request replacement gear if desired.

Built-in contribution slots are `buffs.added.before`, `buffs.added.after`,
`buffs.removed.before`, and `buffs.removed.after`. Imports, rule IDs, custom slots,
vars-file contributions, and processed JSON exports work as for other events.
The stock `lib/buffs/all` module adds name-based gear sets and later ID-specific
overrides; see [buff gear configuration](stock-events.md#configure-buff-specific-gear).

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
`event.time` records lifecycle creation and `event.duration` gives elapsed seconds
from creation to termination, available in post. Rejection/failure and timeout
cleanup diagnostics include
elapsed creation/dispatch times (or indicate that dispatch never happened).
Normal completion, interruption, local cancellation, and lifecycle teardown do
not emit these cleanup messages.

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

See [Variables](variables.md) for definitions, Lua references, clearing markers,
priority prefixes, and CSV key expansion across actions and events.

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
      {"when": ["event.matches('Dispel')"],
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

`equipRestore()` restores the original lifecycle baseline directly and discards
intermediate pushes. It returns a positive requested-change count, or nil for
no changes/no remaining baseline. A consumed baseline is never restored again;
without a lifecycle baseline it leaves manual snapshots alone. Restoration joins
the current phase batch, so later idle/battle gear can overlay it. Use this helper
rather than inspecting internal stack storage.

Use stopping cautiously in post: `stopEvent()` and `stop: true` can skip later
cleanup and restoration rules. Lifecycle-managed automatic restoration still
runs after the phase.

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

Use `//gbt events r -e empty` to select `empty.json`, or
`//gbt events r -e lib/my-events` for a library-style path. The name resolves
through the normal event directories, with the closest matching file winning;
the `.json` suffix is optional. Absolute paths and `..` traversal are rejected.
Imports still resolve through the complete event hierarchy, and normal matching
job/group variable files still load independently of the selected rule file.
Selection does not discover an additional companion vars file for the explicit
name unless it already matches the normal variable search.

The selection is session-only: `//gbt events r -r` reloads the current selection,
while plain `//gbt events r` or full `//gbt r` restores automatic selection.
Full settings/job/namespace reloads also restore automatic selection.
`-r` has the alias `-reload` and cannot be combined with `-e`.
A failed selection leaves the current configuration active. `r` is
an alias for `reload`, and `s` is an alias for `status`. `-e` also accepts the
alias `-events`, and can be combined with `-v` for processed output.

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
unidentifiable server results use timeout cleanup: three seconds after dispatch
for player job abilities and weapon skills, and 30 seconds for pet abilities.
Spells must receive a matching server casting-start notification within three
seconds of dispatch. Once confirmed, they have twice the resource cast time
plus three seconds from that notification to complete. A completion without a
start notification still finishes normally. Local mid execution is not server
start confirmation. Delayed or missing start packets can cause false timeouts;
debug diagnostics distinguish missing start from missing completion. Equipment dispatch
waiting has a separate ten-second fallback; its queue has its own failure
handling. An expired request runs post cleanup before a retry is accepted.

A duplicate ordinary job ability can recover after a one-second response grace
when its recast still reports ready. Charge-based abilities are excluded from
this inference. Recognized rejections prefer the newest dispatched request only
when it is recent and clearly separated from older requests; ambiguous messages
retain timeout recovery. Missing/dead hostile targets also trigger cleanup.
Debug logging records suppressed duplicates and recovery reasons. With
`//gbt config -debugging on`, these diagnostics also go to the Windower console
independently of chat verbosity, but only for lost-lifecycle timeout recovery.
Recognized rejections and other handled failures retain debug-chat diagnostics
without console output. Import-load messages remain on the ordinary
debug output path. Cleanup
honors your post rules and snapshot settings; it does not force restoration when
your configuration deliberately leaves equipment in place.
An event request that never reaches the outgoing listener cannot create a
lifecycle. Test your gear and failure paths in game during beta; JSON compilation
alone cannot verify equipment ownership or timing.
