# Action slots

## Contribution replacements and shorthand

Prefix a contribution name with `^` to supply a fallback definition. If any
ordinary or `!` definition exists for that name, all `^` definitions are ignored,
even if they are more specific. Explicit empty arrays also suppress defaults.
Otherwise only the closest `^` definition is selected using the precedence below;
equal priorities use first discovery. Fallback definitions do not merge together.
Selection is at load time: disabled actions or failing preconditions do not revive
discarded defaults. An empty selected fallback still counts as present for slot
alternative selection.

For example, `"^geo/black-magic-burst": [{"import": "nukes/black-magic-burst"}]`
provides default actions which an ordinary definition can replace. Comma-separated
keys support `^` independently on each name. References omit prefixes. Duplicate
normalized names across ordinary, `!`, and `^` definitions are rejected within a
file, as are combined prefixes such as `!^name`.

Prefix a contribution name with `!` to replace contributions below it in
precedence. For example, `"!black-magic-burst": []` suppresses less-specific
defaults. Higher-priority additions remain; when multiple replacements exist,
the highest-priority replacement is the boundary. Empty replacements count as
present for fallback selection. An ordinary empty array remains additive.

Contribution keys may contain comma-separated names, each with its own optional
`!`: `"!rdm/black-magic-burst, !geo/black-magic-burst": []`. Whitespace around
each name is trimmed. This registers separate definitions, not alternatives.
Empty names and duplicate normalized names within a file are rejected, including
both ordinary and `!` forms of the same name. Slot references omit the `!`.

Precedence is active namespace before ancestors, followed by non-namespace
settings and shipped defaults. Within each namespace, character files precede
shared files. Outside namespaces, character settings precede shared settings,
then shipped files. Within each of these locations, entry points and explicit
libraries precede job common files, then role common files, then general common
files (including `lib/common.json`). Equal priorities retain loader discovery
order; the first replacement wins. This applies to additive ordering too.

Slots let imported libraries and namespace common files contribute actions without
copying job entry points. A slot is a placeholder, not a runtime action.

An entry point chooses placement:

```json
{
  "battle": [
    { "import": "reactions/use-stun" },
    { "slot": "encounter-emergency" },
    { "import": "heals/main-cure-sequence" }
  ],
  "idle": [
    { "slot": "encounter-emergency" }
  ]
}
```

A common file or another imported file supplies a top-level `contributions` object:

`slot` and `slots` both accept a string or an ordered array. For example,
`{ "slots": ["black-magic-burst", "black-magic-nuke"] }` expands all burst
contributions before all nuke contributions. If both keys are supplied, `slot`
entries come first, followed by `slots` entries. Empty arrays insert nothing;
repeated names create separate occurrences. Placeholder conditions and scopes
apply to every name in the chain.

An entry may itself be an ordered fallback array:

```json
{ "slots": [["geo/black-magic-burst", "black-magic-burst"], "black-magic-nuke"] }
```

The outer list expands sequentially. Each inner list selects the first name with
registered contributions, then expands all contributions under that name using
the usual namespace ordering. Selection happens at load time, after collection;
disabled actions or failing runtime preconditions never trigger fallback.
An explicitly empty contribution array counts as present and prevents selection
of later alternatives. It does not erase other contributions under the same name.
If no alternative exists, or the inner list is empty, nothing is inserted.
Unselected alternatives do not produce unmatched-slot warnings. Only one level
of fallback arrays is supported; deeper arrays are invalid. Both `slot` and
`slots` support this syntax. Slashes in names have no special meaning.

```json
{
  "contributions": {
    "encounter-emergency": [
      {
        "import": "reactions/encounter-response",
        "precondition": "not evaluateAllConditions(vars.primary_tank_precondition)",
        "with_vars": { "response": { "distance": 12 } }
      }
    ]
  }
}
```

The example import is illustrative; create that library before using it.
Contributions accept ordinary actions or imports, including `import`/`imports`
arrays, filters, preconditions, and `with_vars`.

All ordinary imports are loaded before slots expand. Every matching slot receives
all contributions. More-specific namespaces contribute before their ancestors;
non-namespace files follow namespace files. Within the same namespace priority,
files retain deterministic loader discovery order (the existing loader visits
action lists and imports in reverse order). Each contribution array retains its
written order. Use separate slots to impose finer ordering rather than relying on
discovery order. Slot names are case-sensitive.

A file's contributions are collected once per importing variable scope. Importing
the same file repeatedly without separate scopes does not multiply contributions;
the first discovered import supplies its inherited conditions. Prefer defining
contributions in common files or importing their defining library once.

Each slot occurrence creates independent action instances, timers, enumerators,
error-disable state, and contribution-owned variable scopes. Descendants of a
contributed import share that occurrence's scope, just as ordinary imported
descendants do. Global variables remain shared. A scope surrounding the slot also
remains shared with its original descendants; contribution scopes nest inside it.
Slot conditions, contributing-import conditions, and action conditions all apply.

Repeated slot names are allowed, even in one section. They execute as separate
instances and are not deduplicated. Empty slots disappear. A contribution without
a matching enabled slot generates a warning. No existing job automatically gains
a slot: add placeholders at the desired priorities.

Slots may have `precondition`, `with_vars`, `filter`, or `disabled`, but cannot also
be commands or imports. Contributions cannot contain slots, import libraries that
contain slots, or import further contribution definitions. Such configurations
fail validation rather than recursively expanding. Imported `loading` actions and
functions retain their ordinary destination semantics.
