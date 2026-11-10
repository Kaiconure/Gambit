# Scoped action variables

For definitions, references, priorities, and CSV key expansion, start with
[Variables](variables.md). This page covers private action scopes.

Use `with_vars` on an import or a normal action to provide private configuration
and persistent state without changing the shared library:

```json
{
  "import": "buffs/haste-cycle",
  "with_vars": {
    "haste_cycle": { "targets": ["me"] }
  }
}
```

This captures the entire `haste_cycle` subtree. Its initial value merges the
override with the parent's current values when the action is evaluated.
For example, a duration-only override preserves an angle changed by tank status
after loading. The captured values stay stable through conditions, commands,
and yields for that evaluation.
Objects merge recursively; arrays replace. An empty object/array replaces with
an empty table. Use ordinary variable names, without `!` or `^` priority prefixes:
scope overrides already take precedence. JSON null is discarded by the JSON
loader; use `"$object.null"` to explicitly initialize a captured value to nil.

`csv(...)`, `array.append(...)`, and `array.remove(...)` are expanded when the
scope snapshot is refreshed for an action evaluation. For example:

```json
{
  "import": "use-dispel",
  "with_vars": {
    "use_dispel": {
      "array.append(buffs)": ["Blaze Spikes", "Howl"],
      "array.remove(buffs)": ["Protect"]
    }
  }
}
```

The operations use the parent's current array and produce a private scoped
copy. Distinct appends, removal of all matches, warnings for non-arrays, and
remove winning over append at equal priority in one block match ordinary/event
variable behavior. CSV-generated subtrees are independent too. Top-level scope
names still cannot use `!` or `^`; nested definitions support their normal
priority syntax. Explicit empty tables retain their scoped replacement behavior.

All actions beneath this import share its state, including multiple references
on one import statement. Separate import statements create separate instances.
Nested `with_vars` blocks create child scopes; their captured subtrees are
independent of the parent's copies. Normal actions can use the same property.
Preconditions, `when`, `commands`, and `else` all see the action's effective scope.

## Reading and writing

Direct access (`vars.haste_cycle.targets`) and `getVar`/`setVar` resolve to the
nearest scope owning the top-level variable. Nested table writes, field helpers,
increment/decrement and cycle helpers use that same state. Writes persist across
executions until actions are recompiled/reloaded. Uncaptured variables continue
to resolve through parents to global state, including changes made globally.

`getVarGlobal(name)` and `setVarGlobal(name, value)` access only global state.
They do not update an evaluation's captured copies. A later evaluation refreshes
inherited fields from the live parent while preserving persistent local edits.
Outside a local scope, normal and global
helpers have equivalent behavior. As with ordinary Lua assignments, explicitly
assigning a table obtained from another scope shares that table reference; the
initial scoped copies themselves are independent.

`getOriginalVar` returns a copy of the current evaluation's baseline: live parent
values plus configured overrides, before persistent local edits are reapplied.
`resetVar` restores that value within the owning scope. Local edits are detected
by comparing with the previous baseline; assigning an unchanged value does not
pin that field against future parent updates. Arrays are compared as whole values.
Reloading rebuilds all
scope instances from the newly loaded configuration.

## Lua tables

Captured subtrees are ordinary tables: `pairs`, `ipairs`, array length, and table
operations work normally on `vars.haste_cycle` and its children. The scoped
`vars` root is a lookup view. `pairs(vars)` inside an action expression is
supported, but external Lua utilities using native Lua 5.1 `pairs`, `next`,
`rawget`, or `rawset` on that root bypass the view. Pass the relevant subtree to
such utilities instead. Do not replace the context's `vars` root.

## Example: self-only Haste configuration

The shipped haste library (`buffs/haste-cycle`) reads `vars.haste_cycle.targets`. In your own action file, you could import it with private
targets in `idle` so that you keep yourself hasted before entering battle, 

```json
{
  "vars": {
    "haste_cycle": {
      "targets": ["me", "Tanks", "Melee"]
    }
  },
  "battle": [
    {
      "import": "buffs/haste-cycle"
    }
  ],
  "idle": [
    {
      "import": "buffs/haste-cycle",
      "with_vars": {
        "haste_cycle": {"targets": ["me"]}
      }
    }
  ]
}
```

You could further restrict the idle haste action with a `precondition`, perhaps saying that it should only act when you're in a level-restricted battlefield.
