# Using and extending the stock events

The shipped events provide configurable gear rules for every job. Most characters
can use them by creating a variable file; writing a personal event rule file is
optional. See the [event user guide](events.md) for event timing, rule syntax,
context fields, imports, and the full contribution interface.

## Shipped event entry points

These files live in the addon's top-level `events/` directory. Closer user or
namespace files take precedence. Jobs without a dedicated entry point use
`common.json`; they can still have their own `<job>.vars.json` configuration.

| File | Included behavior |
|---|---|
| `common.json` | Shared spells, job abilities (including Corsair rolls), weapon skills, named pet abilities, idle/battle transitions, and post-equipment rules |
| `blu.json` | Common behavior plus Blue Magic sets and named overrides |
| `brd.json` | Common behavior plus song sets and named overrides |
| `bst.json` | Common behavior plus general and named Ready sets |
| `geo.json` | Common behavior plus geomancy sets and named overrides |
| `nin.json` | Common behavior plus ninjutsu sets and named overrides |
| `pup.json` | Common behavior plus named PUP player-ability sets such as Repair |
| `run.json` | Common behavior plus general/named Rune Enchantment, Ward, and Effusion sets |
| `sch.json` | Common behavior plus arts- and stratagem-dependent spell overlays |
| `smn.json` | Common behavior plus avatar summoning and general/named Blood Pact Rage/Ward sets |
| `empty.json` | An explicitly selectable entry point with no built-in rules; independently loaded vars-file contributions can still add handlers |

The reusable pieces are under `events/lib/`. You normally configure the shipped
entry points through vars files rather than editing these libraries. Their
supported gear paths and job examples are described below.

## Event command cheat sheet

The command is **`gbt events`** (plural). In game, prefix it with `//`:

| Command | Purpose |
|---|---|
| `//gbt events` or `//gbt events status` | Show the active entry point, imports, and variable files; `s` is an alias for `status` |
| `//gbt events reload` or `//gbt events r` | Reload event JSON using automatic/default file selection |
| `//gbt events r -e empty` | Temporarily select `empty.json`; substitute any event-file name or library-style path |
| `//gbt events r -r` | Reload the currently selected event file instead of returning to automatic selection |
| `//gbt events r -v` | Reload automatic selection and export processed event JSON |
| `//gbt events r -r -v` | Reload the current selection and export its processed JSON |
| `//gbt r` | Reload normal settings/actions and events, restoring automatic event selection |
| `//lua reload Gambit` | Reload addon Lua code after implementation changes; event JSON reload alone does not reload Lua |

`-e` also accepts `-events`, `-r` accepts `-reload`, and `-v` accepts `-verbose`.
An explicit filename may omit `.json` and resolves through the event search
hierarchy. Selection is not persisted. `-e` and `-r` are mutually exclusive;
either can be combined with `-v`. Failed event loads retain the previous working
configuration. See [the event guide](events.md#reloading-and-troubleshooting)
for output locations and diagnostics.

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

## How-to guide

Use these recipes in `settings/<character>/events/<job>.vars.json`, unless a
recipe says otherwise. Replace descriptive item names such as `Your Fast Cast
Head` with exact names of equipment you own. The examples illustrate configuration,
not recommended best-in-slot sets. Combine their fields into one `vars` object
and one `contributions` object; do not paste several whole JSON documents into
the same file or repeat object keys.

| I want to... | Recipe |
|---|---|
| Use a shared Fast Cast set | [General spell pre-cast](#use-one-fast-cast-set-for-spells) |
| Enhance cures, enfeebles, or nukes | [Spell categories and named overrides](#layer-spell-category-and-named-gear) |
| Add magic-burst or buff-dependent gear | [Burst and buff overlays](#add-burst-and-buff-dependent-overlays) |
| Return to normal gear | [Idle/battle gear and restoration](#equip-idlebattle-gear-and-restore-partial-sets) |
| Prefer an item but accept a fallback | [Candidates and shared sets](#choose-fallback-items-and-share-set-definitions) |
| Enhance abilities, rolls, or weapon skills | [Abilities and weapon skills](#configure-abilities-rolls-and-weapon-skills) |
| Configure a job-specific system | [Job recipes](#configure-job-specific-gear) |
| Add custom behavior without replacing stock rules | [Contributions](#add-custom-rules-and-initialization) |
| Find out why a rule isn't working | [Check and troubleshoot](#check-which-files-and-rules-are-active) |

### Use one Fast Cast set for spells

Configure **`gear.spells.pre`** for general spell pre-cast equipment:

```json
{
  "vars": {
    "gear": {
      "spells": {
        "pre": {
          "head": {"name": "Your Fast Cast Head"},
          "body": {"name": "Your Fast Cast Body"},
          "ear1": {"name": "Your Fast Cast Earring"}
        }
      }
    }
  }
}
```

The shared pre rule runs before specialized and named spell gear. Songs,
ninjutsu, summoning, geomancy, and Blue Magic modules import it too; import
deduplication prevents it running multiple times. Later pre layers can override
its slots. Leave `meta.stop` unset if those layers should still run.

Pre equipment is acknowledged before the action is dispatched. Result-enhancing
equipment usually belongs in mid, but fast/instant spells may finish before mid
gear arrives. For such spells, put essential result gear in their named pre set:

```json
{
  "vars": {
    "gear": {
      "spells": {
        "Flash": {"pre": {"head": {"name": "Your Flash Head"}}}
      }
    }
  }
}
```

This overlays the shared Fast Cast set; it doesn't replace every slot.

### Layer spell category and named gear

The stock spell categories under `vars.gear.spells` are:

| Category | Applies to |
|---|---|
| `curing` | Cure, Curaga, Cura, and Full Cure; excludes other Healing Magic and Blue Magic cures |
| `divine` | Spells using the Divine Magic skill, such as Flash, Banish, and Holy |
| `enfeebling` | Spells using the Enfeebling Magic skill, such as Dispel and Sleep |
| `enhancing` | Spells using the Enhancing Magic skill, such as Haste and Protect |
| `elemental` | Spells using the Elemental Magic skill, such as Fire and Blizzard; not every spell with an element |
| `magic_burst` | Elemental or Divine Magic, plus Blue Magic with Burst Affinity, whose element matches the target's current tracked magic-burst window; overlays their category gear |
| `geomancy` | Geomancy spells, including Indi- and Geo-spells; supplied by the GEO module |
| `blue` | Blue Magic spells, including Blue Magic cures; supplied by the BLU module |

Each category accepts general `.pre`/`.mid` sets and named spell overrides.
These keys are the categories implemented by stock rules, not an automatic set
for every spell skill. BRD songs, NIN ninjutsu, and SMN summoning use separate
paths described in [job-specific gear](#configure-job-specific-gear).

General category gear runs first, followed by its named override:

```json
{
  "vars": {
    "gear": {
      "spells": {
        "curing": {
          "mid": {
            "body": {"name": "Your Cure Body"},
            "hands": {"name": "Your Cure Hands"},
            "neck": {"name": "Your Cure Necklace"}
          }
        },
        "divine": {
          "mid": {
            "body": {"name": "Your Divine Magic Body"},
            "neck": {"name": "Your Divine Magic Necklace"}
          },
          "Flash": {"pre": {"head": {"name": "Your Flash Head"}}}
        },
        "enfeebling": {
          "mid": {
            "body": {"name": "Your Enfeebling Body"},
            "hands": {"name": "Your Enfeebling Hands"}
          },
          "Dispel": {"mid": {"head": {"name": "Your Dispel Head"}}}
        },
        "enhancing": {"mid": {"body": {"name": "Your Enhancing Body"}}},
        "elemental": {"mid": {"body": {"name": "Your Nuking Body"}}}
      }
    }
  }
}
```

Curing means the Cure/Curaga/Cura families and Full Cure, not all Healing Magic.
Category names describe the classifications supported by the stock modules;
they are not arbitrary spell skills. A named override runs even if its general
category set is absent. `gear.spells.Dispel.mid` would instead be the common
named-spell override, applied after category and buff-overlay rules. Use exact
English spell names on every client.

### Add burst and buff-dependent overlays

```json
{
  "vars": {
    "gear": {
      "spells": {
        "elemental": {"mid": {"body": {"name": "Your Nuking Body"}}},
        "magic_burst": {
          "mid": {
            "head": {"name": "Your Burst Head"},
            "ring1": {"name": "Your Burst Ring"}
          }
        },
        "buff_overlays": [
          {
            "buff": "Rapture",
            "when": ["event.curing"],
            "mid": {"head": {"name": "Your Rapture Head"}}
          }
        ]
      }
    }
  }
}
```

Burst gear overlays elemental or divine gear when `canMagicBurst(event)` matches the
target's current tracked window and the spell element. It doesn't guarantee
the spell will land before the window closes. Buff overlays apply in array
order after categories; each needs a `when` array (use `[]` for no additional
condition) and a set for the relevant phase. All changes in that phase form
one final batch. See [buff overlays](#buff-overlays) for the full entry format.

### Equip idle/battle gear and restore partial sets

```json
{
  "vars": {
    "gear": {
      "idle": {"back": {"name": "Your Idle Back"}},
      "battle": {"back": {"name": "Your Battle Back"}}
    },
    "post_equip": {"enabled": true, "restore_snapshot": true}
  }
}
```

State-enter events apply the matching set. After action cleanup, restore-first
returns to the lifecycle's starting equipment, then applies idle/battle gear.
This matters for partial sets: a casting headpiece should not remain just
because your idle set only defines a back piece. It also means intentional gear
changes during the lifecycle can be overwritten.

Note that by default, `post_equip.enabled` is true and `post_equip.resore_snapshot` is false.

Set `post_equip.enabled` to false to disable stock post gear/restoration, while
retaining state-enter rules. Set only `restore_snapshot` to false to keep post
state gear but skip baseline restoration. See [restoration details](#restoration-and-partial-sets)
before combining this with manual pushes or `use_equipment_snapshot`.

To send literal commands after a state-enter gear request, use
`on_idle.windower_commands` or `on_battle.windower_commands`; see
[the command example](#windower-commands-on-state-changes). They don't wait for
equipment acknowledgment and are not Lua scripts.

### Choose fallback items and share set definitions

```json
{
  "vars": {
    "gear": {
      "csv(idle, battle)": {
        "back": [{"name": "Aptitude Mantle +1"}, {"name": "Aptitude Mantle"}]
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

Candidates are ordered preferences; a missing item falls back to the next.
An already-equipped matching copy is retained. CSV keys expand into independent
copies at load time. An explicit sibling name can override a generated name.
See [variables](variables.md#expand-multiple-keys-with-csv) for collision rules
and [equipment](equipment.md) for augments and exact snapshot restoration.

### Configure abilities, rolls, and weapon skills

```json
{
  "vars": {
    "gear": {
      "job_abilities": {
        "pre": {"body": {"name": "Your General Ability Body"}},
        "Sentinel": {"pre": {"feet": {"name": "Your Sentinel Feet"}}}
      },
      "rolls": {"ring1": {"name": "Barataria Ring"}},
      "weapon_skills": {
        "pre": {
          "body": {"name": "Your Weapon Skill Body"},
          "waist": {"name": "Your Weapon Skill Belt"},
          "ring1": {"name": "Your Weapon Skill Ring"}
        },
        "Savage Blade": {"pre": {"head": {"name": "Your Savage Blade Head"}}}
      }
    }
  }
}
```

Use the relevant pieces for your job. Weapon-skill named sets overlay the general
set in pre. Rolls use the direct `gear.rolls` set for Corsair rolls and Double-Up;
there is no `gear.rolls.pre`. Roll rules run before the common general ability
set, then the common named ability override. Avoid configuring conflicting
general ability slots unless you intend to override the roll gear.

These actions need their enhancement gear in pre; don't rely on mid for an
instant player action. Post may occur before its animation visibly ends.

### Configure job-specific gear

Use the matching main-job vars file. The dedicated stock entry point selects
the relevant module; it doesn't automatically select modules for your subjob.
Below are minimal configurations to combine with your common sets and restoration.

| Job | Scenario and example `vars` contents |
|---|---|
| BRD | General song potency: `{"gear":{"songs":{"mid":{"range":{"name":"Your Song Instrument"}}}}}` |
| NIN | General ninjutsu, then named Utsusemi gear: `{"gear":{"ninjutsu":{"mid":{"body":{"name":"Your Ninjutsu Body"}},"Utsusemi: Ni":{"pre":{"head":{"name":"Your Utsusemi Head"}}}}}}` |
| GEO | Geomancy duration/potency: `{"gear":{"spells":{"geomancy":{"mid":{"hands":{"name":"Your Geomancy Hands"}}}}}}` |
| BLU | General Blue Magic, then a named cure override: `{"gear":{"spells":{"blue":{"mid":{"body":{"name":"Your Blue Magic Body"}},"White Wind":{"mid":{"head":{"name":"Your White Wind Head"}}}}}}}` |
| BST | Ready potency: `{"gear":{"beastmaster":{"ready":{"mid":{"body":{"name":"Your Ready Body"}}}}}}` |
| PUP | Repair enhancement: `{"gear":{"puppetmaster":{"abilities":{"Repair":{"pre":{"body":{"name":"Your Repair Body"}}}}}}}` |

Wrap a table example in `{"vars": ...}` when using it as a complete file.
BRD and NIN also accept `[<English spell name>].pre/mid` within `songs` and
`ninjutsu`, respectively. Instrument choice is explicit gear, not an inferred
event classification. Blue cures are Blue Magic and do not match `curing`.
Luopan-related player abilities and BST Reward use the normal named
`gear.job_abilities` path. PUP's module covers player abilities, not autonomous
automaton actions; random Sic moves are not command-correlated Ready events.

#### SMN: named Blood Pact Rage and Ward sets

In `settings/<character>/events/smn.vars.json`, configure avatar summoning
separately from Rage and Ward. Put named pact overrides inside the corresponding
`rage` or `ward` object:

```json
{
  "vars": {
    "gear": {
      "summoning": {
        "avatar": {"mid": {"body": {"name": "Your Summoning Body"}}},
        "rage": {
          "pre": {"hands": {"name": "Your Pact Recast Hands"}},
          "mid": {
            "body": {"name": "Your Rage Body"},
            "hands": {"name": "Your Rage Hands"}
          },
          "Flaming Crush": {
            "mid": {
              "head": {"name": "Your Flaming Crush Head"},
              "ring1": {"name": "Your Flaming Crush Ring"}
            }
          },
          "Predator Claws": {
            "mid": {"body": {"name": "Your Physical Pact Body"}}
          }
        },
        "ward": {
          "pre": {"hands": {"name": "Your Pact Recast Hands"}},
          "mid": {"body": {"name": "Your Ward Body"}},
          "Hastega II": {
            "mid": {
              "head": {"name": "Your Hastega Head"},
              "feet": {"name": "Your Hastega Feet"}
            }
          },
          "Earthen Armor": {
            "mid": {"body": {"name": "Your Earthen Armor Body"}}
          }
        }
      }
    },
    "post_equip": {"enabled": true, "restore_snapshot": true}
  }
}
```

For Flaming Crush, the general Rage mid set applies first, then its named head
and ring overlay. Predator Claws instead overrides the general body's slot.
Hastega II and Earthen Armor follow the same pattern within Ward. Named entries
also accept `pre`, and do not require a general set to be configured. These are
gear-layout examples; replace the placeholder items with your chosen pieces.

Pet pre is player-command initiation; mid is observed pet execution; post is
result/failure cleanup. A lifecycle can go directly from pre to post, so gear
restoration must not assume mid ran. General/named `pet_abilities` overrides
follow the job module unless an earlier rule stops processing.

For example, `gear.pet_abilities["Flaming Crush"].mid` is another supported
named override, applied after the SMN-specific `gear.summoning.rage` rules.
Use one location unless you intentionally want another layer.

#### BST: named Ready sets

In `settings/<character>/events/bst.vars.json`, use
`gear.beastmaster.ready[<English ability name>].pre/mid` for named Ready moves:

```json
{
  "vars": {
    "gear": {
      "beastmaster": {
        "ready": {
          "pre": {"hands": {"name": "Your Ready Recast Hands"}},
          "mid": {
            "body": {"name": "Your Ready Body"},
            "feet": {"name": "Your Ready Feet"}
          },
          "Razor Fang": {
            "mid": {
              "head": {"name": "Your Razor Fang Head"},
              "ring1": {"name": "Your Razor Fang Ring"}
            }
          },
          "Tail Blow": {
            "mid": {"body": {"name": "Your Tail Blow Body"}}
          }
        }
      }
    },
    "post_equip": {"enabled": true, "restore_snapshot": true}
  }
}
```

The general pre set applies before the player's command is released. On observed
pet execution, the general Ready mid set applies, followed by the matching named
override. Razor Fang adds a head and ring; Tail Blow replaces the general body.
Named `pre` entries can similarly overlay the general pre set. All requests
within a phase are batched, so intermediate sets do not require separate swaps.

The module matches `pet_abilities` of type `Monster`; it does not turn autonomous
pet attacks or random Sic moves into named Ready lifecycles. Generic
`gear.pet_abilities[<name>].pre/mid` overrides can add a final layer afterward.
Restore-first handles partial idle/battle sets at post, including failure paths
where mid never ran. Earlier `meta.stop` rules can skip later named overrides;
leave stopping unset for normal general-then-specific layering.

#### RUN: runes, wards, and effusions

In `settings/<character>/events/run.vars.json`, organize ability enhancement
sets by resource type. Each group accepts a general `pre` set and named `pre`
overrides:

```json
{
  "vars": {
    "gear": {
      "runefencer": {
        "runes": {
          "pre": {"body": {"name": "Your Rune Ability Body"}},
          "Ignis": {"pre": {"hands": {"name": "Your Ignis Hands"}}}
        },
        "wards": {
          "pre": {"neck": {"name": "Your Ward Necklace"}},
          "Vallation": {"pre": {"body": {"name": "Your Vallation Body"}}},
          "Valiance": {"pre": {"body": {"name": "Your Valiance Body"}}},
          "Pflug": {"pre": {"feet": {"name": "Your Pflug Feet"}}}
        },
        "effusions": {
          "pre": {"neck": {"name": "Your Effusion Necklace"}},
          "Gambit": {"pre": {"hands": {"name": "Your Gambit Hands"}}},
          "Rayke": {"pre": {"feet": {"name": "Your Rayke Feet"}}}
        }
      }
    },
    "post_equip": {"enabled": true, "restore_snapshot": true}
  }
}
```

These are layout examples with placeholder items. `runes` matches
`event.type == 'Rune'`, `wards` matches `'Ward'`, and `effusions` matches
`'Effusion'`. This grouping does not automatically infer appropriate gear from
the currently harbored runes. The resource's `event.element` is not a reliable
description of the rune-dependent effect.

General group gear applies first, then its named override. The common
`gear.job_abilities.pre` and `gear.job_abilities[<name>].pre` rules run afterward,
so their overlapping slots can override RUN-specific gear. Earlier `meta.stop`
can prevent those later rules. Individual abilities outside these three groups
remain configurable through the common named ability map. RUN spell gear uses
the normal shared spell categories and named overrides.

#### SCH: arts and stratagem overlays

For SCH, use `gear.scholar.light_arts.pre/mid` and
`gear.scholar.dark_arts.pre/mid` for arts-dependent gear, including the respective
Addendum buffs. Use the ordered [stratagem example](#scholar-stratagems) for
Rapture/Ebullience-style overlays. SCH overlays run after common spell rules.

### Add custom rules and initialization

Contributions let a vars file extend stock behavior at before/after hooks:

```json
{
  "vars": {"announce_cures": true},
  "contributions": {
    "loading.actions.after": [
      {"commands": ["setVar('ready_message', 'Cure rules initialized')"], "id": "personal-init"}
    ],
    "spells.pre.before": [
      {
        "when": ["vars.announce_cures and event.curing"],
        "commands": ["log(vars.ready_message, event.name)"],
        "id": "personal-cure-announcement"
      }
    ]
  }
}
```

Loading runs once per successful event load/reload; its successful variable
changes initialize the copies used by later lifecycles. Ordinary lifecycle
`setVar` calls do not persist into the next lifecycle. Keep scripts short and
non-yielding. For literal Windower command arrays, use `sendWindowerCommands`.

For item-specific gear, see the [optional Hairpin contribution](#example-optional-dark-element-headgear).
For existing-rule replacement, disabling by ID, priorities, and custom hooks,
see [contribution controls](#disable-or-replace-a-stock-rule). IDs replace at
load time; they are not first-match groups. Before/after contributions can be
skipped by earlier stops. Use a set's `meta.stop` only when later phase rules
really should be skipped; avoid stopping post cleanup.

### Check which files and rules are active

1. Run `//gbt events s` to inspect the selected entry point, imports, and vars files.
2. Run `//gbt events r` after editing JSON; `//gbt events r -r` preserves an
   explicitly selected file. Use `//gbt events r -e common` to temporarily choose
   a different entry point, or full `//gbt r` to return to automatic selection.
3. Add `-v` to export final variables, expanded rules, IDs, and source metadata.
4. Check exact English names, the correct variable phase/path, and earlier stops.
   A closer empty rule file intentionally suppresses shipped defaults.

If casting gear remains, review partial sets and restore-first behavior. If
mid gear misses fast casts, put essential pieces in pre. JSON compilation cannot
verify ownership or in-game timing. See [troubleshooting](#checking-your-setup)
and the [event guide](events.md#reloading-and-troubleshooting) for failure handling.

## Files and layering

For variable syntax and merging basics, see [Variables](variables.md).

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

### Resource-name aliases in named gear sets

Stock loading rules accept either spelling of known English resource-name pairs,
such as `Nat. Meditation` and `Nature's Meditation`, in these named gear tables:

- `gear.spells` (final named overrides)
- `gear.spells.blue`
- `gear.spells.magic_burst`
- `gear.enemy_spells`
- `gear.enemy_abilities`
- `gear.pet_abilities`

Define one spelling per action; conflicting definitions under both aliases are
rejected. These modules explicitly call the general `resourceAliasKeys` helper
during loading. Other names, variable tables, item names, and resource IDs are
not rewritten. Re-expand a table if code adds/replaces alias keys later.
`event.matches(nameOrId)` accepts either action spelling independently of this
gear configuration. See [alias pairs and custom usage](functions.md#english-resource-name-aliases).

### Equipment slot names

Use these keys inside any gear set. Slot names are case-insensitive; lowercase
is the convention used in the examples.

| Slot key | Equipment position | Accepted alias |
|---|---|---|
| `main` | Main-hand weapon | — |
| `sub` | Off-hand weapon, shield, or grip | — |
| `range` | Ranged weapon or instrument | — |
| `ammo` | Ammunition | — |
| `head` | Head | — |
| `body` | Body | — |
| `hands` | Hands | — |
| `legs` | Legs | — |
| `feet` | Feet | — |
| `neck` | Neck | — |
| `waist` | Waist | — |
| `ear1` | Left ear | `left_ear` |
| `ear2` | Right ear | `right_ear` |
| `ring1` | Left ring | `left_ring` |
| `ring2` | Right ring | `right_ring` |
| `back` | Back | — |

Use one key per physical slot; do not define both `ear1` and `left_ear`, for
example. `meta` is reserved set metadata, not an equipment slot. Omitted slots
are left alone, so both small overlays and full sets use the same format.

### Item values and metadata

To reuse a full piece definition from another set, use a variable reference:

```json
{
  "vars": {
    "gear": {
      "battle": {
        "head": {"name": "Your Shared Head", "augments": ["Your Augment"]}
      },
      "spells": {
        "enhancing": {
          "mid": {"head": {"var": "vars.gear.battle.head"}}
        }
      }
    }
  }
}
```

The reference uses the entire current value, including augments or an ordered
candidate array; it does not just copy the name. `vars.` is optional in the path.
Lookup uses the current scope at equipment-request time without modifying the
source definition. A missing value leaves the slot alone. A reference object
must contain only `var`; cycles are rejected. See [equipment references](equipment.md#reuse-a-configured-piece)
for helper usage and snapshot behavior.

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
| `gear.job_abilities.pre` | General job-ability pre set, before the generic named override |
| `gear.job_abilities[<name>].pre` | Named job-ability set |
| `gear.rolls` | Direct gear set for Corsair rolls and Double-Up; there is no `.pre` suffix |
| `gear.pet_abilities[<name>].pre` / `.mid` | Named pet-command/ability overrides |
| `on_battle.windower_commands` | Array of literal Windower commands after the battle-enter gear rule |
| `on_idle.windower_commands` | Array of literal Windower commands after the idle-enter gear rule |
| `post_equip.enabled` | Enable stock post restoration and idle/battle gear; default `true` |
| `post_equip.restore_snapshot` | Restore starting gear before the post idle/battle overlay; default `false` |

Common spell categories are `curing`, `divine`, `enfeebling`, `enhancing`, `elemental`, and
`magic_burst`. GEO adds `geomancy`; BLU adds `blue`. There is no general
`gear.spells.mid` rule: use categories or named sets for result-enhancing gear.

`curing` includes Cure, Curaga, Cura, and Full Cure, but not all Healing Magic.
`elemental` describes the Elemental Magic skill. `magic_burst` additionally requires
`canMagicBurst(event)` for the current target/window. A spell-specific set can
run without its category's general set being configured.

### General job-ability gear

Set `gear.job_abilities.pre` for gear shared by job abilities, then use
`gear.job_abilities[<name>].pre` for named overrides. Both requests join the
same pre batch, with the named set winning overlapping slots.

The general set runs at the position of `lib/job_abilities/all`'s own rules.
Imported roll rules run first, so general job-ability gear can override
`gear.rolls`; the named ability set follows the general set. Specialized job
modules may also run earlier. This is not an unconditional first step for all
job-ability modules. A general set's `meta.stop` skips the later named override.

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

Configure any item-specific behavior through your own gear variables or contributions, with
appropriate restoration for slots absent from idle/battle sets.

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
| `run.json` | `gear.runefencer.runes`, `.wards`, `.effusions`: each accepts `.pre` and `[<name>].pre` |
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
  With Burst Affinity active and `canMagicBurst(event)` true, shared
  `gear.spells.magic_burst.pre` / `.mid` gear overlays Blue Magic gear, followed by
  `gear.spells.magic_burst["Spectral Floe"].pre` / `.mid` (or another spell's
  English name). Named burst sets work without a general burst set. General and
  named Blue Magic sets run first; final spell-name overrides still run afterward.
  `canMagicBurst` also requires a matching `monster_abilities` resource by English
  spell name with `skillchain_a == nil`. A present field, including an empty
  string, identifies a physical ability and prevents burst gear; missing resource
  matches are excluded as well.
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

### Equip gear for your battle target's actions

Every stock entry point except `empty.json` imports `lib/enemy_spells/all` and
`lib/enemy_abilities/all`. Configure named `pre` / `post` sets under
`gear.enemy_spells` or `gear.enemy_abilities`; quoted numeric IDs provide a later,
more specific override in the same table:

```json
{
  "vars": {
    "gear": {
      "enemy_spells": {
        "Firaga III": {
          "pre": {"body": {"name": "Your Magic Defense Body"}},
          "post": {"body": {"var": "gear.battle.body"}}
        }
      },
      "enemy_abilities": {
        "Mortal Ray": {
          "pre": {"neck": {"name": "Your Defensive Necklace"}},
          "post": {"neck": {"var": "gear.battle.neck"}}
        }
      }
    }
  }
}
```

Replace placeholder gear and configure the referenced replacement pieces. Stock
handlers require `bt and event.actor and event.actor.id == bt.id` in both phases.
Name-based gear runs first, ID-specific gear second; these optional sets batch
together and support `meta.stop` and `lock_when` as usual. Named keys use English
resource spelling or a supported English name alias. For custom conditions,
prefer `event.matches(nameOrId)`.

`pre` observes the start; it cannot pause the enemy or cancel its action. Posts
may occur without pre, and lost result packets are not synthesized. If your
battle target changes, the previous enemy's post no longer passes the stock
filter. Consequently, these are explicit gear requests, not paired snapshot
push/pop operations. Ordinary gear changes may replace the pieces later.
Contributions such as `enemy_spells.pre.after` can use different actor filters
or execute custom code. See [enemy events](events.md#enemy-spells-and-abilities).

### Configure buff-specific gear

Every stock entry point except `empty.json` imports `lib/buffs/all`. Define
`gear.buffs["English buff name"].added` / `.removed` in your `.vars.json` file.
For more specific overrides, use `gear.buffs["buff id"].added` / `.removed`:

```json
{
  "vars": {
    "gear": {
      "buffs": {
        "Doom": {
          "added": {
            "ring1": {"name": "Eshmun's Ring", "lock_when": ["hasBuff('Doom')"]}
          },
          "removed": {
            "ring1": {"name": "Your Normal Ring"}
          }
        },
        "15": {
          "added": {
            "ring2": {"name": "Your Other Doom Ring", "lock_when": ["hasBuff('Doom')"]}
          },
          "removed": {
            "ring2": {"name": "Your Normal Second Ring"}
          }
        }
      }
    }
  }
}
```

Replace placeholder item names with your equipment. JSON object keys are strings,
so ID buckets use quoted IDs such as `"15"`. Name-based gear runs first, then
ID-specific gear. ID sets override overlapping slots and retain other pieces
from the name set. Both sets are optional and use the same batched equipment
phase. There is no automatic snapshot restoration for buff notifications.

Buff gear names are case-insensitive (`Doom`, `doom`, and `DOOM` are equivalent).
Do not define multiple keys differing only in case. The stock buff module
normalizes its immediate gear keys during loading using the general
`caseInsensitiveKeys` helper; other stock gear tables keep their existing key
behavior. If code replaces or adds mixed-case buff keys later, normalize that
table again with `setVar('gear.buffs', caseInsensitiveKeys(vars.gear.buffs))`.

Names use English resources. A name can match multiple buff IDs; an ID set can
also run when the name is unknown. Sets support equipment candidates, variable
references, `lock_when`, and `meta.stop` like other stock gear sets. A name set
with `meta.stop=true` intentionally prevents the later ID override and further
handlers in that phase. Prefer leaving it unset when layering gear or cleanup.

### React to buffs without replacing the stock entry point

For behavior beyond the gear sets above, add rules to a character/job `.vars.json` file using `buffs.added.after` and
`buffs.removed.after`. For example, equip a Doom-specific ring and protect it
from other Gambit gear changes while Doom remains active:

```json
{
  "contributions": {
    "buffs.added.after": [
      {
        "when": ["event.matches('Doom')"],
        "commands": ["equipMany({ring1={name=\"Eshmun's Ring\", lock_when={\"hasBuff('Doom')\"}}})"],
        "id": "doom-ring"
      }
    ],
    "buffs.removed.after": [
      {
        "when": [
          "event.matches('Doom')",
          "me.is_engaged and vars.gear.battle or (not me.is_engaged and vars.gear.idle)"
        ],
        "commands": ["equipMany(me.is_engaged and vars.gear.battle or vars.gear.idle)"],
        "id": "doom-restore"
      }
    ]
  }
}
```

Your idle/battle set must include a replacement for `ring1`; partial sets leave
unspecified slots alone. The lock expires when Doom is absent and the replacement
request is checked. These notifications concern your own character and run even
when automation is disabled. They do not replay already-active buffs on reload.
Use `event.id` rather than `event.name` when multiple buffs share a name. See
[buff events](events.md#buffs-received-and-removed) for fields and behavior, and
[conditional locks](equipment.md#conditional-slot-locks) for equipment ownership.

### Stock example: shared post-equipment rules

The shipped [post-equipment module](../events/lib/post-equip.json) contributes
one ordered rule list to four built-in hooks:

```json
{
  "contributions": {
    "spells.post.after, job_abilities.post.after, pet_abilities.post.after, weapon_skills.post.after": [
      {
        "when": ["vars.post_equip.enabled", "vars.post_equip.restore_snapshot"],
        "commands": ["equipRestore()"],
        "id": "post-equip-restore"
      },
      {
        "when": ["vars.post_equip.enabled", "me.is_idle and vars.gear.idle"],
        "commands": ["equipMany(vars.gear.idle)"],
        "id": "post-equip-idle"
      },
      {
        "when": ["vars.post_equip.enabled", "me.is_engaged and vars.gear.battle"],
        "commands": ["equipMany(vars.gear.battle)"],
        "id": "post-equip-battle"
      }
    ]
  }
}
```

This is an excerpt of the shipped module, not an additional configuration to
copy into your vars file. The module also supplies the variable defaults.

Comma-separated hook names apply the same list to each destination at load
time; no `csv(...)` wrapper is needed. Each action type gets restoration first,
then the applicable state set. Shared IDs are safe because ID replacement is
scoped to each section/phase.

The `.after` hooks place these rules after ordinary post handlers, independently
of the module's import position. Restoration and state gear share the post
batch, so a partial idle/battle set overlays the baseline without intermediate
equipment cycles. `equipRestore()` hides the stack details and safely does
nothing when no lifecycle baseline remains.

Set `post_equip.enabled` to `false` to skip all three rules. This does not disable
status-enter gear or lifecycle-managed `use_equipment_snapshot` restoration.
The rules deliberately do not honor gear-set `meta.stop`: stopping post could
skip other cleanup contributions. Earlier stop rules can still skip these hooks,
and other after contributions follow their normal ordering; `.after` does not
guarantee the final operation under every extension.

### Personal contributions

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

### Example: optional Dark-element headgear

Pixie Hairpin +1 is a useful example of adding item-specific behavior through
contributions. This is opt-in and is not included in the stock rules:

```json
{
  "vars": {
    "post_equip": {"enabled": true, "restore_snapshot": true}
  },
  "contributions": {
    "spells.mid.after": [
      {
        "when": ["event.target.is_mob", "event.element_name == 'Dark'"],
        "commands": ["equip('head', 'Pixie Hairpin +1')"],
        "id": "pixie-hairpin-for-darkness"
      }
    ]
  }
}
```

Place this in a matching `.vars.json` file. The stock post-equipment module's
restore-first option returns the head slot to its original item before applying
idle/battle gear, even when those sets omit a headpiece. A missing Hairpin leaves
the slot unchanged. Earlier phase stops can prevent this after contribution.

### Disable or replace a stock rule

IDs resolve at load time across a final phase. To remove the stock buff-overlay
mid rule:

```json
{
  "contributions": {
    "spells.mid.after": [
      {"disabled": true, "id": "spells-buff-overlays-mid"}
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
`post-equip-restore`. Category IDs include `spells-curing-mid` and
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
