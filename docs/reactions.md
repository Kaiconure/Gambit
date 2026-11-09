# Face-away reactions

Face-away reactions let Gambit respond to an enemy readying a spell or ability without waiting for its turn in your normal action list. You can also define a bracket: one spell or ability starts the reaction, and another releases it.

Gambit must be enabled. The stock event system includes the built-in face-away rules below; character and namespace event variables can add, replace, or disable them.

Keep definitions in the array format shown below. Gambit prepares keyed lookups when event settings load, so adding rules for unrelated enemies or moves does not require checking every definition on each event. Matching rules still run in their configured order. Reload event settings after changing definitions; treat `vars.reactions.face_away` as configuration rather than a list to edit from a running event.

## Add a reaction

Put reactions in your character's **event variables**, such as `settings/Aidelle/events/geo.vars.json`. To share rules across jobs or a namespace, use the corresponding `events/(all).vars.json` or `events/common.vars.json`. Merge the following into the file's existing `vars` object:

```json
{
  "vars": {
    "reactions": {
      "face_away": [
        {
          "kind": "enemy_ability",
          "names": ["Bubble Shower", "Scissor Guard"],
          "options": {
            "wait": 3,
            "timeout": 15,
            "allow_offensive_magic": true
          }
        }
      ]
    }
  }
}
```

This example turns away when the enemy readies either ability. After completion or interruption is observed, Gambit keeps the reaction active for another three seconds. Offensive spells remain allowed, making this a useful setup for testing with crabs. The timeout ends the reaction after at most 15 seconds from its start, even if no completion is observed.

Stock event files already load these reactions; you do not need to place a face-away import in your battle action list. If you use a custom event entry file that does not import the shared enemy events, add `"lib/reactions/face-away"` to its `imports` array.

Reload Gambit after changing Lua code. After editing event configuration, reload your event settings or reload Gambit before testing.

## Choose enemies and triggers

You can group related definitions in sub-arrays in either `face_away` or `stock_face_away`:

```json
"face_away": [
  [
    { "actor": "Glavoid", "kind": "enemy_ability", "names": "*", "options": { "wait": 4, "allow_offensive_magic": true } },
    { "actor": "Glavoid", "kind": "enemy_spell", "names": "*", "options": { "wait": 4, "no_turn": true } }
  ],
  { "actor": "Raja", "kind": "enemy_ability", "names": "Royal Decree", "options": { "distance": 20, "wait": 2 } }
]
```

Groups are organizational only. Gambit flattens them when settings load, preserving order, then builds the same keyed lookups. Nested and empty groups are allowed. Groups do not share or inherit settings; each rule still specifies its own actor and options. Explicit bracket keys remain preferable to automatically generated positions.

| Field | Accepted values | Behavior |
| --- | --- | --- |
| `kind` | `"enemy_ability"` or `"enemy_spell"` | Restrict a simple reaction to abilities or spells. Omit to match either kind. |
| `names` | One name or an array | Any matching spell or ability starts the reaction on readying. |
| `actor` | One enemy name or an array | Restrict the reaction to those enemy names. Omit to allow any enemy. Actor names match exactly. |
| `options` | An object | Control turning, suppression, release wait, and timeout. |

For example, both of these forms work:

```json
"names": "Bubble Shower"
```

```json
"names": ["Bubble Shower", "Scissor Guard"]
```

Trigger names accept resource aliases, numeric IDs, and `"*"` to match all spells or abilities of the selected kind. To share a definition between enemies, use `"actor": ["Monster A", "Monster B"]`.

A reaction starts only for your current Gambit battle target, or your party leader's battle target when you have none. Selecting an enemy with the cursor alone is not sufficient.

## What happens during a reaction?

By default, Gambit stops automated movement, unlocks from the enemy if necessary, and turns away. While the reaction is active:

- Normal following, positioning, turning toward a target, and auto-engagement are blocked.
- Weapon skills and offensive spells are withheld, including requests waiting to be sent.
- Healing, support spells, and other job abilities remain available through normal actions.

Gambit does not deliberately interrupt an already-started cast. Manual movement and other addons can still interfere with facing.

Use these options to change the behavior:

| Option | Default | Meaning |
| --- | --- | --- |
| `wait` | `0.25` seconds | How long to keep holding after completion, interruption, or a bracket's release trigger. It does not delay the initial response. |
| `timeout` | No automatic expiry | Optional maximum total duration in seconds from the start, including the release wait. Omit, use `null`, or use `"inf"`/`"infinity"` for no deadline. |
| `no_turn` | `false` | Do not force a face-away. Normal positioning and facing continue unless `distance` also requests a retreat. |
| `allow_weapon_skills` | `false` | Allow weapon skills during this reaction. |
| `allow_offensive_magic` | `false` | Allow offensive spells during this reaction. |
| `distance` | Not set | Retreat to at least this horizontal center distance from the triggering enemy, in yalms. Does not move you closer if already farther away. |
| `angle` | Not set | Optional target-relative angle or region to maintain alongside `distance`. Requires `distance`; omitted or `null` preserves outward-only retreat. |

Without a timeout, simple reactions remain active until completion/interruption is observed, and brackets until their release trigger is observed, followed by the configured `wait`. Enemy defeat and the cleanup conditions below still clear them. If an end event is missed, the hold stays active until it is explicitly released or cleaned up. Set a finite `timeout` when you want an automatic fallback. `"inf"` and `"infinity"` are case-insensitive. Zero expires immediately; it does not disable expiry. The release `wait` must still be a finite nonnegative number.

If several reactions overlap, their restrictions combine. Allowing offensive magic in one reaction does not override another reaction that suppresses it. The newest active turning reaction determines which enemy you face away from. Ending one reaction does not clear the others.

## Distance reactions

Add `distance` to a simple reaction or bracket's `options` to retreat from the triggering enemy:

```json
{
  "actor": "Raja",
  "kind": "enemy_ability",
  "names": "Royal Decree",
  "options": {
    "distance": 20,
    "wait": 2,
    "timeout": 15
  }
}
```

This requests at least **20 yalms from the monster's center**, measured horizontally from the actual coordinates. Model size, melee range, `radius_multiplier`, and adjusted `mob.distance` do not change that minimum. Gambit aims slightly beyond it to allow for movement arrival tolerance. It never approaches an enemy just to reach the requested distance.

To also request a particular side of the monster, add an angle:

```json
"options": {
  "distance": 20,
  "angle": "backside",
  "wait": 2
}
```

Angles use the same rules as [frontline alignment](functions.md#flexible-alignment): a number such as `180`, exact aliases such as `"rear"` or `"front"`, regions such as `"backside"`, `"frontside"`, `"side"`, `"left"`, `"right"`, or ranges such as `"180+/-30"`. They are relative to the triggering enemy's current facing. Gambit chooses the nearest allowed direction and checks both angle and minimum distance, with positional arrival tolerance. If you are already farther than the minimum but on the wrong side, correction uses your current radius rather than pulling you closer. The angle continues to apply if the enemy turns during the hold.

An omitted or `null` angle keeps the original behavior: retreat straight outward, with no angular correction. `angle` controls position around the enemy, not which way your character faces after moving; `no_turn` still controls the face-away behavior. If overlapping distance requests select one movement rule, that rule supplies its angle as well.

The face-away and suppression start immediately. Retreat starts at the next opportunity in the normal action loop, without needing an import at a particular position. It waits for existing casts and movement reservations, and does not start while you are resting, mounted, dead, or affected by Bind, Sleep, Stun, Petrification, or Terror. Movement runs in short steps, with brief gaps for normal support actions and fresh checks if the enemy moves. No path to a safe point is guaranteed.

Facing away is reasserted after each movement step. With `no_turn: true`, Gambit still retreats but does not force facing away. Other automated movement and facing are held back while a distance reaction is active, including after you reach the minimum, so normal positioning cannot pull you back into danger. Healing/support actions remain eligible between steps.

Retreat continues during the release wait and stops when the reaction ends. Enemy defeat, timeout, or other cleanup also cancels its movement, including a request that has not started running yet. Normal positioning resumes afterward. If multiple distance reactions concern the same enemy, the largest minimum wins. If they concern different enemies, the most recently triggered distance enemy takes priority; this does not guarantee clearance from both enemies at once.

## Bracketed reactions

Use `start` and `release` instead of `kind` and `names` when a mechanic persists between two different moves:

```json
{
  "key": "amphitrite-hold",
  "actor": "Amphitrite",
  "start": {
    "abilities": ["Palsynyxis"]
  },
  "release": {
    "abilities": ["Painful Whip"]
  },
  "options": {
    "wait": 3,
    "timeout": 120
  }
}
```

Add that object to `vars.reactions.face_away`. It starts after Palsynyxis successfully completes and remains active until Painful Whip successfully completes, followed by the three-second release wait. Completing the starting move does not automatically release a bracket.

Each side can contain `abilities`, `spells`, or both. Each accepts a string or an array; any matching entry triggers that side. For example:

```json
"start": {
  "abilities": ["Ability A"],
  "spells": ["Spell A"],
  "phase": "pre"
},
"release": {
  "abilities": ["Ability B"],
  "spells": ["Spell B"],
  "phase": "post"
}
```

Replace the example names with the moves you want to match. `phase` defaults to `"post"`, which requires successful completion. Use `"pre"` to respond at readying. A failed or interrupted move does not satisfy a `post` trigger.

Give each bracket a descriptive, distinct `key`. If omitted, Gambit uses its position in the configured list. An `actor` array shares the definition across enemies, but each actual enemy keeps its own hold: one monster cannot release another monster's bracket.

## Target changes and cleanup

Switching battle targets does not end a reaction. You continue facing away from the original enemy, and its restrictions still apply to actions against the new target. A bracket's release trigger is still recognized from the original enemy after switching away.

Enemy defeat, disappearance, or invalidation removes its hold without waiting the remaining release delay. Player death, zoning, reload, logout, unloading Gambit, a full settings or event settings reload, and disabling automation also clear reaction state.

After the final normal release or timeout, Gambit turns back only if that enemy remains the game's battle target. Otherwise, your normal actions determine what happens next. No reaction automatically engages a different target.

## Migrating existing face-away rules

**Custom-rule migration is a breaking change.** The event-driven rules do not automatically convert the old `face_away_on_ability`, `face_away_on_spell`, or `face_away_bracketed` action variables. Define the replacements under event `vars.reactions.face_away`.

| Old configuration | New configuration |
| --- | --- |
| Enemy-name table key | `actor` |
| `abilities` or `spells` name map | `kind` plus `names` |
| Bracket `initiators` and `terminators` | `start` and `release` |
| Per-trigger turning/suppression settings | `options` |
| `wait` omitted, previously two seconds | Specify `"wait": 2` to retain that delay; the new default is 0.25 seconds. |
| Hold with no expiry | Omit `timeout`, use `null`, or specify `"infinity"`. |

The shorter release wait is measured from an observed end event, not from the normal action loop noticing that the enemy is no longer acting. A timeout is a separate fallback and can release without a confirmed end event.

Rules created during the initial event-driven trial used default timeouts of 15 seconds (simple reactions) or 60 seconds (brackets). Those defaults no longer apply: add `"timeout": 15` or `"timeout": 60` explicitly if you want to preserve that expiry. Existing explicit finite timeouts are unchanged.

The old face-away action imports are compatibility placeholders and no longer poll or change facing. You can remove the spell and bracket imports. The aggregate and ability imports still retain the legacy gear-removal command hook; keep one of those if you use that hook. Old custom face-away action variables are not read by the new rules and must be migrated to event variables. Stun actions are unchanged.

Legacy `distance` settings can now be moved to the new rule's `options.distance`. This requests a minimum center distance, rather than an exact alignment ring with model-size adjustments. Gear-removal recovery has not migrated yet. Stun remains a normal sequenced action rather than an immediate face-away response.

## Built-in rules and overrides

Stock rules are active for every stock job event entry point. They preserve the old release waits explicitly; omitted timeouts mean no automatic expiry. Gaze/ability rules start at readying. Brackets start and release on successful completion. Distance rules use the new minimum center-distance behavior.

| Stock key | Enemy / trigger | Behavior |
| --- | --- | --- |
| `stock-assailer-discoid` | Assailer Chariot / Discoid | Face away, minimum distance 12, wait 2. |
| `stock-glavoid-abilities` | Glavoid / all abilities | Face away, allow offensive magic, wait 4. |
| `stock-raja-royal-decree` | Raja / Royal Decree | Face away, minimum distance 20, wait 2. |
| `stock-rani-abilities` | Rani / all abilities | Face away, wait 2. |
| `stock-urmahlullu-abilities` | Urmahlullu / all abilities | Suppress without turning, wait 2. |
| `stock-gaze-abilities` | Any enemy / Afflicting Gaze, Baleful Gaze, Blaster, Grim Glower, Mortal Blast, Mortal Ray, Oppressive Glare | Face away, wait 2. |
| `stock-deathly-glare` | Any enemy / Deathly Glare | Face away, wait 4. |
| `stock-shah-mat` | Any enemy / Shah Mat | Face away, allow offensive magic, wait 6. |
| `stock-glavoid-spells` | Glavoid / all spells | Suppress without turning, wait 4. |
| `stock-urmahlullu-spells` | Urmahlullu / all spells | Suppress without turning, wait 2. |
| `stock-amphitrite-bracket` | Amphitrite / Palsynyxis to Painful Whip | Bracket, wait 2. |
| `stock-cloud-of-darkness-bracket` | Cloud of Darkness / Primordial Surge to Waning Vigor or Expunge | Bracket, wait 2. |

Unless stated otherwise, stock rules suppress weapon skills and offensive magic. Actor-specific stock starts take precedence over generic stock gaze starts for the same event, preserving the old lookup behavior.

Your `face_away` list is separate from the stock list: adding your own rules does not erase all built-ins. A custom start that matches an event replaces stock starts for that event, avoiding duplicate holds and conflicting suppression settings. Existing stock brackets still receive their release events. Explicit keys let you replace or disable a complete stock definition regardless of the trigger you choose.

To disable one default, add a custom entry using its stock key:

```json
{
  "vars": {
    "reactions": {
      "face_away": [
        { "key": "stock-gaze-abilities", "disabled": true }
      ]
    }
  }
}
```

That grouped key disables all seven moves listed in its row. To change a stock rule, put its key on a complete replacement definition in `face_away`, including the desired actor, trigger, and options. Replacement settings are not merged with the stock entry.

To use only your custom list, set `vars.reactions.stock_face_away_enabled` to `false`. You normally do not need to edit `stock_face_away` itself. Reload event settings after changing either setting.

## Troubleshooting

To print reaction details to the Windower console, set `debug` in your event variables:

```json
{
  "vars": {
    "reactions": {
      "debug": true
    }
  }
}
```

Merge this into your existing settings and reload event settings. The default is `false`; this setting is independent of Gambit's general debugging setting. Messages start with `[Gambit reactions]` and show the enemy, rule key, triggering move, turning/suppression options, distance, wait, and timeout. They also show observed releases, distance movement status changes, and why a hold ended (release wait, timeout, enemy defeat/invalidation, reload, or disabled automation). A matching start rejected by the battle-target filter is reported as skipped.

This logs reaction transitions rather than every facing update or every enemy action. Turn `debug` back to `false` when finished. After initially installing this feature, reload Gambit to load the Lua changes.

If a rule does not turn you away, check that:

1. Gambit is enabled and the edited event variables belong to the current character, job, and namespace.
2. Your event entry file loads `lib/reactions/face-away`, directly or through the shared enemy-ability events.
3. The enemy is your battle target, or the leader's target when you have none.
4. Its name matches `actor`, if specified, and the trigger kind/name/phase matches the observed move.
5. `no_turn` is not enabled and another addon is not controlling facing.

For a first test, use one familiar enemy move with an obvious release wait. Check readying, completion, interruption, and enemy defeat before adding more rules. For custom expressions, `reactions.active()` reports whether any hold exists, `reactions.state()` returns its details, and `reactions.suppresses('weapon_skills')` or `reactions.suppresses('offensive_magic')` reports the combined restrictions.
