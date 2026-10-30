# Variables

Variables hold configuration and runtime state for Lua conditions and commands.
Define them in JSON under `vars`, then read them through the context's `vars`
object. Normal actions and events have separate variable stores.

## Define and reference values

An action file can define configuration alongside its actions:

```json
{
  "vars": {
    "healing": {"enabled": true, "threshold": 60},
    "targets": ["me", "bt"],
    "message": "Healing enabled"
  },
  "actions": [
    {
      "when": ["vars.healing.enabled and me.hpp < vars.healing.threshold"],
      "commands": ["log(vars.message)"]
    }
  ]
}
```

Event rule files also accept `vars`. Event-only variable files use the name
`<job>.vars.json` or a matching group name such as `(mages).vars.json` under
an events directory. See [stock-event configuration](stock-events.md) for paths
and supported gear settings. Normal action configuration follows the action
entry-point/import system; event vars files are a separate feature.

| JSON value | Lua reference/example |
|---|---|
| Nested object | `vars.healing.threshold` |
| Array | `vars.targets[1]` (Lua indexes start at 1) |
| Key with spaces | `vars.gear.weapon_skills['Savage Blade']` |
| Key from an event | `vars.gear.spells[event.name]` |
| Boolean | `vars.healing.enabled` |
| Missing value | `nil` |

Objects and arrays become Lua tables. Accessing a missing leaf returns nil;
accessing a child of nil causes an error. Guard optional parents:

```lua
vars.gear.spells[event.name] and vars.gear.spells[event.name].mid
```

Lua treats only `false` and `nil` as falsey. Zero, empty strings, and empty
tables are truthy. For an array, `#vars.targets > 0` checks whether it has entries;
array length is not a count of an object's named keys.

### Strings versus expressions

The field containing a JSON string determines how Gambit uses it. Strings in
`when` are evaluated as Lua expressions; strings stored under `vars` are data
until something explicitly evaluates them.

For example, this action checks HP directly:

```json
{
  "actions": [
    {
      "when": ["me.hpp < 60"],
      "commands": ["log('HP is below 60%')"]
    }
  ]
}
```

You can also store the expression for reuse, then evaluate it explicitly:

```json
{
  "vars": {"low_hp_condition": "me.hpp < 60"},
  "actions": [
    {
      "when": ["evaluateAll(vars.low_hp_condition)"],
      "commands": ["log('HP is below the threshold!')"]
    }
  ]
}
```

Writing `"when": ["vars.low_hp_condition"]` would instead evaluate only the
variable lookup. Its result is the string `"me.hpp < 60"`, which is truthy
regardless of current HP. Gambit does not automatically evaluate that returned
string a second time. Similarly, `log(vars.low_hp_condition)` prints the stored
text rather than the result of the HP comparison.

Strings in `commands` are executed as Lua code too, but string values read by
that code remain data. See [evaluation helpers](functions.md#evaluating-reusable-conditions)
for evaluating stored expressions and condition arrays.

## Combining definitions

Definitions from applicable files merge at load time:

- Nested objects combine recursively.
- Arrays use the winning definition rather than concatenating.
- At equal priority, the earlier definition in the loader's precedence order
  wins. The action/event search and import rules determine that order.
- A prefix changes priority: `!name` is prioritized, `name` is ordinary, and
  `^name` is a fallback/default. Prefixes are removed from runtime keys.
- Prefix priority is inherited by supplied children unless a child has its own
  prefix. It does not automatically erase unrelated object fields.

```json
{
  "vars": {
    "^healing": {"enabled": true, "threshold": 60},
    "!message": "My preferred message"
  }
}
```

Both values are referenced without prefixes: `vars.healing` and `vars.message`.
Competing prioritized definitions keep the earlier one and warn if they differ.
In event rule files, inline vars are already implicit fallback defaults; event
vars files provide ordinary configuration unless explicitly prefixed.

### Clearing values

JSON `null` is discarded by the JSON loader. It is useful for showing an
unconfigured field in a sample, but does not reliably clear an inherited value.
Use explicit marker strings when that is your intent:

| Marker | Loaded value |
|---|---|
| `"$object.null"`, `"$table.null"` | nil; remove the value |
| `"$array.empty"`, `"$object.empty"`, `"$table.empty"` | An empty Lua table |

```json
{
  "vars": {
    "targets": "$array.empty",
    "message": "$object.null"
  }
}
```

Ordinary clearing markers can clear earlier ordinary/default definitions, while
prioritized definitions remain protected. Empty `{}` is not a general-purpose
way to erase an inherited object; use an explicit clearing marker.

## Expand multiple keys with `csv(...)`

Use `csv(...)` as a JSON variable key to give several names the same initial
value. This is load-time syntax, not a Lua function call:

```json
{
  "vars": {
    "gear": {
      "weapon_skills": {
        "csv(Savage Blade, Shining Blade)": {
          "pre": {"ring1": {"name": "Rufescent Ring"}}
        }
      }
    }
  }
}
```

The loader creates `vars.gear.weapon_skills['Savage Blade']` and
`vars.gear.weapon_skills['Shining Blade']`. Each gets an independent copy;
changing one later does not modify the other.

- Expansion works recursively in both normal-action and event variables.
- Names are case-sensitive and surrounding whitespace is trimmed.
- Prefixes work: `!csv(A, B)` and `^csv(A, B)` apply their priority to both keys.
- An explicit sibling key wins over a generated key at the same priority.
- Malformed syntax, empty names, or overlapping CSV declarations at the same
  priority in one object cause loading errors. There is no escaping for commas
  inside names and no range/wildcard expansion.
- Expansion applies to variable definitions, not arbitrary event sections or
  contribution keys. Contributions have their own comma-separated destination
  syntax, without a `csv(...)` wrapper.

## Change values at runtime

Use variable helpers in Lua commands:

```lua
getVar('healing.threshold')
setVar('healing.threshold', 50)
getOriginalVar('healing.threshold')
resetVar('healing.threshold')
```

For these helpers, the leading `vars.` in the path string is optional and
implicit: `getVar('healing.threshold')` and
`getVar('vars.healing.threshold')` refer to the same value. The same applies to
`setVar`, `getOriginalVar`, and `resetVar`.

Direct Lua access requires the `vars` object: use `vars.healing.threshold`,
not `healing.threshold`. The latter refers to a separate context name rather
than looking inside the variable store.

`getVar` safely traverses nested paths, returning nil if a parent is missing
or is not a table. For example, `getVar('vars.a.b.c.d')` avoids the explicit
guards needed for direct access:

```lua
-- Preferred for an optional nested value:
getVar('vars.a.b.c.d')

-- Direct access needs guards when intermediate values may be nil:
vars.a and vars.a.b and vars.a.b.c and vars.a.b.c.d
```

These paths are strings, unlike direct Lua indexing. `getOriginalVar` returns
a copy of the initial value; `resetVar` restores it. Prefer `setVar` for runtime
updates to keep variable writes consistent. Direct field assignment such as
`vars.healing.threshold = 50` is supported, but is not the recommended pattern.
Assigning an
existing table shares its reference; it does not make an independent copy.

Runtime changes do not save JSON. Reloading rebuilds variables from the files.
Do not replace the `vars` root or use the reserved `vars._` internal subtree.

### Lifetime and scope

| Context | Lifetime |
|---|---|
| Normal action variables | Shared runtime state until settings/actions are reloaded |
| Action `with_vars` | Private captured subtrees, persistent across that branch's executions |
| Action-event variables | One isolated lifecycle, shared by its pre/mid/post |
| Status/zone notification variables | One notification |
| Event loading actions | Successful changes initialize defaults copied into subsequent events |

`getVar` and `setVar` use the effective scope. For normal actions with private
`with_vars` scopes, `getVarGlobal` and `setVarGlobal` bypass captured copies;
they do not mean cross-addon storage or saving to disk. Event contexts remain
isolated from normal action variables, including when using global helpers.

For private action state, see [scoped variables](scoped-variables.md). For event
initialization and merging, see [events](events.md#variables-and-their-lifetime).
