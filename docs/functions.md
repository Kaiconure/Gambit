# Action Functions

The following functions are available for use in your actions. They are broken down by broad category, and they can all be used in both the `when` condition or in the actual action `commands` -- though some may make more sense in one versus the other.



## Case-insensitive table keys

`caseInsensitiveKeys(table)` returns a new table with its immediate string keys
lowercased. Numeric keys and all values are preserved; nested keys, item names,
and expression strings are not altered. Ambiguous keys such as `Doom` and `doom`
raise an error. The input table is not modified.

```lua
setVar('my_named_sets', caseInsensitiveKeys(vars.my_named_sets))
```

This is an opt-in helper available to normal actions and event rules. Loading
actions can normalize configuration once per load. Later additions/replacements
must follow the same key convention or be normalized again. No variable paths
are automatically normalized by Gambit.

Event conditions should use `event.matches(nameOrId)` for case-insensitive
English-name comparisons or numeric/numeric-string ID comparisons; see
[matching events](events.md#match-event-names-and-ids).

## English resource-name aliases

`resourceAliasKeys(table)` returns a shallow copy with both spellings of known
English resource-name pairs available as keys. Values, numeric keys, and
unrelated names are preserved. It does not generally lowercase table keys.
Defining conflicting values under both aliases raises an error; applying the
helper repeatedly to its own output is safe. When replacing a definition after
expansion, build a fresh definition table or remove the old mirrored alias first,
so two aliases do not retain conflicting values.

```lua
setVar('my_spell_sets', resourceAliasKeys(vars.my_spell_sets))
```

Use this opt-in helper in loading actions for custom named gear tables. Keys
added/replaced later should be expanded again. Gambit does not inspect variable
paths automatically. `event.matches(...)` independently accepts either spelling
for spell, ability, weapon-skill, pet-ability, and enemy-action events.

| Monster ability name | Blue Magic spell name |
|---|---|
| Atramentous Libations | Atra. Libations |
| Everyone's Grudge | Evryone. Grudge |
| Nature's Meditation | Nat. Meditation |
| Orcish Counterstance | O. Counterstance |
| Quadratic Continuum | Quad. Continuum |
| Tempestuous Upheaval | Tem. Upheaval |
| Winds of Promyvion | Winds of Promy. |

The explicit pairs live in `meta/resource-name-aliases.lua`. Both lookup
directions are prepared once; internal spell and monster-ability lookups retain
the resource-name cache. Resource IDs and original displayed names are unchanged.
Aliases do not merge same-named resources or make IDs interchangeable between
resource tables. Buff, status, and zone matching do not use these action aliases.

## Panel checklist state

`checklistSet(checklistId, itemId, checked)` saves a boolean at
`vars.panel.<checklistId>.<itemId>` and returns it. Nil and false become false;
all other Lua values, including zero and empty strings, become true.
`checklistGet(checklistId, itemId)` returns a boolean; missing state returns false.

Both helpers use shared automation variables, including from event handlers and
scoped actions. They work while the checklist is hidden. State is not saved to
panel preferences. IDs follow the [panel checklist rules](status-panel.md#objective-checklists).

```lua
checklistSet('sortie_a', 'kill_5_abject', true)
checklistGet('sortie_a', 'kill_5_abject') -- true
```

## Optional selector ordering

Expression selectors `partyAny`, `partyAll`, `allyAny`, and `allyAll` also accept
a final options table with `randomize`, `self_first`, and `self_last`. Only the last argument
is treated as options when it is a table; earlier arguments remain expression
formatting arguments:

```lua
partyAny('distance < %d', 15, {randomize=true})
partyAll('is_player', {randomize=true, self_first=true})
```

Options change ordering, not eligibility. Fresh enumerations shuffle once;
`partyAll`/`allyAll` retain that order while continuing an existing cycle.
Count helpers do not need ordering options. `partyAnchorByName` retains its
deterministic preference ordering.

`self_last=true` moves yourself to the end after shuffling, if you match the
selection. Other members retain their relative order. If both `self_first` and
`self_last` are truthy, `self_first` wins. All three options default to false and
work with both expression and name-based selectors.

```lua
partyAny('is_player and not hasBuff("Sneak")', {randomize=true, self_last=true})
```

`partyByName(targets, options)` and `alliesByName(targets, options)` accept a trailing options table: `{randomize = true, self_first = true}`. Targets may be an array or separate arguments. Both options default to false. Randomization shuffles the resolved matches once per fresh enumeration, after exclusions and deduplication; self-first then moves yourself to the front if included. Neither option changes membership. Continuing the cycle preserves its order. These options are not used by `partyAnchorByName`, which keeps deterministic preference ordering.

`partyNames(targets)` returns a new array of matching party names in deterministic
selector order (alphabetical within each job/group, deduplicated with exclusions
applied). `partyMatches(targets, member)` tests membership; `member` defaults to
`me`. Both accept the existing names, jobs, groups, `me`, `*`, `^`, and `~`
selector syntax and leave `member`, enumerators, and target selection unchanged.
Use `partyNames({'PLD', 'RUN'})[1]` for a consistent primary tank, or
`partyMatches({'melee_dps', 'ranged'})` to test whether the current character is a DD.
Role resolution depends on known party job information; no match yields an empty
array or false. Client-relative selectors such as `me` and `^` should not be used
for a shared cross-client WS order.

## Member positioning

### Movement reservations

Cooperating actions can declare `"movement_owner": "corsair-rolls"` (or another unique owner name) and call `reserveMovement(seconds)` before starting a movement sequence. It returns false if another owner holds the reservation. Repeated acquisition by the same owner does not extend the deadline.

`hasMovementReservation()` checks whether the current action owns the reservation; `releaseMovement()` releases only its own reservation. `movementAvailable()` is true when no reservation exists or the current action owns it. Use it as a precondition in ordinary movement actions to skip without consuming a scheduler hit.

`resumeMovement(seconds)` keeps an existing reservation or acquires one for continuation in a new section/encounter context. It refuses to restart a reservation that expired or was released in the same context. A genuinely new operation uses `reserveMovement(seconds)`. Roll Double-Up actions use continuation only after checking ability availability and the roll policy, allowing an unfinished roll to continue across battles without repeatedly renewing a timed-out reservation.

Reservations cancel existing addon movement when acquired, and cancel movement when released or invalidated. They expire on the next reservation check after the deadline, and are invalidated by action-section, encounter-scope, zone, or variable-state reload changes. `align`, `align2`, `move`, `follow`, and `cancelFollow` reject competing callers with `nil, 'reserved'`. Facing and non-movement actions remain available. Direct movement commands outside these context helpers bypass this mechanism.

Optional roll alignment uses this reservation through its initial roll and Double-Up actions. Frontline engagement, member engagement, and idle follow-leader check availability before running. The configured roll alignment timeout bounds the entire reservation, including the initial approach.

Import `member-engagement` into the section where you want to stay near a party member. Configure it with:

```json
"member_engagement": {
  "targets": ["^WHM"],
  "distance": 2,
  "duration": 3,
  "max_distance": 30,
  "tolerance": 1
}
```

These are the default distances and duration; targets default to an empty array, which disables movement. Normal party selectors, including jobs, roles and exclusions, are supported. The action moves when farther than `distance + tolerance` yalms, aiming for `distance`; being closer is acceptable. Its action frequency remains three seconds. `duration` defaults to three seconds per alignment attempt; `retry_delay` defaults to ten seconds of postponement after movement failure. Avoid importing competing positioning actions in the same section.

`partyAnchorByName(targets, maxDistance, excludeSelf)` selects a living, valid party member within `maxDistance` yalms (default 30). Yourself is eligible when matched by the selectors unless `excludeSelf` is true; `member-engagement` explicitly passes true. Self-exclusion happens before selection so another eligible member can be chosen. It returns and sets `member`, or returns nil and clears `member` if nobody qualifies. Selection is reevaluated in deterministic selector order using fresh party data each time; a preferred member becoming eligible again takes precedence. It does not advance the normal member enumerator. Nil or empty targets select nobody. The helper supplies stable positioning targets; it does not engage or change the battle target.

## Ability Functions

These functions are related to the use of job abilities.

- `canUseAbility(name1, name2, ... , nameN)` - Results in the first usable ability from the list of provided abilities that is ready to be used, or nil if none are usable. Typically used in the `when` condition to determine if an ability can be used. The match will be saved to the context symbol `ability`, and subsequent calls to `useAbility` without an ability name will use this instead.
  - Will not trigger if you are asleep or suffering from amnesia.
  - Abilities that use TP (such as DNC waltzes or sambas) will only trigger if the required TP is available.
  - <!-- Need to investigate job abilities that use finishing moves, pet commands, others? -->
- `useAbility(target, ability)` - Use an ability on the specified target. If no target is specified, the current battle target will be used instead. If no ability is specified, the result of the most recent `canUseAbility` will be used.



## Item Functions

`findKeyItem(nameOrId)` returns the key-item resource only if you currently own it, otherwise nil. It also sets `key_item` on success and clears it on failure. For example, `findKeyItem('chipped sandworm tooth')` or `findKeyItem(1477)` checks the same Abyssea key item. Name lookup uses the shared resource cache; ownership is read live on each call, including after acquiring or consuming a key item. This context helper differs from the internal resource-only lookup of the same name.

These functions are related to the use of items.

- `canUseItem(name1, name2, ... , nameN)` - Results in the first usable item from the list of provided items that is ready to be used, or nil if none are usable. Typically used in the `when` condition to determine if an item can be used. The match will be saved to the context symbol `item`, and subsequent calls to `useItem` without an item name will use this instead. 
  - Can be used with enchanted equipment, though it **does not** take item activation timers into account (i.e. the five second countdown after equipping a Capacity Ring). It **does** take into account reuse timers  (i.e. the two hour cooldown after using a Capacity Ring).
  - Can be used with food, and it will not trigger if you're already fed.
  - Will not trigger if you are asleep.
- `useAbility(target, ability)` - Use an ability on the specified target. If no target is specified, the current battle target will be used instead. If no ability is specified, the result of the most recent `canUseAbility` will be used.



## Spell Functions

- `canUseSpell(name1, name2, ... , nameN)` - Results in the first usable spell from the list of provided spells that is ready to be used, or nil if none are usable. Typically used in the `when` condition to determine if a spell can be used. The match will be saved to the context symbol `spell`, and subsequent calls to `useSpell` without a spell name will use this instead.
  - Will not trigger if you are asleep or silenced.
  - Will not trigger if you have insufficient MP.
  - Will not trigger if the spell is not applied (BLU magic)
- `useSpell(target, spell)` - Use a spell on the specified target. If no target is specified, the current battle target will be used instead. If no spell is specified, the result of the most recent `canUseSpell` will be used.



## **Combined: Abilities, Items, and Spells**

Sometimes, you may find yourself wanting to use the best option spanning spells, abilities, and items rather than limiting yourself to just one type. 

For example, let's say you want to pick the best healing option between the various Curing Waltz abilities and Cure spells. You can actually ask Gambit to figure that all out for you by omitting the category entirely from the *canUse* and *use* functions.

- `canUse(name1, name2, ... , nameN)` - Similar to `canUseAbility`, `canUseItem`, and `canUseSpell`, but not limited to just one type. Finds the first usable entry from the list, and applies that to the context.
- `use(target, name)` - Use an ability, item, or spell on the specified target. If no target is specified, the current battle target will be used instead. If no ability is specified, the result of the most recent `canUse` will be used instead.

Here's an example:

```json
{
    "when": "me.hpp < 50 and canUse('Curing Waltz IV', 'Cure IV', 'Curing Waltz III')",
    "commands": "use(me)"
}
```

In plain English, this says:

> When my HP is below 50%, use the best available of Curing Waltz IV, Cure IV, or Curing Waltz III



## Buffs, Debuffs, and Effects

- `hasEffect(effect1, effect2, ... , effectN)` - Determine which (if any) effects are currently applied to you. The match will be saved to the context as a variable named `effect`.
  - This is aliased as `hasBuff`, and the two can be used interchangeably. 
- `hasEffectOf(name1, name2, ... , nameN)` - Similar to `hasEffect`, but allows you to specify the spell or ability that *causes* the effect rather than the effect itself. For example, you can call this with `Dream Flower` and it will detect if you are asleep. If matched, the resulting effect will be stored to the `effect` variable.

`hasAllBuffs([target,] [strictness,] buffs)` returns true only when every requested
buff is known on the target (yourself by default). Supply an array or separate
arguments, using buff names, IDs, or resource objects. Targets and the optional
`'use-strict'` / `'not-strict'` flags work as with `hasBuff`. An empty array returns
true. This query leaves `effect` and `effect_count` unchanged.

```lua
hasAllBuffs(bt, vars.required_buffs)
hasAllBuffs(bt, 'Protect', 'Shell')
hasAllBuffs({'Haste', 'Protect'})
```

Here's an example:

```json
{
    "when": "hasEffectOf('Silence') and canUse('Healing Waltz', 'Echo Drops')",
    "commands": "use(me)"
}
```

In plain English, this says:

> If I'm silenced, remove it with Healing Waltz (first choice) or some Echo Drops.
# Flexible alignment

`align(target, angle, distance, duration, noFace, tolerance)` supports exact angles and flexible positioning. Optional positional tolerance is in yalms; `aligned` and `aligning` accept it as their fourth argument. Frontline engagement uses `vars.frontline_engagement.tolerance`, defaulting to 0.5, for its alignment check and movement completion. Other callers retain their existing defaults. The same angle values work with `vars.frontline_engagement.angle`.

Frontline engagement caches only `max(0.125, (distance or 0.5) + (distance_offset or 0))` using variable scope. Smart Move applies `radius_multiplier` from the options object when resolving each target-relative destination; frontline defaults it to `0.25`. A numeric multiplier replaces the automatic player/target size adjustment with `max(0, target.model_size or 0) * max(0, radius_multiplier)`. For example, distance `0.5`, offset `0.25`, and target model size `4` produce a final center distance of `1.75` yalms. Zero means no size adjustment; missing or null retains legacy behavior (alignment adds half the combined player/target sizes, following adds three quarters, unless global `useRawDistances` is enabled). An explicit multiplier also applies when global raw distances are enabled.

`align`, `aligned`, `aligning`, and `alignWithRetry` accept this through their existing options argument. `follow(target, distance, options)` now accepts the same optional object. `followDistance(target, distance, options)` returns the resolved center distance for follow range checks without starting movement. Frontline uses it with `center_distance` so range checks and following agree, and forwards the same options to alignment checks and movement. The rear-engagement import inherits this behavior. Smart Move retains its separate mounted-follow and lateral-follow offsets. Follow resumption preserves the original requested distance and multiplier, avoiding repeated size adjustments.

Set `vars.frontline_engagement.distance_priority` to `true` to enforce the assigned angle until successfully aligned once per battle, then hold position whenever the target's resolved center distance is within `tolerance`, regardless of its facing. This defaults to `false`. It also prevents following from restarting inside the outer tolerance boundary. If distance is outside tolerance, alignment still uses the configured angle; initial angular alignment is required before holding position. Failed or interrupted movement does not count as arrival; checking a pending movement destination does not count either. The caller owns `options.arrived`: alignment helpers only read it and never retain arrival state. Frontline clears `frontline_engagement.arrived` with a battle-scoped action, then sets it after successful movement or an actual-position check confirms arrival. It remains set for the rest of that battle; changing targets or configuration within the same battle does not clear it automatically. Facing the target in place remains enabled.

| Angle | Meaning, relative to the target's facing |
| --- | --- |
| `nil` / JSON `null` | Try your current direction from the target, then +45° and -45° if movement times out. Any direction at the requested distance counts as aligned. |
| A number, such as `180` | Exact angle; no alternate destination. Numeric strings also work. |
| `"rear"` | Alias for numeric `180`, using the normal positional tolerance and exact-angle timeout. |
| `"face"`, `"front"`, `"facing"` | Aliases for numeric `0`, using the normal positional tolerance and exact-angle timeout. |
| `"frontside"` | 0° ± 30°. |
| `"backside"` | 180° ± 30°. This is a positioning region, not a guarantee that positional ability requirements are met. |
| `"left"` | 90° ± 30°, relative to the target. |
| `"right"` | -90° ± 30°, relative to the target. |
| `"side"` | Either the left or right region. |
| `"180+/-30"` | A center and half-width, from 0 through 180 degrees of half-width. |
| `"150-210"` | An arc from the first angle to the second in increasing angle order. Wraparound works: `"330-30"` crosses zero. A span of 360° permits the full circle. |

Semantic names are case-insensitive. Invalid specifications raise an error rather than silently becoming unrestricted alignment.

For flexible ranges, a character already inside an allowed arc keeps its current bearing when correcting distance. Otherwise, a preferred angle is randomized and remembered on the executing action for the current battle scope, target, and angle specification. A later successful fallback becomes the preference. If already at the requested distance anywhere in an allowed arc, no repositioning is needed. Target movement or turning during an unsuccessful attempt defers correction to a later evaluation instead of trying arc extremes. This reduces clustering but does not coordinate character positions or guarantee separation.

On a movement timeout, alignment tries other allowed destinations, including arc endpoints. `side` can try the other side. The default total attempt budget is six seconds for flexible alignment and three seconds for an exact angle; supplying `duration` overrides it. Scheduling, polling, and movement cleanup can add some overhead. Cancellation or replacement of the movement job ends the attempt without starting another fallback. Failure returns false; success returns true. This is bounded destination retrying, not wall detection or pathfinding.

```json
"vars": {
  "frontline_engagement": {
    "angle": "backside",
    "distance": 8
  }
}
```

The frontline action still applies its existing `canAlign` checks, model-size distance handling, and failure postponement. Movement paths themselves are not constrained to remain inside the permitted arc; the arcs describe destinations. With `align2`, flexible string angles use the same retry behavior without final facing.
Both positioning imports expose `duration` and `retry_delay` under their respective variable objects. `frontline_engagement.duration` defaults to `null`, retaining `align`'s automatic budget (three seconds for exact angles, six for flexible positioning); `member_engagement.duration` defaults to three seconds. Both retry delays default to ten seconds. Durations are clamped to at least one second by `align`; retry delay controls failure postponement, not the action's frequency or a guaranteed retry time.

For shorter attempts in a mage's job-specific common file, set the applicable object to `{"duration": 1, "retry_delay": 2}`. These options affect alignment attempts only, not camp movement, trust engagement, or background following. They do not change action ordering or make movement asynchronous.

## Party-distributed alignment

Opt in to distributed frontline positioning with:

```json
{
  "vars": {
    "frontline_engagement": {
      "distribute": true,
      "angle": "side"
    }
  }
}
```

The leader must also be running the updated Gambit, but need not opt into
distribution. It publishes its party-slot order over IPC. Participating clients
advertise their current target, parsed arc union, and alignment distance; matching
profiles divide that allowed angular space into fractional slices in the leader's
order. Different distances or arc sets form separate groups. Party members with
no matching advertisement do not occupy a slice. Roster slots are not filtered by
temporary death or distance. Profiles and the shared roster refresh every ten seconds,
with immediate updates on changes. Reloading requests fresh profiles from peers.
Initial synchronization may take a couple of seconds;
ordinary flexible alignment remains available while no shared assignment exists.

Slices apply to the actual arc union, including custom ranges, gaps, overlaps,
and wraparound. They do not special-case names such as `side`. Exact angles and
unrestricted/nil angles bypass distribution. Following distances are unchanged.

The nearest point in the assigned slice is tried first. If blocked, alternatives
may use the entire configured arc set, including other arcs and slices. Movement
attempts share the existing duration budget; distributed attempts check progress
in short steps. Continuing progress or untried alternatives return to the scheduler
using `progress_retry_delay`; exhausted attempts use `retry_delay`. Cancellation
does not restart movement via an alternative.

A successful fallback is accepted for that target/profile/roster, including on
subsequent action ticks, instead of repeatedly reclaiming a blocked slice. Changes
to target, configuration, group assignment, leader, zone or action reload reset
the preference. This is destination selection, not pathfinding: walls may still
force stacking, and the travel path is not constrained to the allowed arcs.

For direct calls, pass the same options object to both
`aligned(target, angle, distance, tolerance, options)` and
`align(target, angle, distance, duration, noFace, tolerance, options)`.
`alignWithRetry` forwards its existing options object automatically.

## Sending Windower commands

`sendWindowerCommands(commands)` accepts one literal command string or a dense
array of strings. It dispatches nonblank strings in order with
`windower.send_command`, without evaluating Lua or waiting for completion.
It returns the number dispatched, or nil for an empty array/blank-only input.
Nil is not accepted.

```lua
sendWindowerCommands('input /echo Ready')
sendWindowerCommands({'input /echo Ready', 'lua c other start'})
```

## Evaluating reusable conditions


`evaluateAll(conditions, ...)` returns a boolean. A string is evaluated through the existing execution cache; an array evaluates each condition in order and stops at the first falsy result. Boolean inputs are used directly, numbers are truthy (including zero), and both `nil` and an empty array return false. Arrays must be contiguous; nested arrays are not supported. Expression errors propagate to the action guard.

Use `evaluateAllConditions(vars.idle_precondition)` for an optional reusable list of requirements, or `not evaluateAllConditions(vars.primary_tank_precondition)` for its inverse. Strings returned by expressions are treated as values, not executed recursively.

`execute` remains unchanged: it evaluates every expression in an array and returns the final expression's results, rather than combining them with AND.

`evaluateAllConditions(conditions, ...)` is the optional-condition variant: `nil` or an empty array returns `true` (no restrictions). All other inputs delegate to `evaluateAll`, preserving explicit `false`, short-circuiting, argument forwarding, and validation of malformed tables. An expression that returns `nil` still fails. For example, `evaluateAllConditions(vars.idle_precondition)` permits execution when the policy is absent, while respecting a policy explicitly set to `false`.
# Short alignment attempts

The first direction receives the full configured movement budget rather than a
share divided among candidate angles. When a timed-out attempt makes progress,
the next call continues that direction. When it is blocked, untried directions
are retained for later calls. This preserves scheduler opportunities between
attempts without shortening each movement to reserve time for alternatives.

`align` returns `false, 'progress'` when its movement budget expires after making
measurable progress toward the destination. It does not try another angle or apply
its internal failure postponement in that case. Existing boolean callers remain
compatible. The engagement libraries use `progress_retry_delay` for this outcome
and `retry_delay` for other unsuccessful attempts.

`frontline_engagement.initial_delay` defaults to 2 seconds since entering battle;
set it to 0 to permit immediate alignment. Boss mage settings currently restore
the two-second delay, default frontline duration (3 seconds for exact angles,
6 for flexible angles), three-second member duration, and ten-second failure retries.
Healing still needs to precede movement: alignment returns between short attempts,
but does not interrupt an attempt when someone takes damage.

`alignWithRetry(target, angle, distance, options, noFace, successDelay)` forwards
`duration` and `tolerance` from options to `align`. On failure it postpones using
`progress_retry_delay` (default 1) or `retry_delay` (default 10). Optional
`successDelay` postpones after arrival. It returns the alignment result and reason.

`alignWithReservation(target, angle, distance, options, noFace)` positions a resolved
target under an existing movement reservation. Options include `duration`,
`tolerance`, optional acceptable `range`, `progress_retry_delay` (default 1), and
`retry_delay` (default 10). Arrival or already being within `range` returns true
and retains the reservation. Partial progress returns false, retains the lease,
and postpones briefly. Missing/invalid targets, movement-blocking statuses, and
other failures release the reservation and back off. The caller must pass nil
when target selection fails, rather than short-circuiting before the helper.
Callers acquire/resume reservations separately; this helper never acquires or
extends them, even when the selected target changes. Roll actions use this helper
after resolving their party anchor on each attempt.

### Abyssea red proc search

For complete custom-action examples and configuration tables, see
[Abyssea interface for custom actions](abyssea.md).

The shipped red/blue actions share `vars.abyssea.weapon_proc`: exact `"red"`
selects red, exact `"blue"` selects blue, and every other value selects neither.
The default is `"none"`; nil and unrecognized values safely disable both without
an error. Set the mode explicitly for automatic search. Manual `abyssea/red/use`
and all `abyssea/blue/use*` selectors also choose their corresponding mode.
Yellow can run alongside either. All colors' observations continue updating
regardless of the selected weapon search.

Mode selection belongs to the action files. They pass a live `is_active` expression
in the explicit Lua config, allowing queued WS requests to be cancelled if the
mode changes before dispatch. Custom action callers can provide their own
`is_active` expression string or AND array of expression strings without using
this variable path. Expressions are evaluated in the action context on every
check, including queued dispatch. Empty arrays are false; callbacks remain
supported for Lua callers. Already transmitted
equipment or action packets cannot be recalled.

Import `abyssea/red-proc` in battle actions to run the red search. The action file
resolves `weapon_set_name`, `weapons.LOW`/`weapons.HIGH`, shared weapon-set
fallbacks, and target allow/black lists, then explicitly supplies them to the Lua
interface. Lua does not read action variable paths. It uses the currently equipped
weapon first, then cycles through owned, job/level-appropriate configured main
weapons and their usable red WS. Main weapon changes wait for confirmation and
ability-list refresh. Empty current slots do not prevent selecting a configured
weapon. A new hint supersedes an obsolete pending rotation swap.

Swap requests appear in normal output; confirmed equipment and available-skill
checks appear at debug verbosity. The refresh delay begins when equipment is first
observed as confirmed, not when the request was queued. `refresh_delay` defaults
to two seconds; `equip_timeout` defaults to ten seconds. Both are explicit config
fields also forwarded by shipped actions from per-proc settings. Unconfirmed or
failed swaps produce an incomplete pass and retry; they are not counted as proof
that a weapon has no usable WS. Available WS waiting on TP, range, or another
readiness condition produce a deduplicated waiting message.
Successful swap requests log the
weapon name; deduplicated rotation diagnostics distinguish an incompatible
candidate pool, absent rotation weapons, and completion of a search pass.
Red and blue swap requests are spaced at least five seconds apart. If an entire
pass finds no usable WS, the search waits ten seconds before trying another pass.
The rotation retains its exhausted flag and visited weapons during this wait;
it does not keep starting passes or switching weapons while waiting.
The explicit config fields `swap_delay` and `empty_pass_delay` override these
defaults (seconds, 0 disables that delay); shipped actions forward the matching
per-proc settings. New hints, selected weapon-set changes, or external weapon
changes release the exhausted-pass wait. Passes that found usable WS retain their
normal repeat behavior, and waiting for TP does not count as an empty pass.
Every dispatched attempt advances the rotation, including
missed, rejected, and uncertain attempts. Attempt history orders one pass; it
never eliminates candidates. Another pass starts when candidates are exhausted,
so previously used WS remain eligible until a hint excludes their element or a
confirmed red stagger applies the configured completion policy.

Proc hit tracking examines all direct WS results for the exact requested monster
ID, even when that monster is not first in an area-effect result packet. Damage
and drain messages count as confirmed landing; nearby targets' hits, misses,
no-effect messages, and unknown results do not establish a hit on that monster.
Confirmed landing does not prove a proc opportunity or remove that WS from future
passes. Generic WS lifecycle completion retains its existing meaning.

External main-weapon changes are read from confirmed equipment. A detected
external swap supersedes the rotation's pending swap wait and allows two seconds
for equipment/abilities to settle, retaining the current pass's attempt history. Queued proc
WS recheck the exact main item (including bag/slot identity) and live WS
availability at dispatch, as well as the current hint/stagger state. With the
default `"stop"` policy, switching to damage gear after a confirmed red proc
does not restart the search or request further proc weapon swaps. Before a proc,
external gear changes do not disable the configured rotation.

`abyssea.runRedProc(config)` requires a configuration object and executes one
rotation step, gated to Abyssea zones unless `allow_outside_abyssea=true`. For example:

```lua
abyssea.runRedProc(vars.my_red_search)
```

The argument's fields are `enabled` (optional boolean, default true), `weapons`
(the resolved array of equipment sets or main weapons), `all_ws` (optional red WS
candidate names, default the Abyssea catalog), `on_stagger` (`stop` or
`full_rotation`), and optional `ws_allow_list`/`ws_black_list` maps. An optional
`weapon_set_name` labels the supplied list for detecting a change of sets; it
does not resolve variable paths or named lists. The optional `state` table owns
the mutable `_rotation` progress; without it, progress lives on `config` itself.
Keep that owning table persistent between calls. Fresh argument objects can
share a caller-selected `state`, while different state tables run independently.
Action files own enabling and resetting the search. A hint narrows both weapon choices and
WS choices to its element for that monster. A character with no matching candidates
does not spend TP on unrelated WS. `abyssea.weaknesses` is a fresh copy of the
current battle target's observations (an empty `red` object when none exist).
`abyssea.getWeaknesses([target])` returns a copy of
the observed encounter state, defaulting to the battle target:
`{zone, id, index, red={element, triggered, actor}, yellow={element, triggered, actor}, blue={weapon_type, triggered, actor}}`. Fields are absent until
observed; `actor` is a name, when available. State clears on observed death,
despawn, deaggro, zoning, logout, or addon unload. Switching targets retains the
other living monster's hint. Action reloads retain observations. Ordinary monsters
and notorious monsters use the same process; there is no NM-only eligibility check.

Set `vars.abyssea.red_proc.on_stagger` to `"stop"` (default) to end red weapon
swaps and WS attempts after a confirmed red stagger. Other battle actions remain
eligible. Set it to `"full_rotation"` to discard the hint restriction after the
stagger and resume all red candidates. This policy does not restore damage gear;
configure that separately. `//gbtfn abyssea/red/use` enables/restarts a manual
search after engagement. When `bypass_auto_init` is true, battle initialization
disables the search until that command is run on the character.

Observations are collected independently of discovery recording across all nine
Abyssea zones. Shared `0x02A` decoding recognizes all eight hint elements and red
confirmation, using the appropriate zone-text offsets for Attohwa/Uleguerand.
The message definitions are referenced from LandSandBoat's Abyssea `IDs.lua`
files; Altepa's light/darkness hints and red confirmation also have live capture
coverage. Exact English hint/red-confirmation text correlated within one second
to a packet naming the monster remains a fallback. Unknown numeric messages do
not constrain the rotation. A generic stagger message alone is never treated as
a red proc. The Abyssea zone gates these observations; Visitant is not required,
so buff-list availability cannot suppress otherwise valid observations. Other
content's proc mechanics remain separate.

Gambit shares new observations over IPC with nearby clients in the same zone;
receivers verify the monster ID/index and never rebroadcast received updates.
This lets party members narrow their local search even if only one sees a hint.
Red, yellow and blue have separate hint and confirmation state on the same
observation interface.

Abyssea methods live on the `abyssea` object. The shipped actions store settings
in `vars.abyssea`; custom actions can supply any configuration location.

### Abyssea yellow proc search

All three proc runners accept `allow_outside_abyssea = true` for testing
weapon/weapon-skill and spell cycling elsewhere. It defaults to false. The
shipped actions pass `vars.abyssea.allow_outside_abyssea` to each runner, so one
shared setting enables this for red, blue and yellow. Hint and stagger detection
remain restricted to Abyssea; normal target, readiness and equipment checks
still apply. Red/blue mode selection and yellow initialization work as usual.

`abyssea.runYellowProc(config)` requires an explicit configuration object and runs
only in Abyssea zones unless `allow_outside_abyssea=true`. Required `spells` is an array of candidate spell names.
Optional fields are `enabled` (default true), `on_stagger` (`stop`, the default,
or `full_rotation`), `state`, `tools`, and `ws_allow_list`/`ws_black_list` target
maps (the same target filters as red). Without `state`, mutable `_yellow_rotation`
progress lives on the config itself. Keep the supplied state/config persistent;
red and yellow progress have separate fields even when sharing an owner table.

```lua
abyssea.runYellowProc({
    spells = vars.my_candidates,
    state = vars.my_search_state,
    on_stagger = 'stop'
})
```

The action file owns day selection and candidate lists; Lua never reads an action
variable path or invokes a named action function. The shipped `abyssea/yellow-proc`
actions preserve automatic yesterday/today/tomorrow initialization and the manual
`abyssea/yellow/show`, `use-today`, `use-yesterday`, and `use-tomorrow` functions.
`//gbtfn abyssea/yellow/use` initializes the combined yesterday/today/tomorrow pool
and resets yellow rotation progress. It shares the automatic initialization macro
and suppresses routine function lifecycle messages. It does not select or change
the red/blue weapon-proc mode.
Automatic initialization obeys `bypass_auto_init`; initialize manual pools after
engaging. Changing the selected spell-pool table or resetting `_yellow_rotation`
starts a new pass. A day change alone does not replace the pool mid-encounter.

Hints narrow candidates by the spell resource's actual element, including songs
such as Ice Threnody (fire element). If casting cannot proceed, a deduplicated
`YELLOW PROC waiting:` notice identifies readiness, range, or dispatch problems.
Routine active-action waiting appears only at debug verbosity.
The search skips spells that cannot currently
be cast, including cooldown, MP, job, learned-spell and assigned Blue Magic checks,
so an unavailable first candidate does not block ready candidates. Started casts
advance the pass; completed, interrupted and resisted/no-effect attempts are
eligible again on later passes. Requests that never start are not counted as
casts: search waits three seconds before another dispatch attempt and defers that
candidate for six seconds. Busy casting/ranged state suppresses new attempts.
Neither execution completion nor
damage is treated as proof of a yellow stagger. Only yellow confirmation stops
yellow search; red confirmation does not. With `full_rotation`, confirmation
removes the hint restriction and continues the supplied pool.

Ninjutsu is cast through the normal spell lifecycle rather than fire-and-forget
named functions. `tools[spellName] = {items={...}, bags={...}}` describes inventory
tools and optional toolbags. The search can open a configured usable bag when
inventory space allows, wait for inventory to update, and recheck tools. Missing
tools do not block other ready spells. The shipped action supplies the existing
Ni spell/tool mappings; the imported standalone ninjutsu functions remain
available for manual use. Configure any desired instruments or other casting
gear through ordinary spell event rules.

Both preparation and queued spell dispatch recheck the intended monster and
current yellow hint/stagger state. A new hint can cancel a queued spell outside
its element; a confirmed yellow stagger cancels queued search casts under `stop`.
Already dispatched casts cannot be recalled. Yellow hints and confirmation are
shared over IPC, so a hint received only by its caster can filter other clients'
searches. New hints and confirmed staggers print immediate `[abyssea]` messages
with the monster, element or triggering actor when known, and `[IPC]` for remote
observations. Red and yellow use the same `COLOR PROC search: element (monster).`
and `COLOR PROC confirmed on monster by actor.` wording. Confirmation is emitted
once by detection rather than repeated by the search loop. Duplicate
packet/text/IPC observations do not repeat these notices;
they are independent of whether a search action is currently running.
Live fixtures cover the fire hint on Sharabha and Stonega III yellow
stagger on Ansherekh; tests exercise the common offsets in all nine Abyssea zones.

### Abyssea blue proc search

`abyssea.runBlueProc(config)` requires an explicit configuration object with an
`all_ws` array containing candidates from one or more time windows. Other fields
match the red interface: `enabled`, `weapons`, `weapon_set_name`, `state`,
`on_stagger`, `ws_allow_list`, and `ws_black_list`. The helper is gated to Abyssea
unless `allow_outside_abyssea=true`;
it does not read action variable paths or choose time windows. State is stored in
`_blue_rotation` on `state` or the supplied config, independently of red/yellow.

Import `abyssea/blue-proc` to use the shipped pools. Automatic initialization
selects the current window at the beginning of battle actions, then freezes it:
06:00–13:59, 14:00–21:59, or 22:00–05:59. Weapon swaps and advancing the clock do
not change that selection mid-encounter. This is initialization time, not a
reconstruction of the monster's original claim/pop time. If initializing late,
the manual selectors can choose a different window:

```text
//gbtfn abyssea/blue/use
//gbtfn abyssea/blue/use-now
//gbtfn abyssea/blue/use-previous
//gbtfn abyssea/blue/use-next
```

`use` combines all three pools. `use-now` selects only the current window;
previous/next select the window eight hours earlier/later. All selectors enable
search and reset rotation progress. With `bypass_auto_init`, run a selector after
engaging. The action resolves configured per-proc/shared weapon sets before
passing an explicit config, just as the red action does.

Blue hints filter by weapon type (`weapon_type`, such as `great sword` or
`archery`), using the weapon-skill resource's skill ID. Unknown hint values do not
narrow the search. Red and blue share equipment confirmation, external-swap
settling, repeated passes, and intended-target WS result handling. Configured
sets may use `main`/`sub`, or `range`/`ammo`. Already equipped ranged weapons are
considered as well as the main weapon. Ranged attempts require ammunition and
guard both weapon and ammo identity at dispatch. Empty main equipment can expose
hand-to-hand candidates when the character's live ability list permits them.

Only blue-specific inability-to-use-special-attacks confirmation completes a
blue search. `on_stagger="stop"` (default) stops further rotation/attempts;
`full_rotation` removes the weapon-type hint restriction while retaining the
supplied time pool. Red/yellow confirmations do not stop blue. Detection and IPC
messages use the same wording and duplicate suppression as the other colors.

Blue packet IDs/type parameters are based on the Abyssea zone message reference
definitions, including Attohwa/Uleguerand's different offsets. Unit tests exercise
all types/zones, time boundaries, IPC, ranged ammo guards and completion policies.
There is no live blue discovery fixture yet; capture a blue hint and successful
stagger using the existing recorder to verify in-game behavior.

### Weapon-skill execution results

`local completed, result = useWeaponSkill(name)` waits for execution and returns
the existing completion boolean plus a result object. A completed miss returns
`true` with `result.completed == true` and `result.missed == true`. Inspect
`result.landed` when the effect on the requested target matters. Result fields
include `outcome`, `target_id`, `completed`, `interrupted`, `failed`, `cancelled`,
`dispatched`, `started`,
`timed_out`, `effect`, `landed`, `missed`, `no_effect`, and per-target `results`.
Failure, cancellation, and timeout preserve their execution outcome independently
of effect classification. Range rejections are failures, not confirmed misses.
The shared observer classifies target effects once for both waits and post events.
Abyssea's internal strict landing option affects its success boolean, while the
returned execution outcome remains separate. Other callers retain completion
semantics and can optionally consume the second result value.

### Multi-stage compilation

`compileMultiStage(config)` prepares a multi-stage weapon-skill plan without
checking combat readiness or selecting a weapon skill. It returns `true` for a
valid nonempty stage list, including when the cached plan is current, and `false`
when no stages are defined. Errors use the normal action error handling.

The `ws/multi-stage` library includes an `on_load` action named
`multi-stage-compile` after its settings initialization. The existing opener and
closer checks still compile on demand and refresh plans after roster or
capability changes. Initial compilation may exclude characters whose capability
replies have not arrived yet; later evaluation refreshes the plan. Loading actions
run when automation is enabled and eligible to process them.

### Explicit battle-target selection

setBattleTarget(mob, engage) accepts a mob object or numeric entity ID. The optional engage flag defaults to true for the existing acquisition behavior. Passing false updates only Gambit's tracked battle target when the pending request is processed: it does not change the cursor, issue an attack, broadcast a target, or run the legacy acquisition waits. Invalid/dead targets are rejected. Use explicit phase-gated engagement actions afterward; if switching away from a currently attacked enemy, disengage explicitly before selecting the new one.
