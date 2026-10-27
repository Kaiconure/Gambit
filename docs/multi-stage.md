# Multi-stage weapon-skill participants

Multi-stage chains accept the normal party target selectors in `participants`,
`stage_participants`, stage-local `participants`, individual `on_ws` entry
participants, and the keys of `exclusions`. Existing character-name arrays remain
supported, including their explicit priority order.

```json
{
  "participants": ["WAR", "PLD"],
  "stage_participants": {
    "1": ["WAR"],
    "2": ["PLD"],
    "3": ["WAR", "PLD"]
  },
  "exclusions": {
    "COR": [1, 2],
    "Theta": [3]
  }
}
```

These fields belong in `vars.ws.multi_stage` or a selected
`vars.ws.multi_stage_settings` configuration. The example assigns opening to WAR,
the initial closer to PLD, and the next stage to WAR followed by PLD. It does not
define the weapon skills or chain itself.

## Protected participants

Prefix a participant selector or character name with `!` to protect its matches
from exclusions in that list:

```json
{
  "stage_participants": {
    "3": ["!leader", "COR", "melee"]
  },
  "exclusions": {
    "WAR": [3]
  }
}
```

Here the leader remains eligible for stage 3 even when their main job is WAR.
Other WAR participants are excluded normally. Protection works in global,
stage-override, stage-local, and individual `on_ws` participant lists. It survives
rotation and generated branches, and overrides both inline `~` exclusions and
stage/substage exclusion rules. An overriding participant list replaces the
inherited list's protection along with its membership.

Protection does not move a duplicate to a new position: `["melee", "!leader"]`
retains the leader's first matching position while protecting that match. It
never bypasses TP, engagement, range, or weapon-skill eligibility. Protection is
recomputed when roster or leadership changes. `!` applies only to multi-stage
participant lists; it is rejected in exclusion keys. Empty or combined forms
such as `!`, `!!leader`, and `!~leader` are invalid. Client-relative selectors
remain unsuitable for shared coordination even when protected.

## Resolution and ordering

Selectors expand in array order. Multiple members matching a job/group are
alphabetical by character name; overlaps are deduplicated. Names, jobs, groups
such as `melee`, semantic member symbols, `*`, and `~` exclusions use the existing
selector conventions. For example, `["Aidelle", "melee", "~COR"]` prefers Aidelle
before other melee and removes COR matches.

For shared coordination, avoid `me`, `^melee`, positional member symbols such as
`p0`, and other client-relative selectors. They can produce different lists on
different clients. Self-first and random ordering options are not used. Clients
must have consistent party/job information to agree on priority.

Participant rotation runs on the expanded character list using the existing
rotation behavior. Stage exclusions then remove matching names. Exclusion keys
can match several members, and overlapping rules combine. Existing numeric stage
rules remain unchanged: for example `2` excludes all initial closing branches,
while `2.1` identifies the first branch. Stage two's local exclusion rules retain
their branch-number convention, such as `1` for its first branch.

`stage_participants["2.1"]` overrides participants for that initial closing
branch, including generated branches. An explicit manual `on_ws` entry's
participants take precedence over that override. For generated branches, the
existing order is branch override, stage-two override, stage-local participants,
then global participants. Other stages prefer explicit stage participants, then
the stage override, then the global list.

Resolution does not consume or modify a gambit action's member enumeration.
The compiler keeps a separate copy of the unresolved configuration and rebuilds
the resolved plan when the observed party roster, jobs, leadership or member
symbols change. TP, range, death and engagement remain runtime eligibility
checks; they do not reorder or recompile participants. Compiled diagnostic output
contains resolved names. Reload actions after editing the sequence configuration.

A nonempty selector list with no matches does not become an unrestricted closer.
Likewise, exclusions removing every candidate block that stage. Such lists use a
nonmatching placeholder in compiled output. A genuinely empty participant list
retains the previous behavior, including the initial readiness check's lack of a
participant restriction; it does not select an executing closer by itself.

## Shared weapon-skill capabilities

Compilation warns when a restricted stage has no eligible participants after
exclusions and capability filtering. Stage 2 produces one warning only when none
of its alternatives can be filled; individual unavailable alternatives are silent.
Warnings identify the step (such as `#2`) and its required weapon skills. Pending capability replies
do not produce a confirmed-inability warning. Cached evaluations do not repeat
warnings; a later recompilation reevaluates them. This diagnostic does not disable
the whole sequence or add a full-sequence readiness check.

Gambit exchanges weapon-skill IDs over IPC on addon load and login. It also
checks the local ability list for changes during the IPC sender loop and
broadcasts only changed snapshots. Use `gbt wsinfo -sync` to request a fresh
snapshot from every local instance, `-send` to broadcast yours, and `-all` to
inspect the cache. Instances must have this support loaded to respond.

Multi-stage compilation layers capability filtering onto configured participant
lists and exclusions. Each stage and stage-2 alternative keeps only characters
with at least one compatible weapon skill. Remote capabilities are compared
against the full role, independently of the compiling character's skills.
Unknown characters cannot be assigned until they advertise capabilities; an
empty advertised list confirms no available weapon skills. Capability changes
rebuild cached plans on their next evaluation. Derived exclusions stay in memory
and compiled diagnostic output; source configuration files are never rewritten.

Manual exclusions retain their existing behavior. Protected `!` participants
still override manual exclusions, but cannot override missing capabilities.
TP, range, engagement, and temporary restrictions remain runtime checks.
