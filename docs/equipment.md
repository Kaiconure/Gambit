# Equipment queue

## Reuse a configured piece

Slot values can reference another variable's complete item specification:

```lua
equipMany({head={var='vars.gear.battle.head'}})
equip('head', {var='gear.battle.head'})
```

The leading `vars.` is optional, as with `getVar`. References resolve at request
time in the current variable scope, preserving item names, augments, and candidate
arrays. Resolved values are copied so sanitization cannot modify the source.
Missing values leave the slot unchanged. Chains are supported; circular or
excessively nested references and references mixed with other fields are errors.
The same slot-reference format works with `equipPush` and `checkEquipMany`.
`equipment_set` still exposes the original caller-provided set, including `meta`.
`equipPop`/`equipRestore` continue restoring exact snapshots without re-resolving
configuration references.

Gambit's normal actions and event rules share one equipment manager under
`lib/equipment/`. Existing `equip`, `equipMany`, `checkEquipMany`, `equipPush`, and
`equipPop` calls keep their input formats. A successful call means changes were
requested, not that the server has confirmed them.

## Equipment views

### Ordered item candidates

`equip('back', {'Aptitude Mantle +1', 'Aptitude Mantle'})` chooses the first
available, eligible item. Slot-based sets can supply an ordered array of item
tables (including per-candidate augments):

```json
{
  "back": [
    {"name": "Aptitude Mantle +1"},
    {"name": "Aptitude Mantle"}
  ]
}
```

This also works with `equipPush(set)` and `checkEquipMany(set)`. Candidates are
tested in order and stop at the first usable match. An item already equipped
or queued in the requested slot counts as available. A matching instance is
retained instead of swapping to another copy; required augments must match, but
unspecified augments do not force a copy change. A better candidate becoming
available can upgrade the slot on a later call. Candidates unavailable for the
slot, including copies already used by another slot, are skipped. If none are
available the slot is left unchanged. Paired slots resolve in deterministic slot
order and cannot select the same physical copy twice.

`equipPop()` does not select candidates: it restores the exact saved physical
item instance or empty slot, as before. Helper return conventions are unchanged.
Candidate lists share one normalization/resolution pass and inventory input
snapshot per request; actual queue sends still validate identity and wait for
acknowledgments. Missing candidates add lookup work, while early matches avoid
examining lower-priority candidates. No runtime timing guarantee is implied.

The manager tracks confirmed gear, queued requests, and submitted requests.
Its effective view overlays queued/submitted changes on confirmed gear. It does
not modify Windower's inventory tables. Confirmed equipped slots are bootstrapped
once from inventory and then updated only by equipment packets, including changes
not initiated by Gambit. Queries and queue ticks never reread the equipped-slot
snapshot. Inventory data continues to supply item identity, augments, availability,
and bag contents; it is not a competing source for slot occupancy.

Submitted swaps advance only on matching equipment packets, never merely because
a cached inventory snapshot happens to match. Delayed inventory snapshots cannot
overwrite confirmed equipment, even for idle slots that have never been swapped
by Gambit. An equipment packet records bag/index even if item metadata is not yet
available; equipment item queries may return nil until inventory supplies those
details. Unknown slots remain unknown rather than falling back to cached values.

`findEquipmentInSlot('ring1')` uses effective gear. To query confirmed equipment:

```lua
findEquipmentInSlot('ring1', true)
```

Inventory searches with equipment filters, ranged-equipment checks, and `canShoot`
use effective state. Usable-item searches retain actual inventory/activation data:
requesting an enchanted ring does not mean it is confirmed worn or ready to use.
Item fields such as raw inventory `status` and activation timestamps are not
fabricated by the projected view.

`checkEquipMany` uses effective state without changing it. `equipPush()` saves a
snapshot of all known effective gear without requesting any changes, and returns
true. `equipPush(gear)` saves the same full snapshot, then applies the supplied
gear; it retains the requested-change count/nil return convention. Even when no
requested item is available, it still pushes a full restore point.

Event lifecycles begin with a baseline snapshot on their private stack before
`pre`, so an extra pop can restore pre-lifecycle equipment without an explicit
push. `use_equipment_snapshot` enables automatic restoration of that baseline
after `post` if it has not been popped. Remaining entries are then discarded.

Equipment helpers preserve their return values but do not print intermediate
counts or restoration messages. Verbose output reports one count per nonempty
batch submitted to the shared equipment queue, including restoration batches.
No-op batches are silent; swap failures remain visible.

Equipment sets may carry a reserved `meta` field with arbitrary caller metadata:

```json
{
  "head": {"name": "Some Hat"},
  "meta": {"stop": true}
}
```

Equipment helpers ignore `meta` without modifying or interpreting its contents.
Event rules may use `set.meta and set.meta.stop and stopEvent()` after equipping
the set. The shipped event modules use this pattern for per-name overrides and
roll gear. Metadata is not an instruction to the equipment queue itself.
Sanitization runs each time a helper is called, so runtime changes are respected;
it is not a one-time load transformation.

`equipMany(set)` and `equipPush(set)` clear `equipment_set` initially, then expose
the original input table in the current context before submitting equipment.
This retains metadata even when no changes are needed. Subsequent commands can
use `equipment_set.meta and equipment_set.meta.stop and stopEvent()` independently
of the helper's return value. For slot/name argument lists, `equipment_set` is
the normalized equipment map instead. A no-argument `equipPush()` leaves it nil.
The value belongs to the current context; a new event phase starts without it.

`equipPop()` restores the latest full snapshot, including slots changed by later
`equip()` or `equipMany()` calls and originally empty slots. Therefore pop can
undo unrelated gear changes made since the push; it is not limited to the slots
specified in the matching push. Keep one pop per push regardless of return value.
For example, push A, push B, pop, pop restores the state after A, then the original
state. Partial A/B sets overlay prior gear, with B winning overlapping slots.

Snapshots store bag/index/item identity and do not search for merely equivalent
items if saved bag slots have been reused. Unknown slots are omitted, never
assumed empty. Missing metadata for a known occupied slot raises an error before
the snapshot is pushed or optional gear is applied.

## Ordering and acknowledgments

Normal-action equipment calls create ordered batches. Event rules instead share
a context-local collecting session for each phase. General sets and later slot
overrides merge in that session; only the final requested item for each slot is
submitted as one batch when the phase finishes. For example, general head A plus
a later Dark Magic head B submits only B, while preserving the general set's
other slots. The helper syntax is unchanged.

Equipment queries and `checkEquipMany` inside that phase see its plan overlaid on
global effective gear. Confirmed-only queries ignore the local plan. Other
contexts cannot see or change that private plan; their own submissions still go
through the shared queue. The session is explicitly bound to the event context,
not selected through a global batching flag.

Batches stay in submission order;
future restoration does not collapse or discard pre/mid gear needed around an
action. The existing slot order is now enforced:

```text
main, range, head, neck, body, hands, back, waist,
legs, feet, ear1, ear2, ring1, ring2, sub, ammo
```

Independent slots can be submitted together. Sub waits for a main-hand change's
acknowledgment; ammo waits for a ranged change. When a batch changes both main
and sub and sub is occupied, the manager first clears sub, waits for confirmation,
changes main, waits for confirmation, and then equips the requested sub item.
This avoids depending on retries to resolve ordinary main/sub conflicts.
The game still validates job, skill, dual-wield, two-handed, and multi-slot gear
compatibility. Impossible combinations eventually fail rather than being retried
forever.

The adapter submits individual equipment packets (`0x050`) directly and consumes
equipment acknowledgments (`0x050`) and equipset snapshots (`0x117`). A whole
equipset snapshot is reconciled before the next batch is released.

Unacknowledged changes retry after 0.75 seconds, with at most three submissions
(the initial request and two retries). Bag identity is checked before every
submission. Failure reports the slot, ends that batch, and allows later work to
proceed; the next dispatch barrier fails rather than casting with unconfirmed
pre gear. Once a batch is retired, it cannot retry and overwrite later gear.
There is no background retry of failed desired state after its batch has ended.

## Action boundaries

Event dispatch uses an equipment barrier:

```text
pre gear confirmed → action dispatched → mid gear → post restoration
```

Mid remains immediately after dispatch, not the incoming cast-start event.
The normal explicit spell/ability dispatcher also respects pending equipment;
command-generated action packets wait when they encounter pending gear through
the event service. This is asynchronous: no event rule sleeps waiting for gear.
Pre commits its merged plan and reserves the dispatch barrier in the same
synchronous execution, without a scheduling delay between them. A phase with no
equipment changes need not wait for an artificial 0.1-second timer.

Pre cancellation discards its unsent gear and rolls back that phase's equipment
stack edits before post cleanup runs. A rule error in any phase also discards its
entire gear plan and restores the stack checkpoint. Other command side effects
and variable changes are not rolled back. A failed mid phase preserves pushes
from a successful pre, so post can still restore that earlier work. A post rule
error discards that post plan too; inspect the reported error rather than assuming
restoration succeeded. Layers within a phase combine; different phases remain
separate to preserve action boundaries.

Push snapshots include earlier requests in the same phase, even if their items
never reach the game. Keep pushes/pops balanced as before: multiple pops within
one post phase can unwind those logical layers while committing only the final
restoration. No exclusive equipment ownership is held across an entire action's
lifetime; other batches can still run between phases.

Logout and addon shutdown clear pending equipment work and fail held dispatch
callbacks. Login, zoning, and job changes explicitly reset the queue and read a
new baseline; later changes again come exclusively from equipment packets.
Normal settings reloads do not recreate or resnapshot the manager.
Automation being disabled does not stop the queue or equipment acknowledgments.

`gbt equipment resync` explicitly clears pending equipment requests, fails held
dispatch barriers, and bootstraps current slots from inventory. It is a recovery
operation for missed state, not part of ordinary gear changes. Already dispatched
actions can still receive their later post event. There is no automatic inventory
polling fallback after initialization or a reset.

## Initial in-game checks

After `lua reload Gambit`, test one swap at a time:

1. A Corsair roll with pre push/post pop, including a rejected attempt.
2. Sword/shield changes where both main and sub are requested.
3. A spell using different pre and mid gear, then restoring in post.
4. Effective versus confirmed equipment lookups while a swap is pending.

Packet acknowledgment and equipment timing still need live verification. Manual
or other-addon swaps are reflected when confirmed but do not share Gambit's
pending-request ownership. Competing equipment controllers can overwrite each
other; this manager is not a cross-addon arbitration system. Inventory movement
or rejected equipment may cause a batch to fail, in which case the console reports
the slot instead of silently assuming the desired gear is worn.
