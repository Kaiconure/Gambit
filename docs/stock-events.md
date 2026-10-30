# Using and extending the stock events

The shipped events provide configurable gear rules for every job. Most characters
can use them by creating a variable file; writing a personal event rule file is
optional. See the [event user guide](events.md) for event timing, rule syntax,
context fields, imports, and the full contribution interface.

## Quick start

Create `settings/<character>/events/<job>.vars.json`, using the character's name
and lowercase main-job abbreviation. For example:
`settings/Miyajima/events/whm.vars.json`.

```json
{
  "vars": {
    "gear": {
      "csv(idle, battle)": {
        "back": [
          {"name": "Aptitude Mantle +1"},
          {"name": "Aptitude Mantle"}
        ]
      },
      "spells": {
        "pre": null,
        "curing": {
          "mid": {"back": {"name": "Vates Cape +1"}}
        }
      }
    },
    "post_equip": {"restore_snapshot": true}
  }
}
```

Replace the example pieces with your own gear. This gives idle and battle the
same independent set, chooses the first available mantle, and overlays a curing
piece during cures. After an action, it restores the starting gear before
applying the appropriate idle/battle set.

Run `//gbt events reload`, then `//gbt events status` to check what loaded.
Use `//gbt events reload -v` to export the fully processed configuration.
An existing personal `<job>.json` or group rule file can override the stock entry
point; adding a vars file does not remove that override.

## Files and layering

| Location | Purpose |
|---|---|
| `events/` | Shipped rule entry points and reusable modules |
| `settings/events/<job>.vars.json` | Shared job configuration |
| `settings/<character>/events/<job>.vars.json` | Character-specific configuration |
| `settings/<character>/events/(mages).vars.json` | Character configuration for a matching job group |
| `settings/_ns/<namespace>/events/` | Namespace-wide settings |
| `settings/_ns/<namespace>/players/<character>/events/` | Character settings within a namespace |

Exactly one rule entry point wins. All applicable vars files are layered, even
when the selected entry point is a shipped file. More specific settings win at
equal priority; nested objects merge and arrays use the winning definition.
Inline vars in rule modules are defaults. The usual `!` and `^` variable prefixes
are supported. See [file selection and variables](events.md) for details.

Vars files accept `vars` and `contributions`, not event sections or imports.
Configuration is for the main job; subjob modules are not automatically imported.
If you need different rules, create an entry point and import the desired library
modules explicitly. Imports follow event-directory precedence, so importing your
own entry point's name would create a cycle.

## Gear set format

All paths below start with `vars`. In JSON, put them under the top-level `vars`
object. Gear sets are slot-keyed objects:

```json
{
  "vars": {
    "gear": {
      "spells": {
        "pre": {
          "back": [
            {"name": "Aptitude Mantle +1"},
            {"name": "Aptitude Mantle"}
          ],
          "meta": {"stop": false}
        }
      }
    }
  }
}
```

- A slot can contain an item name, an item object with `name` and optional
  `augments`, or an ordered array of candidates. The first available candidate
  wins. Matching equipped copies are retained rather than swapped repeatedly.
- Missing items leave the slot alone. A partial set changes only listed slots.
- Use `null` to leave an optional set unconfigured. An empty object requests no
  gear but can still carry metadata.
- `meta` is ignored by equipment selection. Stock rules interpret `meta.stop`
  as a request to stop later rules in that phase after applying the set.
  This also works when the requested gear is already equipped.
- `"csv(Savage Blade, Shining Blade)"` creates independent named sets with the
  same initial value. It works at any variable-object level. Explicit sibling
  keys override CSV-generated values at equal priority.

See the [equipment reference](equipment.md) for augments and helper interfaces.

## Common variable reference

Replace `<name>` with the exact English spell or ability name. Bracket notation
below describes an object key, not literal JSON punctuation.

| Variable path | Purpose |
|---|---|
| `gear.idle` | Gear on entering idle and after an action while idle |
| `gear.battle` | Gear on entering battle and after an action while engaged |
| `gear.spells.pre` | General pre-cast set, including specialized spell modules; useful for Fast Cast |
| `gear.spells.<category>.pre` / `.mid` | General set for a spell category |
| `gear.spells.<category>[<name>].pre` / `.mid` | Named override within that category |
| `gear.spells[<name>].pre` / `.mid` | Named override for any spell |
| `gear.spells.buff_overlays` | Ordered buff-dependent spell overlays; see below |
| `gear.weapon_skills.pre` | General weapon-skill set |
| `gear.weapon_skills[<name>].pre` | Named weapon-skill override |
| `gear.job_abilities[<name>].pre` | Named job-ability set |
| `gear.rolls` | Direct gear set for Corsair rolls and Double-Up; there is no `.pre` suffix |
| `gear.pet_abilities[<name>].pre` / `.mid` | Named pet-command/ability overrides |
| `on_battle.windower_commands` | Array of literal Windower commands after the battle-enter gear rule |
| `on_idle.windower_commands` | Array of literal Windower commands after the idle-enter gear rule |
| `post_equip.restore_snapshot` | Restore starting gear before the post idle/battle overlay; default `false` |

Common spell categories are `curing`, `enfeebling`, `enhancing`, `elemental`, and
`burst`. GEO adds `geomancy`; BLU adds `blue`. There is no general
`gear.spells.mid` rule: use categories or named sets for result-enhancing gear.

`curing` includes Cure, Curaga, Cura, and Full Cure, but not all Healing Magic.
`elemental` describes the Elemental Magic skill. `burst` additionally requires
`canMagicBurst(event)` for the current target/window. A spell-specific set can
run without its category's general set being configured.

### Named overrides

```json
{
  "vars": {
    "gear": {
      "spells": {
        "enfeebling": {
          "pre": null,
          "mid": null,
          "csv(Dispel, Sleep, Sleep II)": {
            "mid": {"head": {"name": "Pixie Hairpin +1"}}
          }
        }
      },
      "weapon_skills": {
        "csv(Savage Blade, Shining Blade)": {
          "pre": {"ring1": {"name": "Rufescent Ring"}}
        }
      }
    }
  }
}
```

These are examples of path layout, not recommended complete gear sets. Choose
pieces and phases for your character and spell. Very fast spells can finish
before mid gear arrives; put essential gear in pre when necessary.

### Spell layering and stops

The common spell modules apply general pre gear first, then category gear and
category-specific named overrides. Elemental gear precedes burst gear, with
general and named sets checked independently. Buff overlays follow those
categories, then the general named-spell override runs.

The final common mid rule attempts Pixie Hairpin +1 for Dark-element spells
targeting mobs, if available. It is independent of your configured category sets.
The contribution example below shows how to disable it.

Specialized job modules add their own layers. Most run before the common spell
rules; SCH's arts/stratagem overlays run after them. A `meta.stop` or earlier
stop rule can prevent any later layer. The processed output is the authoritative
view of your actual ordering, including imports and contributions.

All gear requests in a phase are batched. Later layers win overlapping slots
without equipping each intermediate set separately. The pre batch is acknowledged
before the action is dispatched; mid does not delay spell completion.

### Buff overlays

`gear.spells.buff_overlays` is an ordered array. Each entry needs a `buff`, a
`when` condition array, and a `pre` and/or `mid` set. Use an empty `when` array
for no additional restriction. Entries without the relevant phase or `when`
are skipped before condition evaluation.

```json
{
  "vars": {
    "gear": {
      "spells": {
        "buff_overlays": [
          {
            "buff": "Rapture",
            "when": ["event.curing"],
            "mid": {"meta": {"stop": false}}
          }
        ]
      }
    }
  }
}
```

Add your equipment slots alongside `meta`. Matching entries apply in order.
An entry's `meta.stop` stops the loop and later rules in that phase.

### Windower commands on state changes

```json
{
  "vars": {
    "on_battle": {"windower_commands": ["input /echo Entered battle"]},
    "on_idle": {"windower_commands": ["input /echo Returned to idle"]}
  }
}
```

These strings go to `windower.send_command`; they are not Lua expressions.
They dispatch after the gear request is collected, without waiting for gear
acknowledgment or command completion. A stop on the preceding idle/battle gear
rule also skips these commands.

## Job-specific modules

`common.json` is the fallback for jobs without a dedicated entry point.
Dedicated files import the common behavior plus the modules below. Configure
their variables in the same character/job vars file.

| Entry point | Additional variable paths |
|---|---|
| `brd.json` | `gear.songs.pre` / `.mid`, then `gear.songs[<name>].pre` / `.mid` |
| `nin.json` | `gear.ninjutsu.pre` / `.mid`, then `gear.ninjutsu[<name>].pre` / `.mid` |
| `smn.json` | `gear.summoning.avatar`, `.rage`, `.ward`: each has `.pre` / `.mid` and `[<name>].pre` / `.mid` overrides |
| `geo.json` | `gear.spells.geomancy.pre` / `.mid` and named category overrides |
| `blu.json` | `gear.spells.blue.pre` / `.mid` and named category overrides |
| `bst.json` | `gear.beastmaster.ready.pre` / `.mid` and `[<name>].pre` / `.mid` overrides |
| `pup.json` | `gear.puppetmaster.abilities[<name>].pre` |
| `sch.json` | `gear.scholar.light_arts.pre` / `.mid`, `.dark_arts.pre` / `.mid`, and `.stratagems` |

Every specialized spell module also imports the shared general spell-pre rule;
it is included only once.

- **BRD:** song classification comes from the spell's Singing skill. Choose the
  instrument in your gear set; the event does not infer instrument skill flags
  from your currently equipped instrument.
- **SMN:** avatar spells use `avatar`; Blood Pact Rage/Ward commands use the
  corresponding pet-ability category. Pet pre is player initiation, mid is
  observed pet execution, and post is completion/failure. Do not depend on mid
  always occurring.
- **GEO:** geomancy remains under `gear.spells.geomancy`. Configure player
  abilities such as luopan-related job abilities under `gear.job_abilities`.
- **BLU:** Blue Magic has its own category; Blue cures do not set `event.curing`.
- **BST:** Ready rules target named pet monster abilities. Reward is a player
  job ability. Random Sic moves and autonomous pet actions are not covered by
  the same command-correlated lifecycle.
- **PUP:** configure Activate, Deus Ex Automata, Repair, and Maintenance through
  the named ability map. This does not add autonomous automaton-action events.
- **SCH:** Light Arts/Addendum: White and Dark Arts/Addendum: Black select their
  respective overlays. Stratagem overlays run after the common spell rules.

Generic named job/pet ability sets remain available after the specialized job
rules, allowing a final named override unless an earlier rule stops processing.

### Scholar stratagems

`gear.scholar.stratagems` is an ordered array of entries containing `buff`,
optional `when`, and `pre` and/or `mid` sets:

```json
{
  "vars": {
    "gear": {
      "scholar": {
        "stratagems": [
          {"buff": "Rapture", "when": ["event.curing"], "mid": {}},
          {"buff": "Ebullience", "when": ["event.elemental"], "mid": {}}
        ]
      }
    }
  }
}
```

Replace the empty sets with your enhancement pieces. Unlike general buff
overlays, stratagem entries allow `when` to be omitted. The same `meta.stop`
behavior applies.

## Restoration and partial sets

By default, post equips `gear.idle` or `gear.battle` for the current state.
Only listed slots change. If your idle set only contains a back piece, a head
piece equipped for casting will stay equipped.

Set `vars.post_equip.restore_snapshot` to `true` to restore the lifecycle's
starting equipment first, then apply the idle/battle overlay. This works for
spells, job abilities, weapon skills, and pet abilities. The restore and overlay
share one phase batch. Manual pushes are unwound to the original baseline when
it is still present; a baseline already consumed by your own pops is not restored
again. This option is useful for partial state sets.

This differs from the action-section flag `use_equipment_snapshot`, which
automatically restores after all post rules. That later cleanup can overwrite
post gear if its baseline remains. The stock restore-first option consumes that
baseline before applying state gear. See [equipment restoration](events.md#equipment-and-restoration)
when combining manual pushes, automatic restoration, and custom post rules.

Equipment is global even though stacks are private. Restoring the starting
snapshot can replace intentional gear changes made during the lifecycle.
Status-enter gear rules do not capture or restore an action baseline.

## Extending stock behavior with contributions

Keep gear in `vars`, and add rules through `contributions` in the same vars file.
Every phase has built-in `.before` and `.after` hooks. Examples include
`spells.pre.before`, `pet_abilities.mid.after`, `statuses.idle.enter.after`,
and `loading.actions.after`.

```json
{
  "vars": {"announce_cures": true},
  "contributions": {
    "spells.pre.before": [
      {
        "when": ["vars.announce_cures and event.curing"],
        "commands": ["log('Casting', event.name)"],
        "id": "personal-cure-note"
      }
    ]
  }
}
```

Before hooks run before the composed stock phase; after hooks run after it.
An earlier stop can prevent an after hook from running. Contributed equipment
uses the same batch as stock equipment, with later slot requests winning.
Keep commands synchronous and short.

### Disable or replace a stock rule

IDs resolve at load time across a final phase. To remove the stock Hairpin rule:

```json
{
  "contributions": {
    "spells.mid.after": [
      {"disabled": true, "id": "pixie-hairpin-for-darkness"}
    ]
  }
}
```

This removes the earlier definition during loading; the disabling entry does
not have to be reached at runtime. A normal contributed rule with the same ID
replaces the earlier definition and takes the contribution's position.
Replacement is different from stopping: it changes the configuration itself.

Useful IDs include `general-spell-pre`, `spells-named-pre`, `spells-named-mid`,
`spells-buff-overlays-pre`, `spells-buff-overlays-mid`, `rolls-pre`, and
`post-equip-spells-restore`. Category IDs include `spells-curing-mid` and
`spells-curing-named-mid`. Inspect the shipped module or processed output for
the exact ID and phase you want to change.

### Custom hooks and contribution controls

For finer placement, a personal rule entry point can import library modules
and place a `{"slot": "personal-hook"}` placeholder inside its own phase array.
Vars files can then contribute to that name. A vars file alone cannot insert
a custom placeholder into an imported rule array.

Contributions support the normal slot controls: `optional`, `required_for`,
`!` replacement, `^` defaults, comma-separated destinations, and rule priority.
`required_for` controls missing-slot diagnostics rather than whether the rules
run. Built-in before/after hooks cannot be moved or redeclared. See
[slots and contributions](events.md#slots-and-contributions) for the reference.

## Checking your setup

| Problem | Check |
|---|---|
| A variable appears ignored | Active entry point, exact English name, path, phase, and earlier stops |
| Old gear layout no longer works | Use `gear.weapon_skills`, category `.pre`/`.mid`, and direct `gear.rolls` as documented |
| Casting gear remains equipped | Complete state sets or enable restore-first behavior |
| An overlay does not run | Relevant phase set, buff name, `when`, and the module imported by your main-job entry point |
| Rules run in an unexpected order | Export processed JSON and inspect IDs, sources, and expanded slots |
| A runtime variable disappears next cast | Ordinary event vars remain lifecycle-local; loading actions can initialize future defaults |

The processed file contains merged variables before loading actions execute,
CSV-expanded names, final rule ordering, and source metadata. It does not
prove that you own the items or that mid swaps beat a fast spell. Test successful,
interrupted, and rejected actions in game before relying on a new setup.

For more details, see [the event guide](events.md),
[equipment](equipment.md), and [commands](commands.md).
