Return to the [main documentation page](../readme.md).

---

# Action Properties

The following properties are available for use in your actions, broken down by category. These are Lua variables that can be referenced at any time from your action `when` or `commands` blocks.

## Targets

These represent targetable mobs, players, and trusts on the map.

- `t`, `bt` - The current battle target. This is _not_ necessarily the same as your current target `<t>` in-game. It is also not necessarily the same as your `<bt>` target, as it will be set prior to entering battle for use in idle/pull actions as well. If no target has been selected, it will be nil. Otherwise, each of the following properties will be available to you:
  - `name` - The mob display name.
  - `hpp` - The mob's remaining HP, expressed as a percent from 0 - 100.
  - `id` - The internal FFXI identifier for this mob.
  - `index` - The internal index within the zone for this mob (commonly known, somewhat misleadingly, as the "hex id").
  - `distance` - The distance between you and the mob. For those familiar with the Windower 4 Lua interface, this is the actual distance and not the distance squared.
  - `x`, `y`, `z` - The 3D position of the mob on the map.
- `p0`, `p1`, `p2`, `p3`, `p4`, `p5` - Members of your party, or nil if there is no party member in a given slot. All properties on `t` and `bt` above are available here, in addition to the following:
  - `hp`, `mp` - The party member's actual remaining HP and MP values.
  - `mpp` - The party member's remaining MP, expressed as a percent from 0 - 100.
  - `tp` - The party member's TP.
  - `is_trust` - Determine if this party member is a Trust.
  - `is_player` - Determine if this party member is a player.
- `a10 - a15`, `a20 - a25` - When in an alliance, these represent all members in alliance 1 (`a1`) and alliance 2 (`a2`). All of the properties available for party members also apply to alliance members.
- `me` - This represents yourself. All properties available to party members apply here, in addition to the following:
  - `max_hp`, `max_mp` - Your actual maximum HP and MP values.
  - `main_job`, `sub_job` - The three-letter shorthand name of your main job and sub job (if any).
  - `main_job_level`, `sub_job_level` - The level of your main job and sub job (if any).
  - `level` - Same as `main_job_level`, with less typing required.

## Contextual

### Loaded automation

These fields are also available to panel tracking expressions:

| Field | Meaning |
|---|---|
| `gambit.namespace` | Current loaded namespace |
| `gambit.entrypoint` | Stored automation entry-point name |
| `gambit.entrypoint_path` | Source filename, including `.json` |
| `gambit.entrypoint_relative` | Source path relative to its owning namespace, including `.json`; global paths omit the leading `./` |
| `gambit.entrypoint_name` | Source path with `/` separators and the final `.json` removed |
| `gambit.events` | Active event entry file's basename without `.json`, e.g. `common` or `(mages)` |
| `gambit.events_path` | Active event entry file's source filename, including `.json` |
| `gambit.events_name` | Event source path with `/` separators and the final `.json` removed |
| `gambit.events_relative` | Event source path relative to its owning namespace, including `.json`; global/shipped paths omit the leading `./` |
| `gambit.event_namespace` | Owning namespace folder path of the selected event file, including physical underscore aliases; nil for global/shipped files or no active file |

Entry-point fields can be nil before actions have loaded. For example, a source
file `./settings/Carbonite/actions/pld.json` gives an `entrypoint_name` of
`./settings/Carbonite/actions/pld`.
For a namespace source such as
`./settings/_ns/xp/players/Carbonite/actions/pld.json`, `entrypoint_relative` is
`players/Carbonite/actions/pld.json`. Inherited sources are relative to their own
namespace rather than the currently selected namespace.
The event fields describe the selected event entry point, not its imported
modules, and are nil when no event file is active. They update after event reload.

### Selected resources

Contextual variables are those which are set when certain conditions are met, allowing them to be referenced more easily later on. They would typically be set in the `when` clause and used in the `commands` list, but that's not strictly required.

- `ability` - When `canUseAbility` finds a match (or when `canUse` matches on an ability), this will be set to the ability that triggered the match.
- `effect` - When `hasEffect`, `hasBuff`, or `hasEffectOf` finds a match, this will be set to the effect that triggered the match.
- `item` - When `canUseItem` finds a match (or when `canUse` matches on an item), this will be set to the item that triggered the match.
- `spell` - When `canUseSpell` finds a match (or when `canUse` matches on a spell), this will be set to the spell that triggered the match.

---

Return to the [main documentation page](../readme.md).
