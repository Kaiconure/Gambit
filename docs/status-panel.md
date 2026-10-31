# Status panel prototype

The panel appears while logged in, including while automation is disabled. Drag
its title bar to move it. Click `[on]` / `[off]` beside the title to use Gambit's
normal toggle command; commands and hotkeys continue to update the same state.
The active strategy appears beside the toggle, for example `[on] [leader]`.
Only the on/off text is clickable. Aggressor/puller strategies appear red;
other strategies appear green. Header content can widen the panel to reserve
space for the right-aligned version.
The addon version appears as a small right-aligned label just below the top border
and follows the panel width as it resizes.

Personal settings live under `ui.status_panel` in `settings/<character>/main.json`.
They are loaded directly from that global character file, regardless of namespace
main overrides. Defaults live in `lib/ux/status-config.lua`; omitted properties
use those defaults. Mouse resizing is not implemented yet.

## Inline colors

Tracking names and values support Windower's `\cs(r,g,b)` color codes and
`\cr` reset. RGB components range from 0 to 255. For a static JSON value:

```json
{
  "name": "Note",
  "value": "\\cs(255,215,0)Gold text\\cr"
}
```

An expression also has Lua string escaping, so it needs another level:

```json
{
  "name": "Mode",
  "expression": "'\\\\cs(255,215,0)' .. gambit.strategy .. '\\\\cr'"
}
```

Color codes do not count toward automatic width or clipping. Each displayed
line resets any remaining inline color at its end; color each array/multiline
entry explicitly. Inline bold is not supported.

## Commands

To track the current automation entry point, add an entry to your tracking set:

```json
{
  "name": "Automation",
  "expression": "gambit.entrypoint_name"
}
```

Use `gambit.entrypoint` for the stored name or `gambit.entrypoint_path` for the
source filename including `.json`. The row is omitted when its result is nil.
`gambit.entrypoint_relative` omits the owning namespace's directory prefix for
namespace files, while retaining the normal source path for global files.
Both relative display fields omit the leading `./`; the source-path fields
retain their original values.
The active event entry file has corresponding `gambit.events`,
`gambit.events_path`, `gambit.events_name`, and `gambit.events_relative` fields:

```json
{"name": "Events", "expression": "gambit.events_relative"}
```

`gambit.event_namespace` identifies the selected event file's actual namespace,
which may differ from the active `gambit.namespace` because of inheritance or
fallback. Use `gambit.event_namespace or 'global'` to display global/shipped
sources as global. Folder aliases such as `_base` retain their source spelling.

| Command | Behavior |
|---|---|
| `gbt panel` | Show visibility preference, current tracking set, and command help |
| `gbt panel help` | Show command help (`-h` and `-help` also work) |
| `gbt panel show` / `gbt panel hide` | Show/hide without changing automation |
| `gbt panel log` | Show whether recent output is enabled |
| `gbt panel theme [<name>]` | View or change the background skin and save |
| `gbt panel theme -list` | List available JSON-defined skins alphabetically |
| `gbt panel log hide` / `gbt panel log show` | Hide/show recent output and save |
| `gbt panel tracking` | Show the current tracking set |
| `gbt panel tracking -list` | List names alphabetically |
| `gbt panel tracking -set <name>` | Switch immediately and save selection |
| `gbt panel reset-position` | Restore default coordinates and save |
| `gbt panel reset` | Reset display preferences and select `default`; preserve custom sets and clear temporary tracking |
| `gbt panel position <x> <y>` | Set both coordinates in pixels and save |
| `gbt panel anchor [<top\|bottom> <left\|right>]` | View or set the position anchor and save |
| `gbt panel x <x>` / `gbt panel y <y>` | Set one coordinate, retaining the other |
| `gbt panel size <width> <height>` | Set both dimensions in pixels and save |
| `gbt panel font-size [<size>]` | View or set the base font size (integer 6–30) and save; alias `fontsize` |
| `gbt panel width <width>` | Set width while retaining height mode |
| `gbt panel height <height>` | Set a minimum height while retaining width |
| `gbt panel height auto` | Restore automatic height based on tracking/history |
| `gbt panel reload` | Reread panel JSON and apply without reloading actions or the addon |

Visibility, tracking selection, and completed title drags save automatically.
Recent output visibility is stored as `show_log` (default `true`). Hiding the log
shrinks the panel toward its configured minimum height. History continues collecting
while hidden, and reappears when shown. Chat output is unaffected.
Dragging writes once on release, not on every movement. Saves preserve unrelated
main settings and the default namespace preference; normal configuration saves
preserve the personal UI section. After editing JSON manually, run `gbt panel
reload` before changing panel preferences. Invalid configuration or an unknown
set reports an error and retains the existing panel.

## Configuration

Merge this `ui` section into your existing global character main configuration:

```json
{
  "ui": {
    "status_panel": {
      "tracking": {
        "current": "custom",
        "sets": {
          "custom": [
            {
              "name": "Automation",
              "expression": [
                "\"Actions: \" .. color_text(format(\"%s (%s namespace)\", gambit.entrypoint_relative, gambit.namespace or \"global\"), 100,235,130)",
                "\"Events: \" .. color_text(format(\"%s (%s namespace)\", gambit.events_relative, gambit.event_namespace or \"global\"), 100,235,130)",
                "\"Target: \" .. color_mob(cursor) .. (cursor and cursor.valid_target and format(\" (%s / %s)\", color_number(cursor.id), color_number(format(\"%03X\", cursor.index))) or \"\")"
              ]
            },
            {
              "name": "Skillchain",
              "expression": [
                "(party_weapon_skill and party_weapon_skill.name or nil) and format('%s%s%s (~%ss)', color_element(party_weapon_skill.skill or party_weapon_skill), skillchain and skillchain.name and (' → ' .. color_skillchain(skillchain)) or '', bt and (' → ' .. color_mob(bt)) or '', color_number(format('%.1f', (skillchain or party_weapon_skill).lifetime)))"
              ]
            },
            {
              "name": "Spell",
              "expression": [
                "(gambit.last_spell and gambit.last_spell.name and (gambit.last_spell.status == 'casting' or gambit.last_spell.age < 5) or nil) and format('%s%s (%s)', color_element(gambit.last_spell), gambit.last_spell.target and gambit.last_spell.target.name and (' → ' .. color_mob(gambit.last_spell.target)) or '', color_status(gambit.last_spell.status))"
              ]
            },
            {
              "name": "Job Ability",
              "expression": [
                "(gambit.last_ability and gambit.last_ability.name and gambit.last_ability.age < 5 or nil) and format('%s%s', color_element(gambit.last_ability), gambit.last_ability.target and gambit.last_ability.target.name and (' → ' .. color_mob(gambit.last_ability.target)) or '')"
              ]
            }
          ]
        }
      }
    }
  }
}
```

Each named set is an array of entries. Names are case-sensitive. `value` accepts
a string displayed inline with the name, or an array of display lines below
the heading (even a one-element array). Expressions can also return arrays: each
element appears on its own indented line under the entry heading. Automatic
height and subsequent rows reflow as the
array length changes. Switching sets rebuilds tracking rows and
panel height, retaining placement, width, and recent output. Empty sets show only
the automation toggle and log.


### Stock and custom tracking sets

Gambit owns every set defined in its stock configuration: currently `default`,
`compact`, and `none`. Their definitions always come from Gambit. Saved copies
under these names are ignored and removed the next time panel preferences are
saved. The selected name (`tracking.current`) is still saved.

Custom sets are merged with the stock sets in memory and saved normally. Use a
unique name such as `custom` to keep your own version of the display. The example
above copies the current stock `default` definition into a custom set, including its
conditional rows and inline colors. Select it with `gbt panel tracking -set custom`.
To use the built-in display instead, select `default`; you do not need to copy its
definition into your settings. Old single-array tracking settings also fall back
to the current stock default.

`gbt panel reset` resets display preferences, selects `default`, clears temporary
tracking, and saves. It preserves all custom tracking set definitions. Move any
personal edits saved under a stock name to a custom name before your next panel
preference save if you want to retain them.

Coordinates must be nonnegative integers; width is 180–2000, font size 6–30,
history lines 0–100, and refresh interval 0.1–60 seconds. Bounds errors reject the
configuration rather than silently changing it.

`position`, `x`, or `y` without arguments reports the current position.
Coordinates are pixel offsets inward from the selected window edges, not relative
movements. The default anchor is `top left`. For example:

```text
gbt panel anchor top right
gbt panel position 30 150
```

This keeps the panel's right edge 30 pixels from the window's right edge and its
top edge 150 pixels down. Automatic width grows leftward when right-anchored;
automatic height grows upward when bottom-anchored. Window-size changes are
picked up on refresh. Dragging saves offsets relative to the selected edges.
Changing anchors retains the numeric offsets, so the panel moves to the selected
corner. Anchors persist as `anchor: {"vertical":"top","horizontal":"right"}`
under `ui.status_panel`. Unspecified components default to `top` and `left`.
Updates do not rebuild tracking rows or discard history or temporary tracking.

An optional `height` sets minimum height (80–2000 pixels); omit it for automatic
height. `size`, `width`, or `height` without arguments reports the current size.
Changes apply live, preserve history and position, and persist per character.
The panel expands to fit tracking rows and configured log rows, then shrinks back
toward the configured minimum when content needs less room. These automatic
height changes do not modify or save the configured height.
While logging is enabled, the displayed width is at
least 600 pixels. This minimum does not change the configured or saved width;
hiding the log restores that width. Widening/narrowing changes the
horizontal clipping limit. This does not change font size or history capacity.

Tracking headings and values can widen the panel beyond its configured width
and the logging minimum. Each refresh sizes to the longest visible tracking
line, including value indentation, using the same font metrics as clipping.
Segoe UI uses per-character regular/bold width tables; Consolas uses a fixed
advance. Measurements are cached per label until text or font settings change,
with conservative widths for unsupported characters and a small layout margin.
Multiline values use their longest line; nil entries contribute no
width. The panel shrinks toward its minimum when tracking content becomes
shorter. Log text never drives automatic width. These width changes do not
modify saved settings.

Expressions use the ordinary action expression compiler and a fresh temporary
context per entry. A string expression returning a scalar displays inline with
its heading, for example `Strategy: leader`. An array evaluates each expression
independently and displays its results below the heading, including when the
array has only one expression. An expression returning an array expands into
one line per element and uses vertical layout even for a string expression.
Nil results are omitted; an empty result array has no visible rows.
An expression takes precedence over a static value even when
returning `false` or `nil`. A `nil` value hides both the heading and value and
reserves no rows; the entry reappears when its value becomes non-nil. `false`
continues to display normally. Updates occur every half second by default. Use short,
non-yielding expressions without side effects; these are Lua code, not sandboxed
formulas. Temporary contexts do not replace the active automation context.

Syntax/runtime failures display `[error]` on the affected entry and stop retrying
it until panel recreation (switch sets or run `gbt panel reload`). Unavailable contexts display
`[unavailable]` and are retried. Failures do not quarantine automation actions or
produce repeated chat errors.

## Panel expression color helpers

Tracking expressions have additional helpers, available only during panel
evaluation:

| Helper | Result |
|---|---|
| `color_text(text, r, g, b)` | Wrap text in RGB color markup; components are integers from 0 to 255 |
| `color_mob(mob)` | Color the mob's name; unavailable/invalid targets return gray `--` |
| `color_skillchain(chain)` | Color a skillchain name or an object's `name`; missing names return gray `--` |
| `color_element(object)` | Color an object's `name` using its `element`; missing/invalid elements leave the name unchanged |
| `color_number(value)` | Color a number or preformatted numeric string in pale gold |
| `color_status(status)` | Casting in pending gold, interrupted in red, completed in green; unknown statuses use body color |
| `color_latest(text)` | Color text using the most recent color chosen by either helper above |

Players outside your party/alliance are white; party/alliance players are
turquoise. Monsters and pets are light gold when not engaged and red when
engaged. Engaged monsters/pets with an outside claim that cannot be shared are
magenta, using Gambit's claim-sharing helper (including its shared-content
exceptions). NPCs and other valid targets (including trusts) are green. Player and
monster/pet classifications take precedence over the broad NPC flag. Invalid
targets remain gray `--`. Dead targets use gray regardless of type or membership.
These colors use the panel theme palette.

```json
{
  "name": "Target",
  "expression": "color_mob(cursor) .. (cursor and cursor.valid_target and color_latest(format(' (%d / %03X)', cursor.id, cursor.index)) or '')"
}
```

`color_element` accepts Windower's numeric element IDs (0–7) or English element
names, case-insensitively: Fire, Ice, Wind, Earth, Lightning, Water, Light, Dark.
It works with spells, abilities, weapon skills, and event objects carrying those
fields. Physical, None, and unsupported elements pass the name through without
adding markup or changing `color_latest`. Nil input or a missing name returns
nil. For example: `color_element(event)`.

Color helpers update `color_latest` when they apply a color. Format numbers before coloring when
needed, for example `color_number(format('%.1f', remaining))`. Palette entries
`number`, `status_pending`, `status_interrupted`, and `status_completed` are in
`lib/ux/theme.lua`. Stock tracking uses these for its countdown and spell status.

Each expression starts with a fresh latest color, including each element of an
expression array. Before a color has been chosen, `color_latest` uses the body
color. Every helper closes its color markup with a reset. The expression above
colors the target name first, then uses `color_latest` for its supplemental IDs.
Tracking examples generally use expressions rather than local declarations or
explicit return statements.

`color_skillchain` recognizes names case-insensitively and updates `color_latest`.
Unknown names retain their text in the normal body color. The stock skillchain
progress row uses it automatically.

| Skillchain | Color |
|---|---|
| Liquefaction | Coral red |
| Induration | Pale blue |
| Detonation | Mint green |
| Scission | Sandy gold |
| Impaction | Lavender |
| Reverberation | Blue |
| Transfixion | Pale yellow |
| Compression | Purple |
| Fusion | Orange |
| Fragmentation | Turquoise |
| Distortion | Blue-violet |
| Gravitation | Muted plum |
| Light / Radiance | Warm white |
| Darkness / Umbra | Light violet |

## Include another tracking set

A tracking entry with `references` is replaced on screen by all rows from that
named tracking set, in their existing order. For example, this set displays the
built-in `compact` rows first, followed by a checklist:

```json
{
  "ui": {
    "status_panel": {
      "tracking": {
        "current": "objectives",
        "sets": {
          "objectives": [
            {"references": "compact"},
            {
              "id": "sortie_a",
              "name": "Objectives",
              "checklist": [{"id": "key_a", "text": "Open any unlocked #A gate"}]
            }
          ]
        }
      }
    }
  }
}
```

References work in saved sets and arrays passed to `setPanelTracking`, including
append mode. They can name stock or custom sets and can be nested. `none` inserts
no rows. Missing sets and circular references produce configuration errors.
When `references` is present, the entry's other fields are ignored; it does not
need a `name`. The reference itself is saved, so changes to the referenced set
are picked up when the panel is reconfigured or reloaded.

## Objective checklists

Add a checklist entry to a custom tracking set to display clickable objectives:

```json
{
  "ui": {
    "status_panel": {
      "tracking": {
        "current": "sortie",
        "sets": {
          "sortie": [
            {
              "id": "sortie_a",
              "name": "Objectives",
              "checklist": [
                {"id": "kill_5_abject", "text": "Kill 5 abject mobs"},
                {"text": "Kill 5 more abject mobs"}
              ]
            }
          ]
        }
      }
    }
  }
}
```

Each objective appears below its heading with an unchecked box or a green check.
The icons use shared 32×32 PNG assets in `content/ui/checklist`, displayed at a
size proportional to the panel font. Each row retains its own image instance;
its texture changes only when the completion state changes.
Click anywhere on its row to toggle it. The objective text turns gold while the
pointer is over its icon or row. A checklist takes precedence over both
`expression` and `value`; those fields are ignored when `checklist` is present.
An empty checklist hides the entry, including its heading.

The checklist requires an `id`. Each item requires single-line `text` and may
provide an `id`; omitted IDs become `objective_1`, `objective_2`, and so on using
their position in the array. Explicit item IDs remain stable when you reorder
objectives. IDs start with a letter or underscore and contain only letters,
digits, underscores, or hyphens. Item IDs must be unique within their checklist.

State is read from `vars.panel.<checklist-id>.<item-id>`. Nil or false means
pending; any truthy Lua value means complete (including zero). For example,
automation actions can mark or reset the objectives above with:

```lua
checklistSet('sortie_a', 'kill_5_abject', true)
checklistSet('sortie_a', 'objective_2', false)
checklistGet('sortie_a', 'kill_5_abject') -- true or false
```

These helpers always use shared automation checklist state, including when called
from event handlers or actions with scoped variables. `checklistSet` stores and
returns a boolean using Lua truthiness: nil and false become false; everything
else (including zero and empty strings) becomes true. `checklistGet` returns a
boolean, with missing items returning false. They do not require the checklist
to be currently displayed. Direct variable access remains available at the path
above; event handlers can use `setVarGlobal` for that lower-level interface.

Code-driven changes appear on the next panel refresh; clicks refresh immediately.
Sets with the same checklist and item IDs share state. Switching tracking sets or
changing panel preferences does not clear that state. Completion is runtime
variable state, not a saved panel preference; initialize or reset it through
variables/actions when starting a new run. Reloading automation settings may
reset it along with other automation variables.

## Temporary tracking from actions

### Most recently used job ability

Actions and tracking expressions can read `gambit.last_ability`, which is nil
until a completed self job-ability event is observed. It contains `id`, `name`,
and `time` (the `os.clock()` timestamp, in seconds). Manual abilities are included;
other players' abilities, spells, and weapon skills do not replace it. It clears
on logout or addon reload, and remains available through settings reloads.
Context values are snapshots; a fresh context sees the latest observed ability.

For a tracking entry that stays hidden until an ability has been used:

```json
{ "name": "Last ability", "expression": ["gambit.last_ability and gambit.last_ability.name"] }
```

An action can test elapsed time with
`gambit.last_ability and time - gambit.last_ability.time < 5`.

`gambit.last_spell` provides `id`, `name`, `time`, `age`, and `status` for your
most recent spell, including manual casting. Cast start creates a record with
`status='casting'`; completion changes it to `'completed'`, and interruption
changes it to `'interrupted'`. `time` is refreshed on each transition and `age`
is seconds since that transition, calculated when the context is created.
Completion can also create a record if the start event was not observed.
Spell and ability records are independent and have the same lifetime and
snapshot behavior. For example:

```json
{ "name": "Last spell", "expression": ["gambit.last_spell and gambit.last_spell.name"] }
```

Both `gambit.last_spell.target` and `gambit.last_ability.target` contain `id`,
`name`, and `index`. Spell targets are captured at cast start and refreshed on
completion; interruption retains the cast-start target. Ability targets are
captured at completion. The ID remains available if the target cannot be resolved; `name`
and `index` are then nil. The target itself is nil if no target ID is available.
For area spells or abilities this is the first target reported in the result packet, rather
than a list of everyone affected. These are recorded details, not a live entity.

### Configure tracking rows

Use `setPanelTracking(entries)` in an action to replace the displayed tracking
rows. Pass an array with the same entry schema as a single configured tracking
set; no set name or `sets` wrapper is needed. For example, in an action file:

```json
{
  "vars": {
    "panel_tracking": [
      { "name": "Strategy", "expression": ["gambit.strategy"] },
      { "name": "Phase", "value": "Preparing" }
    ]
  },
  "loading": [
    { "commands": ["setPanelTracking(vars.panel_tracking)"] }
  ]
}
```

The function returns `true` on success. Invalid entries raise an action error
and leave the existing panel intact. Entry expressions use a fresh panel context,
as ordinary configured tracking does, rather than capturing the calling action's
local variables or parameters.

Pass `true` as the second argument to append after the currently active rows:
`setPanelTracking(vars.panel_tracking, true)`. This extends an existing temporary
override when present, or the selected configured set otherwise. Repeated calls
append again, so use a loading or one-time action to avoid duplicate rows.
Omitting the argument or passing `false` replaces tracking as usual. Appending
an empty array leaves the rows unchanged; passing `nil` restores configured
tracking regardless of the append flag. Appended rows remain temporary.

`setPanelTracking({})` clears tracking rows; `setPanelTracking(nil)` restores the
selected configured set. Overrides do not change that selection, its saved
entries, position, or log history. Later preference saves do not persist the
override. Settings reloads, explicit panel/addon reloads, selecting a tracking
set, or `setPanelTracking(nil)` restore configured tracking. Display
reconfiguration, including size, theme, visibility, log visibility, and position
changes, retains the temporary rows.

## Shared appearance and log text

### Background skins

Use `gbt panel theme ffxi` for the blue-violet textured skin with silver horizontal
trim and open sides. Its retained `content/ui/ffxi/center.png` is 300 by 400 pixels;
the redundant full-resolution source has been removed.
The six-pixel top and bottom borders stay fixed, and the center fills the width.
The center uses a fixed 400-pixel texture height to keep the
horizontal lines about 4–5 pixels apart as the panel resizes. Adjust
`texture_height` in the theme registry to tune spacing (larger means wider).
Run `content/ui/ffxi/generate.ps1` to normalize the center resolution and rebuild
the 580-by-300 preview using the retained center and top/bottom border assets.
The renderer stretches the center horizontally and repeats it vertically;
resolution changes do not alter the configured line spacing.

Use `gbt panel theme ff8` for the gray FF8-style bevel/gradient skin, or
`gbt panel theme ff7` for the blue gradient and silver frame extracted from
`content/ffvii-narrow.png`. FF7 uses ten-pixel fixed corners, stretched edges, and
a stretched center. Its transparent outer margins are trimmed while corner
transparency is preserved. Assets and a repeatable extraction script live in
`content/ui/ff7/`; the original image remains unchanged. Use
`gbt panel theme solid` for the original dark background. The selection persists
as `ui.status_panel.theme`. A theme switch preserves size, placement, tracking,
and recent history. `ffxi` is the default when no theme preference is saved.

The reusable `lib/ux/background.lua` renderer supports a solid surface or nine
separate PNG pieces. The `ff8` skin uses five-pixel fixed corners, stretched edge
strips, and a single stretched center gradient. The center does not need to tile.
It is a procedural recreation of the supplied reference, not a pixel extraction.
Assets and the reproducible generator are under `content/ui/ff8/`; skin definitions
are in `content/ui/themes.json`. Existing content padding clears the five-pixel frame.
Rendering and texture filtering still need visual verification in Windower.

### Add a background theme without Lua changes

Add a named entry to `content/ui/themes.json` and put the artwork in its folder:

```json
{
  "solid": { "color": [20, 24, 32], "opacity": 220 },
  "my-skin": { "folder": "content/ui/my-skin/", "border": 8, "opacity": 255 }
}
```

Merge the entry into the existing registry to retain other skins. Each nine-slice
folder requires `center.png`. Optional frame images are `top.png`, `bottom.png`,
`left.png`, `right.png`, `top-left.png`, `top-right.png`, `bottom-left.png`, and
`bottom-right.png`. Missing edges reserve no space, so the center expands to fill
that side. Corners render only when both adjoining edges exist. Omit side images
and corners for a theme with horizontal borders only.
The pieces stretch; corner dimensions stay fixed at `border` pixels. A single
center image is supported and does not have to tile.

Names use lowercase letters, digits, hyphens, and underscores, starting with a
letter. Folders are addon-relative paths ending with `/`. Border thickness is an
integer from 1 to 100; opacity and RGB components are integers from 0 to 255.
Opacity defaults to 255. Solid entries omit `folder` and provide `color` instead.
Keep the `ffxi` entry for the default panel theme and `solid` for the plain background.

Run `gbt panel theme -list`, then `gbt panel theme my-skin`. Registry edits are
also read by `gbt panel reload`; no addon reload is required for content changes.
Malformed definitions and a missing center image reject the update, preserving the
current panel. Text style/color constants remain in `lib/ux/theme.lua`; this
registry controls background artwork only.

### Text styles

`lib/ux/theme.lua` defines reusable RGB constants (`green`, `red`, `yellow`,
`orange`, and semantic heading/body/log colors) and heading, subheading, and body
styles. The title uses the heading style; automation state and tracking names use
subheadings; values and log lines use body text. Font sizes scale from the panel's
configured `font_size`. Fonts include Unicode symbol/Japanese fallbacks.

Tracking names and values have distinct colors. Error values use red. Log lines
alternate between two contrasting body colors, with the latest line highlighted
in bright gold. When a new line arrives, the previous latest line returns to its
assigned alternating color. Fixed-height panels show the most recent lines that
fit, keeping the highlighted newest line visible whenever there is room for log
output. This improves separation without importing FFXI chat
color formatting into the panel.

Recent output observes `writeMessage` after verbosity/suppression checks and
before the addon prefix is added. Chat color codes are stripped. Non-UTF-8 text
is converted using Windower's `from_shift_jis`; already valid UTF-8 is preserved.
This handles game symbols such as the right arrow without double conversion.
See [Windower's encoding API](https://github.com/Windower/Lua/blob/dev/definitions/windower.lua).
The panel adds
no timestamp or `[gbt]` prefix; explicitly embedded message content is retained.
When recent output is enabled with at least one history row, a `Log` subheading
appears above it and the panel includes space for the heading.
History is bounded by the configured line count. Long rows are clipped, preserving
UTF-8 code-point boundaries. Column widths remain estimates rather than exact
glyph measurements: the estimate uses `font_size * 0.8` pixels per character,
with ten-pixel side padding and allowance for indented values. `print()` output and earlier startup messages are
not captured.

The reusable `lib/ux/panel.lua` surface provides labels, clickable buttons,
visibility, title dragging, and cleanup using injected Windower text/image
primitives. `log-buffer.lua` provides bounded plain-text history. The status
controller supplies Gambit-specific state, logging, and context dependencies.
