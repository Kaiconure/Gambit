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
| `gbt panel position <x> <y>` | Set both coordinates in pixels and save |
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
Coordinates are absolute screen offsets from the top-left corner, not relative
movements. Updates do not rebuild tracking rows or discard history.

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

## Shared appearance and log text

### Background skins

Use `gbt panel theme ffxi` for the blue-violet textured skin with silver horizontal
trim and open sides. It uses `content/ui/ffxi/cleaned-background.png` as its basis.
The six-pixel top and bottom borders stay fixed, and the center fills the width.
The center uses a fixed 400-pixel texture height to keep the
horizontal lines about 4–5 pixels apart as the panel resizes. Adjust
`texture_height` in the theme registry to tune spacing (larger means wider).
Regenerate
the three pieces and a 580-by-300 preview with `content/ui/ffxi/generate.ps1`.
The cleaned source remains unchanged.

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
