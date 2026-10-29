# Event rules (initial implementation)

Event rules respond to the local player's outgoing spells, job abilities, and
weapon skills. They are independent of the normal action-selection cycle and
run even when Gambit automation is disabled. No event files means no requests
are intercepted. Imports and aggregation helpers are not implemented yet.

## Files and precedence

Exactly one event file is selected: the first existing candidate in this order.
Rules from other event files are not merged. Event variables can be layered
separately using `.vars.json` files.

1. Search the active namespace, then inherited namespaces from closest to furthest,
   then global settings.
2. Within each scope, search the character's event directory before the shared
   event directory.
3. Within each directory, try `<job>.json`, matching positive group/leader files,
   matching inverse group files, then `common.json`. Smaller job groups win;
   inverse selectors use the size of their complement across all 22 jobs. Ties
   are alphabetical. `(leader)` retains its former alphabetical slot among
   matching positive selectors. Action entry points use the same group ordering.

For example, global character rules live at `settings/Carbonite/events/pld.json`;
shared global rules live at `settings/events/pld.json`. Named namespaces use
`settings/_ns/<namespace>/players/Carbonite/events/` and
`settings/_ns/<namespace>/events/`. Scope takes priority over filename specificity:
a namespace shared/common file can beat a global character/job file. Likewise a
character/common file beats a shared/job file within the same scope.

Job filenames are lowercase (`rdm.json`); character casing follows existing
settings. Groups reuse target-selector memberships, such as `(melee).json`,
`(mages).json`, `(healer).json`, and aliases. `(~mages).json` matches jobs outside
that group. `(leader).json` applies when party leader at reload time. Only one
matching group file wins; important selectors such as `(!mages)` and inverse
leader selectors are not supported. Leadership changes require an event reload.
`events` remains reserved and is not discovered as a namespace.

An empty selected file intentionally disables lower-priority configurations.
An invalid selected file reports an error rather than falling back. Loading or
reloading events reports `Active event file: <path>`, or that no matching file
exists. Use `gbt events` or `gbt events status` to view the currently active path.
Loading and status output also list contributing variable files, most specific first.

## Event variable files

Alongside rule files, each applicable event directory may contain `geo.vars.json`,
`(mages).vars.json`, `common.vars.json`, or other matching job/group selectors.
All existing matches are loaded across the active namespace, inherited namespaces,
and global settings, including character event directories. They follow the same
specificity order above, independently of which single rule file wins.

Variable files contain only a `vars` object; rules, imports, and other top-level
keys are rejected:

```json
{
  "vars": {
    "gear": {
      "enfeebling": {"ring1": {"name": "Stikini Ring"}}
    }
  }
}
```

The normal variable loader merges these values: more specific definitions win at
equal priority, nested objects merge, and arrays use the winning definition.
Explicit `!` priorities, `^` defaults, and normal clearing markers are supported.
Inline `vars` in the selected rule file have implicit `^` priority, inherited by
their children unless explicitly prefixed. They provide fallback values; explicit
`!` and `^` retain their normal meaning. Prefixes are stripped during loading.
An invalid variable file fails the reload and preserves the previous configuration.
Use `gbt events reload` to reload rules and their variable files together.

`gbt events reload` reloads only event files, without recompiling normal actions
or resetting their variables. `gbt reload` (also `gbt r`) reloads event files
along with normal settings. Job and namespace
changes also reload them. The loader compiles the selected file before replacing the
active event configuration; an invalid file reports an error and retains the
last successfully loaded event configuration. Reloading terminates pending
requests with outcome `reloaded`, using their old rules for cleanup.

## Configuration

```json
{
  "vars": {
    "convert_min_hpp": 25
  },
  "job_abilities": {
    "pre": [
      {
        "id": "prevent-unsafe-convert",
        "when": [
          "event.name == 'Convert'",
          "me.hpp < vars.convert_min_hpp"
        ],
        "commands": ["cancelEvent('HP too low for Convert')"]
      }
    ],
    "post": [
      {
        "when": ["event.outcome == 'cancelled'"],
        "commands": ["setVar('last_cancel_reason', event.reason)"]
      }
    ]
  },
  "spells": {
    "pre": [],
    "mid": [],
    "post": []
  },
  "weapon_skills": {
    "pre": [],
    "mid": [],
    "post": []
  }
}
```

All sections and phases are optional. Each phase contains a dense array of rules.
Rules may include a `comment` field with any JSON value, typically a string or
an array of strings. Comments are stripped from compiled rules, never validated
or evaluated as Lua. Comment-only entries such as
`{"comment": ["Burst gear rules below", "More notes here"]}` may appear anywhere
in a phase array and are skipped entirely. Comments may also accompany executable
rules without changing their behavior. Error locations retain original array indices.
Each section may also set `"use_equipment_snapshot": true` (default: false).
Every lifecycle captures effective equipment before any `pre` rules and places
that baseline at the bottom of its own `equipPush`/`equipPop` stack, regardless
of this flag. It includes queued changes and known empty slots. Balanced explicit
push/pop pairs behave as usual; one additional pop restores and removes the
baseline. Further pops on an empty stack do nothing.
With the flag enabled, cleanup restores the baseline after `post` only if it
remains on the stack, even when explicit pushes were left unbalanced. A consumed
baseline is never restored twice or replaced by a later explicit push.
Restoration also runs on cancellation, interruption,
failure, timeout, and lifecycle cleanup such as reload; handler errors cannot skip
the restoration attempt. If capture fails, the action is blocked before rules run.
All remaining stack entries are discarded at lifecycle end. With the flag off,
discarding entries does not restore gear. With it enabled, gear selected in
`post` is restored afterward if the baseline remains; pop it explicitly before
selecting final gear to retain those later changes.
For example, `"spells": {"use_equipment_snapshot": true, "pre":
[{"when": ["event.element_name == 'Dark'"], "commands":
["equip('head', 'Pixie Hairpin +1')"]}]}` needs no manual push or post pop.
Use `spells`, `job_abilities`, and `weapon_skills` as section names.
`canMagicBurst(spell, target)` is available in both normal actions and event rules.
It accepts a spell resource, spell name/ID, or spell event (for example,
`"when": ["canMagicBurst(event)"]`). The target is the explicit mob object/ID,
otherwise the input object's target, otherwise `bt`. It checks the target's
tracked skillchain window (currently 7.75 seconds) and compatible spell element.
It does not check MP, recast, range, or predict whether the spell will land before
the window closes. Non-spell events and unknown spells/targets return false.
`isEnfeeblingSpell(spell)` accepts the same spell inputs and tests the resource's
Enfeebling Magic skill classification, for example `"when": ["isEnfeeblingSpell(event)"]`.
It is available to normal actions as well. Other skills' debuffs (such as Dark
Magic, Ninjutsu, or Blue Magic spells) are not classified as Enfeebling Magic.
Equivalent helpers are `isDivineSpell`, `isHealingSpell`, `isEnhancingSpell`,
`isElementalSpell`, `isDarkSpell`, `isSummoningSpell`, `isNinjutsuSpell`,
`isSingingSpell`, `isBlueSpell`, and `isGeomancySpell`. All accept the same inputs.
The generic `spellHasSkill(spell, skill)` accepts a numeric skill ID or a key
from `meta/magic-skills.lua`, such as `spellHasSkill(event, 'enhancing')`.
These classify magic skills, not elements: `isDarkSpell` means Dark Magic skill,
not every Dark-element spell.
`isCureSpell(spell)` accepts the same name/ID/resource/spell-event inputs and
identifies Cure I-VI, Curaga I-V, Cura I-III, and Full Cure. It requires Healing
Magic skill and uses the IDs in `meta/cure-spells.lua`, independently of client
language. Other healing spells (status removal, Raise, Regen, etc.) do not match.
Spell events expose the same classification as boolean `event.curing`, for example
`"when": ["event.curing"]`; non-spell events have no `curing` flag.
`event.kind` remains singular (`weapon_skill`), like `spell` and
`job_ability`.
`when` and `commands` accept a string or an array of strings. Conditions are
evaluated in order with AND/short-circuit semantics; an omitted/empty `when`
matches unconditionally. Every matching rule runs in file/array order. Command
return values do not stop processing. A matching rule with `"stop": true`
ends processing of the current phase after its commands.
For conditional stopping inside commands, call `stopEvent()` (or
`stopEvent(false)`). The current rule's remaining commands still run, but later
rules in this phase are skipped. Other phases are unaffected. `stopEvent(true)`
also calls `cancelEvent()` and is valid only in `pre`; normal `post` cleanup still
runs. For example, `"commands": ["someCondition and stopEvent(true)"]` cancels
and stops only when that condition is true. The optional flag must be a boolean.

Rules execute in array order in the selected file. A later rule with the same
optional `id` replaces an earlier rule within the same section and phase, at the
later rule's position. A disabled same-ID rule removes that earlier definition.
IDs are not runtime first-match groups. Errors identify the source file, section,
phase, and array position.

## Context and variable isolation

Rules have the usual temporary Gambit context (including `me`, party symbols,
condition helpers, and equipment helpers) plus these event fields:

| Field | Meaning |
|---|---|
| `event.kind` | `spell`, `job_ability`, or `weapon_skill` |
| `event.phase` | `pre`, `mid`, or `post` |
| `event.id`, `event.name` | Resource ID and English (`en`) name of the triggering action, independent of client language |
| `event.type` | Resource type, such as `CorsairRoll` or `WhiteMagic`; nil if absent |
| `event.element` | Resource element ID; nil if absent |
| `event.element_name` | English element name, such as `Fire`; nil if unavailable |
| `event.skill`, `event.skill_name` | Resource skill ID and English skill name, such as `Enfeebling Magic`; nil if unavailable |
| `event.divine`, `.healing`, `.enhancing`, `.enfeebling`, `.elemental`, `.dark`, `.summoning`, `.ninjutsu`, `.singing`, `.blue`, `.geomancy` | Spell skill classification booleans; absent on non-spell events |
| `event.target.id`, `.name`, `.index` | Selected target snapshot; name can be nil |
| `event.actor_id` | Local player ID |
| `event.request_id` | Request identifier within this event configuration |
| `event.time` | Time the outgoing request was intercepted (`os.clock()`) |
| `event.injected` | Whether the original outgoing request was injected |
| `event.cancelled`, `event.reason` | Sticky cancellation state and optional reason |
| `event.source`, `event.rule_id` | Current rule's source label and optional ID |
| `event.outcome`, `event.completed_at` | Terminal outcome/time; post phase only |
| `event.completed`, `.interrupted`, `.failed`, `.timed_out` | Post-only booleans matching outcomes `completed`, `interrupted`, `failed`, and `timeout`; false for other outcomes |

For example, `"when": ["event.interrupted"]` selects interrupted spells in
`post`. These flags are derived from `event.outcome`; they are nil during `pre`
and `mid`. `event.cancelled` remains available throughout the lifecycle, becomes
true immediately on local cancellation, and is also true for a `cancelled` post
outcome. Cleanup outcomes such as `reloaded` or `zoned` leave the four post-only
flags false; use `event.outcome` to distinguish those cases.

This is the triggering action, regardless of what action-selection helpers put
in `spell`/`ability` or what `gambit.last_spell` contains. Event metadata is a
snapshot; changing it does not retarget or rewrite the outgoing packet.
Action, element, and skill names always use resource English names. The event
interface has no `en` or `ja` fields; use `event.name` in conditions. Target names
remain the observed in-game names. For example, `"when": ["event.enfeebling"]`
selects Enfeebling Magic spells. Flags describe skills, not spell elements.
The additional skill flags `stringed_instrument`, `wind_instrument`, and
`handbell` reflect the spell resource's skill field only; they do not inspect
equipment. Song spell resources normally classify as `singing`.

`vars` comes from the selected file's defaults and matching event variable files.
Variables from other rule files and normal Gambit actions are not included. Each request gets
its own copy; mutations persist across
its rules and phases, but not to the next request or disk. Variable helpers,
including `getVarGlobal`/`setVarGlobal`, operate on this isolated store. `_` is
reserved for per-request equipment-stack bookkeeping.

Use `equipPush(...)` in pre and a corresponding `equipPop()` in post for restoration
when appropriate. Match the same action in both phases, and handle every terminal
outcome rather than only successful completion. The per-request stack prevents
one event's restoration from popping another request's stack; overlapping gear
changes can still compete, so keep equipment ownership simple.
`equipPush()` saves all known effective slots without equipping anything.
`equipPush(gear)` saves that full snapshot before applying gear. Pop queues the
latest snapshot through the shared [equipment manager](equipment.md), including
originally empty slots and changes made by subsequent `equip`/`equipMany` calls.
Pending swaps are visible to subsequent equipment queries,
so a quick post does not mistake stale equipment cache data for current gear.
If a recorded bag slot now holds a different item, it is not used as a substitute.

Equipment requests are collected per phase: later matching rules override earlier
requests for the same slot, and one final batch is committed at phase completion.
Queries within the phase see that local plan; normal actions retain immediate
submission through the shared manager. Rule errors discard the whole phase's
gear plan, and pre cancellation does likewise. Equipment-stack edits from a
discarded phase are rolled back so post does not pop uncommitted pushes. Other
command side effects are not transactional. See [phase batching](equipment.md).

## Dispatch, cancellation, and outcomes

`pre` runs before release of the outgoing request. `cancelEvent(reason)` is valid
only during that request's active pre phase. It returns true and permanently
marks the request cancelled; later rules cannot undo it. It does not stop rule
processing. Later rules may use `not event.cancelled` to skip unwanted work.
Cancellation generates exactly one local `post` with outcome `cancelled`.

For action types with rules, the original request is blocked and an allowed
request waits behind an equipment barrier reserved immediately after pre commits.
There is no fixed delay when the equipment manager is available. Pre gear must
be acknowledged before dispatch. Equipment failure withholds dispatch and produces failed
post cleanup. The target is resolved again before dispatch;
invalid/disappeared targets result in `failed`. `mid` runs immediately after
dispatch, not when the server announces cast start. Instant abilities and weapon
skills generally need their equipment in pre; spells can use mid for casting gear.

Result packets complete matching requests by kind/resource ID. Spell interruption
terminates the oldest dispatched spell request. Local post outcomes are:

- `completed`: matching server action result observed (not proof the effect landed).
- `interrupted`: spell interruption observed.
- `cancelled`: local pre cancellation, pre-rule failure, or request-limit rejection.
- `failed`: dispatch failure or a recognized server rejection.
- `timeout`: no correlated terminal result within 120 seconds.
- `reloaded`, `zoned`, `logout`, `unloaded`: lifecycle cleanup before a terminal result.

Only one post is issued per captured request. Server rejection messages sometimes
lack a reliable action ID; this first pass associates known rejection messages
only when one dispatched request is pending. Other failures time out. Pending
requests are bounded at 16. A repeated attempt with the same kind, resource ID,
and selected target is blocked while that request is pending, without running
pre again or pushing equipment a second time. Message IDs are normalized to
remove the high-bit flag; known same-roll and recast rejections trigger failed
post cleanup even if another addon suppresses the message packet's display.
Pre still runs for a new attempt the server may reject: it is not an ability
readiness or successful-use notification. Cancelling after dispatch is not supported.

## Constraints and verification

Rules are synchronous and must be short. Yielding (`wait`, sleeps, or helpers that
wait) fails the rule. An errored rule is quarantined until event settings reload.
A pre error cancels the request; a quarantined pre rule continues blocking that
action type until corrected/reloaded. Other matching rules still get a chance to
run, including post cleanup. Do not initiate spells/abilities/weapon skills from
event rules; nested requests during rule execution are blocked when intercepted.
Scheduled commands that create later requests are not a supported event-rule flow.

When a configured event action has a known positive spell/ability recast, its
outgoing request is blocked before pre runs. No equipment swaps or event lifecycle
are created for it, so there is no post to undo nonexistent work. Missing timer
data does not block an attempt; ability checks preserve the existing stratagem
charge handling and conservatively leave Quick Draw/Ready recharge timers alone.
Weapon skills are not rejected by this timer check. This does not prove other
readiness conditions, such as whether a roll buff is already active.

The listeners see outgoing packet requests, not client attempts that fail before
any request is sent. Incoming results without a captured outgoing request do not
create synthetic lifecycles. Gambit's explicit spell/ability packet dispatch
also calls the event service directly, so it does not depend on callbacks for
its own injections. Own reinjections bypass interception through one-use payload
permits, including outgoing callbacks delivered after the injection call returns.
Header sequence bytes are excluded from matching; unused permits expire after
10 seconds and their registry is bounded. Other injected requests
are processed when delivered to the outgoing-chunk listener.

This initial pass needs in-game verification of packet interception, cancellation,
manual/menu actions, equipment ordering, and result correlation. The equipment
barrier waits for confirmation. Packet arrival/other addons can affect timing.
GearSwap or another equipment/dispatch controller can compete with
this system; avoid overlapping ownership while testing. Lua callbacks do not
provide hard real-time guarantees.

Implementation lives in `lib/events/`: `config.lua` handles selection/compilation,
`runner.lua` evaluates rules, `runtime.lua` owns request state, and `init.lua` owns
Windower listeners. The packet/event contracts are described in
[Windower events](https://github.com/Windower/Lua/wiki/Events) and
[packet definitions](https://github.com/Windower/Lua/blob/dev/addons/libs/packets/fields.lua).
