# Configurable encounter state

`encounters` is available in action, event, and panel expression contexts. It
observes configured monster names and exposes state; it never sends actions or
assigns meaning to a phase. All names, transitions, and combat policy belong in
JSON. Unconfigured encounters add no tracked records.

Tracker definitions are reset when actions are recompiled, including namespace
changes. Register them in loading actions so the current configuration owns their
lifetime. Zone changes clear observations while retaining the loaded definitions.

An actor may define `"text_aliases": ["The boss"]` for messages that use a
generic label instead of its name. Aliases are literal, case-sensitive matches
and apply only to that actor in that tracker. Text is ignored when multiple
living actors with the same configured name are visible.

Register a definition from a loading action:

```json
{
  "vars": {
    "sentinel_tracker": {
      "actors": {
        "Example Sentinel": {
          "initial": {"mode": "idle", "hits": 0},
          "rules": [
            {"kind": "text", "contains": "raises its shield", "set": {"mode": "guarded"}, "reset": {"hits": 0}, "only_on_change": true},
            {"kind": "enemy_ability", "names": ["Shield Break"], "phase": "post", "outcome": "completed", "set": {"mode": "open"}},
            {"kind": "party_weapon_skill", "when": {"mode": "open"}, "increment": {"hits": 1}, "timestamp": "hit"}
          ]
        }
      },
      "conditions": {
        "attack": "encounter.mode == 'open' and encounter_config.actor == me.name"
      }
    }
  },
  "loading": [
    {"commands": ["encounters.configure('sentinel', vars.sentinel_tracker, {actor='PlayerName'})"]}
  ]
}
```

| API | Behavior |
| --- | --- |
| `encounters.configure(name, definition, parameters)` | Validate and copy a definition and optional policy parameters; replace that tracker's state. |
| `encounters.state(name, target)` | Return a copied snapshot and store it as context `encounter_state`, or clear that value to nil for an unknown tracker/actor. Target defaults to `bt`. |
| `encounters.evaluate(name, condition, target)` | Evaluate a named configured condition in the calling context; false for an unknown tracker, condition, or actor. |
| `encounters.remove(name)` | Unregister a tracker and discard its state. |

Snapshots include configured fields plus `id`, `index`, `name`, `revision`, and
`ages`. A rule with `"timestamp": "hit"` sets `snapshot.ages.hit` to zero;
subsequent snapshots report elapsed seconds from the monotonic clock. The age
is absent until observed. Initial field values apply when an actor is first
seen; they do not reconstruct an encounter already in progress.

Named conditions are ordinary Lua action expressions. They receive the snapshot
as `encounter`, the supplied target as `encounter_target`, and copied registration
parameters as `encounter_config`. Normal context symbols such as `me` remain
available. This lets JSON define policies such as ordered WS turns without Lua
knowing their purpose. Snapshots and parameters cannot mutate the stored tracker.

Rules run in order. Supported `kind` values:

- `text`: incoming original English/localized text containing the actor's exact
  name and the configured literal `contains` substring. No Lua pattern matching.
  Same-name live actors make chat attribution ambiguous, so those messages are
  ignored rather than applied to every matching actor.
- `enemy_ability` / `enemy_spell`: decoded observations; optional `names` (string
  or array), `phase` (`pre`/`post`), and `outcome` constrain the match.
- `auto_attack`: an observed category-1 action by the configured actor.
- `action_message`: a decoded action-result message on the configured target.
  Optional `messages` lists numeric message IDs; high-bit flags are removed.
  Primary, additional-effect, and spike-effect messages are considered, once
  per distinct message ID per target/action. JSON decides what a message means.
- `party_weapon_skill`: an observed category-3 action targeting the configured
  actor, performed by self, a party member, or an alliance member. One increment
  per target per action; this observes results, not queued requests or proven hits.

Optional `when` fields match current state values by equality. `set` replaces
fields; `reset` replaces fields and clears their matching clocks; `increment`
adds numeric amounts; `timestamp` records the current time. `only_on_change`
applies effects only if at least one `set` field changes, preventing duplicate
phase messages from reopening a turn sequence. `stop` stops later rules for the
same actor/observation. Field maps contain named scalar values.

Optional `after` maps clock names to minimum elapsed seconds. For example,
`"after": {"recovery": 4}` matches only if a `recovery` timestamp was observed
at least four seconds ago. It gates an actual observation; it does not schedule
a timeout or synthesize a completion. Use `when` alongside it to require a
completed lifecycle before a later auto-attack can release a hold.

Observations are local to each client. All cooperating clients must register the
same definitions and receive the same packets/messages. There is no inferred
completion, polling timeout, cross-client synchronization, or damage suppression.
Missing observations must be handled conservatively by JSON policy.

Records reset on zone departure/logout, observed invalid/dead targets, and entity
identity changes. Definitions remain registered until replaced, removed, or the
addon reloads. Namespace authors should unregister trackers when explicitly
switching to a different policy if continued observation is unwanted.

The Dullahan namespace demonstrates phase transitions, a next-auto-attack gate,
and ordered WS counters entirely through `actions/lib/dullahan/setup.json`.

Definitions may list configured condition names in latch_conditions. Once one of those conditions evaluates true for a monster, it stays true for that monster's encounter record. Reconfiguration, removal, death/invalidity, identity changes, and zone/logout cleanup reset the latch. Do not latch an absorption or damage-phase condition that must remain live. Conditions can call encounter_test('other_condition') to compose named conditions in the same tracker and calling context; circular references are rejected. Dullahan uses this only for the one-time pull release, while can_ws continues to check current phase and absorption state.
