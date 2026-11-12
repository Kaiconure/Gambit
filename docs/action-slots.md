# Action slots

## Inline contributions

Define a slot and its normal contribution together with `actions`:

```json
{
  "slot": "priority-buffs",
  "actions": [
    {
      "when": "not hasBuff('Defender') and canUse('Defender')",
      "commands": "use(me)"
    }
  ]
}
```

This is shorthand for placing `priority-buffs` here and contributing the enclosed actions to it from the same file. It is not a fallback: ordinary contributions append under the existing namespace/file precedence and per-action `priority` rules. At equal source precedence, previously collected contributions precede inline ones. Actions inside the inline array retain their relative order unless their own `priority` changes it. Imports inside `actions` are supported.

Use `"slot": "!priority-buffs"` to give the inline contribution replacement semantics, or `"slot": "^priority-buffs"` for fallback semantics. Prefixes apply to the contribution; the placed hook is still named `priority-buffs`. An empty inline array has the same meaning as an empty contribution, including replacement/fallback behavior. Inline contributions inherit the slot's preconditions and variable scope.

Inline contributions require one string `slot` name, rather than `slots`, comma-separated names, or fallback-selector arrays. Contributions may contain nested slots or import libraries containing slots. A separately declared slot can still use the existing multi-slot and alternative-slot forms. Expansion happens entirely while settings load; no wrapper action remains at runtime.

## Automatic section slots

Every executable action section has three native insertion points, even when the
entry point does not declare the section or show any slot placeholders:

```text
<action-type>-setup
<action-type>-priority
actions from the entry point and its imports
<action-type>-fallback
```

This applies to `loading`, `battle`, `idle_battle`, `pull`, `idle`, `resting`,
`event`, `dead`, and `mounted`. `functions` and `imports` are collections and do
not receive automatic slots. For example, a namespace common file can supply:

```json
{
  "contributions": [
    {
      "slot": "battle-setup",
      "actions": [
        {
          "commands": ["vars.user.hold_ws = false"],
          "scope": "battle",
          "frequency": "infinity"
        }
      ]
    }
  ]
}
```

The loader inserts these hooks once per top-level section after ordinary imports
expand and before contributions resolve. Imported files do not each receive a
new set of hooks. Empty hooks disappear. Contributions use the same precedence,
replacement, conditions, and variable scopes as explicit slots, and their
expanded actions appear in processed action output.

For compatibility, an explicit reference to the same slot in that section
suppresses its automatic insertion and retains the explicit position and guards.
This includes references in slot lists and alternatives. Explicit repeated
references still create repeated occurrences. Remove an old explicit
`idle-priority`, for example, to adopt the automatic top-of-section position.
Other slots such as `ws-main` retain their explicit placement.

These names control evaluation order, not lifecycle. A setup action does not
automatically execute once or block the rest of the section. Use appropriate
conditions, frequency, and scope. In the example, battle scope and infinite
frequency make the reset eligible once per battle scope; put optional cleanup
checks in commands so an initially false condition does not defer the reset until
after another action changes state. A fallback action follows normal actions but
is not guaranteed to run if higher-priority actions keep consuming opportunities.

## Ordered contributions and load-time filters

`contributions` is an ordered array of objects. Every entry requires `slot` and
an `actions` array, including empty replacements. Repeated entries for the same
slot are allowed and retain declaration order at equal source/action priority.
The legacy name-keyed object form remains readable for external configurations;
the examples and repository configurations use the ordered form.

Entries may include `comment` or `note` documentation fields; these are removed
during compilation. Other unknown entry fields produce source-qualified warnings
and are ignored rather than preventing the namespace from loading. Known fields
and their values remain strictly validated.

An optional `for` selector array filters entries for the character loading the
configuration. It supports the same jobs, groups, names, `leader`, and exclusions
as other target selectors. Nonmatching entries have no effect: their imports,
variables, nested definitions, missing-slot warnings, and replacement/fallback
rules are skipped. An empty `for` list matches nobody; omitting it matches all.
Use runtime `precondition` for conditions that can change during a fight.
Unless `required_for` is explicitly supplied, `for` also defines the audience
for missing-slot warnings.

```json
{
  "contributions": [
    { "slot": "battle-priority", "for": ["RDM"], "actions": [{ "import": "rdm-support" }] },
    { "slot": "battle-priority", "for": ["fighter"], "actions": [{ "import": "fighter-actions" }] }
  ]
}
```

Entries may also specify `optional` and `required_for` for warning control:

```json
{
  "contributions": [
    {
      "slot": "black-magic-nuke",
      "for": ["GEO", "BLM"],
      "optional": true,
      "actions": [{ "import": "nukes/elemental-mitigation" }]
    }
  ]
}
```

`optional: true` suppresses missing-slot warnings for that contribution. It does
not change execution, precedence, or validation. The flag applies to every
comma-separated name and works with `!` and `^` prefixes and empty action arrays.
Entries omitting `optional` continue to warn by default. A selected entry with
`for` is implicitly required for the same audience, overriding `optional` just
as an explicit `required_for` would. If a missing
slot has multiple selected contributions, it warns when any is non-optional;
discarded fallback/replaced definitions do not affect this decision. The object
requires an `actions` array; unknown fields are rejected.

Use an explicit `required_for` to narrow or otherwise override the warning
audience selected by `for`:

```json
{
  "slot": "black-magic-nuke",
  "for": ["BLM", "GEO", "RDM"],
  "required_for": ["BLM", "GEO"],
  "actions": [{ "import": "nukes/elemental-mitigation" }]
}
```

Missing-slot warnings are enabled only when the character loading the actions
matches both `for` and the explicit `required_for`; requirements outside the
filtered `for` audience therefore have no effect. Matching uses current main job and supports existing
job/group selectors (such as `mages`), character names, `me`, `*`, `leader`, and
`~` exclusions. This is not a test of other party members' jobs. An empty array
requires nothing. `required_for` overrides `optional` when both are present.
For a comma-separated declaration, any listed slot satisfies the requirement.
Without `required_for`, comma-separated warnings retain their existing independent
behavior. Requirements affect warnings only, not execution; use `for` to select jobs.

Prefix a contribution name with `^` to supply a fallback definition. If any
ordinary or `!` definition exists for that name, all `^` definitions are ignored,
even if they are more specific. Explicit empty arrays also suppress defaults.
Otherwise the closest fallback source is selected using the precedence below;
equal priorities use first discovery. Repeated fallback entries in that source's
ordered array combine in declaration order; fallbacks from other files do not.
Selection is at load time: disabled actions or failing preconditions do not revive
discarded defaults. An empty selected fallback still counts as present for slot
alternative selection.

For example, `{"slot": "^black-magic-burst", "for": ["BLM"], "actions": [{"import": "nukes/black-magic-burst"}]}`
provides default actions which an ordinary definition can replace. Comma-separated
slot names support `^` independently on each name. References omit prefixes.
Repeated entries are allowed; duplicate names inside a single entry and combined
prefixes such as `!^name` are rejected.

Prefix a contribution name with `!` to replace contributions below it in
precedence. For example, `{"slot": "!black-magic-burst", "actions": []}` suppresses less-specific
defaults. Higher-priority additions remain; when multiple replacements exist,
the highest-priority replacement is the boundary. Empty replacements count as
present for fallback selection. Sibling entries in the same ordered source are
retained on either side of the replacement entry. An ordinary empty array remains additive.

Contribution `slot` fields may contain comma-separated names, each with its own optional
`!`, such as `"slot": "!priority-buffs, !normal-buffs"`. Whitespace around
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

A common file or another imported file supplies a top-level `contributions` array:

`slot` and `slots` both accept a string or an ordered array. For example,
`{ "slots": ["black-magic-burst", "black-magic-nuke"] }` expands all burst
contributions before all nuke contributions. If both keys are supplied, `slot`
entries come first, followed by `slots` entries. Empty arrays insert nothing;
repeated names create separate occurrences. Placeholder conditions and scopes
apply to every name in the chain.

An entry may itself be an ordered fallback array:

```json
{ "slots": [["encounter-emergency", "battle-priority"], "normal-buffs"] }
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
  "contributions": [
    {
      "slot": "encounter-emergency",
      "actions": [
        {
          "import": "reactions/encounter-response",
          "precondition": "not evaluateAllConditions(vars.primary_tank_precondition)",
          "with_vars": { "response": { "distance": 12 } }
        }
      ]
    }
  ]
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
be commands or imports. Put an import inside an inline slot's `actions` array.
Contributions may contain slots and import libraries that declare slots. Nested
hooks expand in place using the same global contribution names and precedence.
Clearing an outer contribution removes its entire branch, including inner hooks
and imports. Inner contributions still apply at any other surviving occurrences.
Imported `loading` actions and functions retain their ordinary destinations.

For example, this lets a child clear the complete default weapon-skill branch
with `"!ws-main": []`, or replace its inner slots individually:

```json
{
  "slot": "ws-main",
  "actions": [{ "import": "melee-ws" }]
}
```

Contributed imports may define additional contributions to existing slots. A
metadata discovery pass follows selected contribution imports before slot
expansion, including library-level imports. This allows a library imported at
`normal-engagement` to register `battle-setup` actions even though setup appears
earlier. Discovered definitions use ordinary namespace precedence, conditions,
variable scopes, deduplication, and replacement rules. Discovery does not execute
actions or merge variables; normal import loading still handles those.

Self-contribution and indirect dependency cycles are errors: for example, slot
`a` importing a file that contributes to `a`, or `a -> b -> a`. Shared providers
cannot bypass the cycle check. Recursive file imports also fail, and both file
discovery depth and contribution discovery rounds are limited to ten. Disabled
or job-filtered imports are skipped. Runtime `precondition` expressions are
inherited by discovered contributions, not evaluated during discovery.

## Contribution action priorities

Each action or import in a contribution may specify `priority`. Lower numbers run
first within that slot; omitted values mean `0`. Semantic aliases are `highest`
(-1000), `high` (-100), `normal` (0), `low` (100), and `lowest` (1000).
Aliases are case-insensitive; numeric values must be finite JSON numbers.

Equal priorities preserve the existing file precedence and declaration order.
Replacement and fallback selection happen before priority sorting. Priorities
never move actions across slot boundaries. An import's priority positions its
entire expanded block, preserving the imported actions' internal order. To keep
a sequence together at a nondefault priority, assign priority to its import.
Priorities are interpreted on contribution entries, not ordinary actions inside
the imported library. An omitted priority always means normal; it does not
inherit the preceding entry's priority. Slot listings retain their original names.

```json
"contributions": [
  {
    "slot": "battle-priority",
    "actions": [
      { "priority": "high", "import": "priority-battle-actions" }
    ]
  }
]
```
