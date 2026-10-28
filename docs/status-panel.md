# Status panel prototype

The panel appears while logged in, including while automation is disabled. Drag
its title bar to move it. Click the automation status row to use Gambit's normal
toggle command; commands and hotkeys continue to update the same state.

Personal settings live under `ui.status_panel` in `settings/<character>/main.json`.
They are loaded directly from that global character file, regardless of namespace
main overrides. Defaults live in `lib/ux/status-config.lua`; omitted properties
use those defaults. Mouse resizing is not implemented yet.

## Commands

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
| `gbt panel reset` | Restore and save all panel defaults, clearing temporary tracking |
| `gbt panel position <x> <y>` | Set both coordinates in pixels and save |
| `gbt panel anchor [<top\|bottom> <left\|right>]` | View or set the position anchor and save |
| `gbt panel x <x>` / `gbt panel y <y>` | Set one coordinate, retaining the other |
| `gbt panel size <width> <height>` | Set both dimensions in pixels and save |
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
      "visible": true,
      "x": 30,
      "y": 150,
      "width": 500,
      "font_size": 10,
      "history_lines": 6,
      "refresh_interval": 0.5,
      "tracking": {
        "current": "default",
        "sets": {
          "default": [
            { "name": "Strategy", "expression": ["gambit.strategy"] },
            { "name": "Namespace", "expression": ["gambit.namespace or '(base settings)'"] }
          ],
          "notes": [{ "name": "Spawn order", "value": ["1. Spawn NM A", "2. Spawn NM B"] }],
          "none": []
        }
      }
    }
  }
}
```

Each named set is an array of entries. Names are case-sensitive. `value` accepts
a string or an array of display lines. Expressions can also return arrays: each
element appears on its own indented line under the entry heading. Scalar results
appear on one content line. Automatic height and subsequent rows reflow as the
array length changes. Switching sets rebuilds tracking rows and
panel height, retaining placement, width, and recent output. Empty sets show only
the automation toggle and log. The initial prototype's tracking array format is
also accepted and becomes a `default` set.

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
line, including value indentation, using the same character-width estimate as
clipping. Multiline values use their longest line; nil entries contribute no
width. The panel shrinks toward its minimum when tracking content becomes
shorter. Log text never drives automatic width. These width changes do not
modify saved settings.

Expressions use the ordinary action expression compiler and a fresh temporary
context per entry. Strings accept expressions or scripts; arrays evaluate
independent expressions in order and return the final result, matching
`context.execute`. An expression takes precedence over a static value even when
returning `false` or `nil`. A `nil` value hides both the heading and value and
reserves no rows; the entry reappears when its value becomes non-nil. `false`
continues to display normally. Updates occur every half second by default. Use short,
non-yielding expressions without side effects; these are Lua code, not sandboxed
formulas. Temporary contexts do not replace the active automation context.

Syntax/runtime failures display `[error]` on the affected entry and stop retrying
it until panel recreation (switch sets or run `gbt panel reload`). Unavailable contexts display
`[unavailable]` and are retried. Failures do not quarantine automation actions or
produce repeated chat errors.

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
