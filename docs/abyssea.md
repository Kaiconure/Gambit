# Abyssea interface for custom actions

The action context exposes `abyssea.getWeaknesses`, `abyssea.weaknesses`,
`abyssea.runRedProc`, `abyssea.runBlueProc`, and `abyssea.runYellowProc`.
Use these names directly in action expressions; in Lua code that has a context
object, they are available on `context.abyssea`. Call them with dot syntax.

The runners receive explicit configuration. They do not read `vars.abyssea`,
resolve named action files, or require the shipped proc imports. Your action file
owns candidate lists, scheduling, configuration storage, and mode selection.
Detection runs independently and does not require discovery recording.

Gambit already ships the full red and blue proc weapon-skill pools and yellow
proc spell pools in [red-proc.json](../actions/lib/abyssea/red-proc.json),
[blue-proc.json](../actions/lib/abyssea/blue-proc.json), and
[yellow-proc.json](../actions/lib/abyssea/yellow-proc.json). These files should
typically be the starting point for your own rules: reuse or adapt their
candidate lists, blue time-window selection, and yellow day selection, then
customize the conditions, equipment, and scheduling for your setup. The small
pools below illustrate the API; they are not complete proc lists. A character's
usable candidates still depend on job, level, equipment, spells, and tools.

## A complete custom action file

This example searches red with the current weapon and also tries a small yellow
spell pool. The pools are deliberately small; replace them with your desired
candidates. Import this file in your namespace's **battle** actions.

```json
{
  "vars": {
    "custom_procs": {
      "weapon_mode": "red",
      "outside_testing": false,
      "red_state": {},
      "yellow_state": {},
      "red_skills": ["Cyclone", "Energy Drain"],
      "yellow_spells": ["Stone", "Stonega III", "Fire IV"]
    }
  },
  "actions": [
    {
      "when": ["bt", "vars.custom_procs.weapon_mode == 'red'"],
      "commands": [
        "abyssea.runRedProc({state=vars.custom_procs.red_state, all_ws=vars.custom_procs.red_skills, is_active=\"vars.custom_procs.weapon_mode == 'red'\", allow_outside_abyssea=vars.custom_procs.outside_testing})"
      ],
      "frequency": 2,
      "scope": "battle"
    },
    {
      "when": ["bt"],
      "commands": [
        "abyssea.runYellowProc({state=vars.custom_procs.yellow_state, spells=vars.custom_procs.yellow_spells, allow_outside_abyssea=vars.custom_procs.outside_testing})"
      ],
      "frequency": 6,
      "scope": "battle"
    }
  ]
}
```

Each call advances the search rather than running an entire rotation in one
call. Schedule repeated calls through ordinary actions. Do not treat a runner's
return value as proof of a proc; consult observations instead. Casting and weapon
skill execution still use Gambit's normal action lifecycle.

Keep the supplied `state` table persistent across calls. A fresh configuration
object on each call is fine when it references that persistent table. Without
`state`, the configuration object itself must persist. Keep yellow's `spells`
table stable too: replacing it resets its iteration. All runners reset their
progress when the selected monster ID/index changes.

## Shared configuration

| Field | Default | Meaning |
| --- | --- | --- |
| `state` | Config object | Table owning mutable search progress. |
| `enabled` | `true` | `false` disables this runner. |
| `on_stagger` | `"stop"` | Stop on this color's confirmed stagger. `"full_rotation"` removes the hint restriction and continues the supplied pool. |
| `allow_outside_abyssea` | `false` | Allow cycling outside Abyssea for testing. Does not enable detection there. |
| `ws_allow_list` | Unrestricted | Target-name map, e.g. `{["Ansherekh"]=true}`. If supplied, a target must have a truthy entry. An empty map allows nothing. Applies to yellow as well. |
| `ws_black_list` | None | Target-name map; truthy entries exclude targets. |

Hints and confirmed staggers are separate for each color. A red stagger does not
complete yellow or blue. Ordinary monsters and NMs follow the same process.
`stop` does not restore damage weapons or casting gear; use your other actions
or event rules to do that.

## Red and blue weapon searches

Define each runner's arguments in `vars` and pass that table from a command.
This action file selects one weapon search at a time through `my_weapon_mode`.
Replace the sample blue skills with your chosen time-window pool.

```json
{
  "vars": {
    "my_weapon_mode": "red",
    "my_search_enabled": true,
    "my_red_proc": {
      "state": {},
      "weapons": [{"main": "Bronze Dagger"}, {"main": "Bronze Sword"}],
      "on_stagger": "stop",
      "is_active": ["vars.my_weapon_mode == 'red'", "vars.my_search_enabled"]
    },
    "my_blue_proc": {
      "state": {},
      "all_ws": ["Fast Blade", "Burning Blade"],
      "weapons": [{"main": "Bronze Sword"}],
      "is_active": ["vars.my_weapon_mode == 'blue'", "vars.my_search_enabled"]
    }
  },
  "actions": [
    {
      "when": ["bt", "vars.my_weapon_mode == 'red'", "vars.my_search_enabled"],
      "commands": ["abyssea.runRedProc(vars.my_red_proc)"],
      "frequency": 2,
      "scope": "battle"
    },
    {
      "when": ["bt", "vars.my_weapon_mode == 'blue'", "vars.my_search_enabled"],
      "commands": ["abyssea.runBlueProc(vars.my_blue_proc)"],
      "frequency": 2,
      "scope": "battle"
    }
  ]
}
```

| Field | Default | Meaning |
| --- | --- | --- |
| `all_ws` | Red's 13-skill catalog; required for blue | Array of WS names. Red filters it against its catalog; blue uses the supplied pool and filters hints by weapon type. |
| `weapons` | No configured rotation | Array of item references or equipment sets. Sets can include `main`/`sub`, or blue `range`/`ammo`. Items must be owned, accessible to the equipment resolver, and usable by the current job/level. |
| `weapon_set_name` | None | Label used to recognize a selected set change; does not resolve a variable or list. |
| `is_active` | Always active | Expression string or array of expression strings, re-evaluated during search and before queued WS dispatch. Arrays short-circuit with AND; an empty array is false. Lua callbacks are also supported. |
| `swap_delay` | `5` | Minimum seconds between swap requests. |
| `empty_pass_delay` | `10` | Seconds before retrying a pass with no usable skills or an incomplete equipment probe. |
| `refresh_delay` | `2` | Seconds to wait after confirmed equipment changes before checking skills. |
| `equip_timeout` | `10` | Seconds to wait for a requested weapon to be confirmed. |

For several activation conditions, use an array just as with action conditions:

```json
{
  "is_active": ["vars.my_weapon_mode == 'blue'", "vars.my_search_enabled"]
}
```

Expressions use the calling action context and are evaluated again before a
queued WS is sent. Passing the expression text preserves that live check; the
configuration does not accept a captured boolean for `is_active`.

Timing fields accept numbers from 0 to 3600 seconds. Zero disables that delay.
The current weapon is checked first; omitting `weapons` supports current-equipment
searches. Blue can also consider equipped ranged gear; ranged WS require ammo.
The live available-skill list is checked after swaps settle. A suitable weapon
waiting for TP does not count as an exhausted pass or force another swap.

Custom blue callers must select their own time-window pool. The runner does not
derive a pool from the game clock. Custom yellow callers likewise own day-based
selection. The shipped action files contain the full pools and selectors if you
want to reuse those policies instead of maintaining your own.

Run one red/blue equipment search at a time to avoid competing swap requests.
Core Lua imposes no shared mode variable: your conditions and `is_active`
conditions own that decision. Yellow can run alongside either weapon search.

Candidates repeat on later passes, including previously attempted skills.
Misses or uncertain results do not permanently eliminate a candidate. A landed
WS is not itself proof of a stagger. Queued requests recheck the monster,
weapon identity, candidate availability, hint, and completion policy. External
weapon changes are observed and allowed to settle; a confirmed stagger under
`stop` prevents the runner swapping back to proc weapons afterward.

## Yellow spell searches

```json
{
  "vars": {
    "my_yellow_proc": {
      "state": {},
      "spells": ["Stone", "Fire IV", "Katon: Ni"],
      "tools": {
        "Katon: Ni": {
          "items": ["Uchitake"],
          "bags": ["Toolbag (Uchi)"]
        }
      }
    }
  },
  "actions": [
    {
      "when": ["bt"],
      "commands": ["abyssea.runYellowProc(vars.my_yellow_proc)"],
      "frequency": 6,
      "scope": "battle"
    }
  ]
}
```

`spells` is a required array of spell names. It is your candidate pool, not an
instruction to cast every spell immediately. The helper skips unavailable
spells, checks range and readiness, and narrows candidates using the spell
resource's actual element. Spell names alone can be misleading: Ice Threnody
is a fire-element candidate.

Optional `tools` maps spell names to inventory `items` and optional tool `bags`.
The helper can open a usable bag when inventory space permits, then recheck
tools. Missing tools do not block other candidates. Configure casting gear and
instruments through ordinary spell event rules.

Started casts advance the pass; candidates become eligible again on later
passes. Requests that never start back off rather than rapidly consuming the
pool. A completed, resisted, or interrupted cast does not establish a proc.

## Reading observations and resetting progress

Store observations with `setVar` inside action commands. The no-argument call
uses Gambit's selected battle target; this example also passes `bt` explicitly.

```json
{
  "vars": {
    "my_observations": {}
  },
  "actions": [
    {
      "when": ["bt"],
      "commands": [
        "setVar('vars.my_observations.observed', abyssea.getWeaknesses())",
        "setVar('vars.my_observations.other', abyssea.getWeaknesses(bt))",
        "setVar('vars.my_observations.current', abyssea.weaknesses)"
      ],
      "frequency": 2,
      "scope": "battle"
    }
  ]
}
```

`getWeaknesses` returns nil when no observation exists. Otherwise its copied
record has this shape (individual fields are absent until known):

```json
{
  "zone": 218,
  "id": 12345,
  "index": 100,
  "red": {"element": "wind", "triggered": true, "actor": "PlayerName"},
  "yellow": {"element": "fire"},
  "blue": {"weapon_type": "great sword"}
}
```

`abyssea.weaknesses` always supplies `red`, `yellow`, and `blue` tables, even
when nothing is known. Both APIs return copies; changing them does not change
detection state. Hints/staggers arrive through observations and IPC independently
of which searches are enabled. Detection is restricted to Abyssea zones and does
not require Visitant. Backline characters need not be melee-engaged: runners use
Gambit's selected monster, not the game's melee battle-target pointer.

Progress lives in `state._rotation` (red), `state._blue_rotation` (blue), or
`state._yellow_rotation` (yellow). To restart iteration, clear the corresponding
field, for example with this action (using the weapon-search variables above):

```json
{
  "when": ["bt"],
  "commands": ["setVar('vars.my_red_proc.state._rotation', nil)"],
  "frequency": "infinity",
  "scope": "battle"
}
```

This resets red iteration once per battle. It does not
erase observations: a known stagger still stops a restarted search under `stop`.
Observations clear with encounter cleanup or zoning; action reloads retain them.

## Using the shipped actions instead

The shipped files provide complete proc candidate pools as well as ready-made
rules. You can import them directly or use them as the basis for custom actions.

Import `abyssea/red-proc`, `abyssea/blue-proc`, or `abyssea/yellow-proc` in battle
actions for their built-in initialization and candidate pools. Their convention
is `vars.abyssea.weapon_proc`: `"red"`, `"blue"`, or anything else for neither.
Yellow is independent. These paths are action-file conventions, not core API
requirements.

Manual commands after battle begins:

```text
//gbtfn abyssea/red/use
//gbtfn abyssea/blue/use
//gbtfn abyssea/blue/use-now
//gbtfn abyssea/blue/use-previous
//gbtfn abyssea/blue/use-next
//gbtfn abyssea/yellow/use
//gbtfn abyssea/yellow/use-today
//gbtfn abyssea/yellow/use-yesterday
//gbtfn abyssea/yellow/use-tomorrow
```

Blue `use` combines all three eight-hour pools; `use-now`, `use-previous`, and
`use-next` select only the current, previous, or next pool. Automatic blue
initialization selects the current pool once per battle. Yellow
`use` combines yesterday/today/tomorrow; the other selectors choose one day.
Per-color `bypass_auto_init` controls automatic initialization. To test outside
Abyssea with these imports, set `vars.abyssea.allow_outside_abyssea` to `true`.
Set it back to `false` when finished. Normal MP, TP, tools, equipment, and target
requirements still apply; no hint or stagger will complete the search there.

See [the function reference](functions.md#abyssea-red-proc-search) for more
implementation and result-handling details, and [equipment](equipment.md) for
item-reference formats.
