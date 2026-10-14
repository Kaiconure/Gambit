# Action Functions

The following functions are available for use in your actions. They are broken down by broad category, and they can all be used in both the `when` condition or in the actual action `commands` -- though some may make more sense in one versus the other.



## Optional selector ordering

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

`align(target, angle, distance, duration, noFace)` supports exact angles and flexible positioning. The same angle values work with `aligned` and `aligning`, and with `vars.frontline_engagement.angle` in `frontline-engagement`.

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

For flexible ranges, the first preferred angle is randomized and remembered on the executing action for the current battle scope, target, and angle specification. A later successful fallback becomes the preference. If already at the requested distance anywhere in an allowed arc, no repositioning is needed. This reduces clustering but does not coordinate character positions or guarantee separation.

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

## Evaluating reusable conditions


`evaluateAll(conditions, ...)` returns a boolean. A string is evaluated through the existing execution cache; an array evaluates each condition in order and stops at the first falsy result. Boolean inputs are used directly, numbers are truthy (including zero), and both `nil` and an empty array return false. Arrays must be contiguous; nested arrays are not supported. Expression errors propagate to the action guard.

Use `evaluateAllConditions(vars.idle_precondition)` for an optional reusable list of requirements, or `not evaluateAllConditions(vars.primary_tank_precondition)` for its inverse. Strings returned by expressions are treated as values, not executed recursively.

`execute` remains unchanged: it evaluates every expression in an array and returns the final expression's results, rather than combining them with AND.

`evaluateAllConditions(conditions, ...)` is the optional-condition variant: `nil` or an empty array returns `true` (no restrictions). All other inputs delegate to `evaluateAll`, preserving explicit `false`, short-circuiting, argument forwarding, and validation of malformed tables. An expression that returns `nil` still fails. For example, `evaluateAllConditions(vars.idle_precondition)` permits execution when the policy is absent, while respecting a policy explicitly set to `false`.
