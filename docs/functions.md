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
