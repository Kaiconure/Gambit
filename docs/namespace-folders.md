# Namespace folder names

Names may contain letters, numbers, underscores, hyphens, and dots, with `/`
separating nested folders. For example, `boss/s.behemoth` is valid both when
selecting a namespace and in `.nsconfig` inheritance references. Standalone `.`
and `..` segments, leading/trailing dots, and Windows device names remain invalid.

Bundled namespaces live under `namespaces/<name>/`; user namespaces live under
`settings/_namespaces/<name>/`. Each contains a `.nsconfig` and shared rules. A user
namespace replaces the entire bundled namespace with the same name, even if the
user folder lacks a `.nsconfig`. Files are never merged between those two copies.
Only explicitly inherited parents contribute additional namespace content,
followed by the normal global settings and shipped-library fallbacks.
`//gbt ns -list` marks bundled namespaces. Selecting one does not write into its
folder. To customize shared rules, copy it into the user root or create a
differently named user namespace that inherits it.

For **all** namespaces, character files are loaded and saved under
`settings/_namespace-settings/<name>/players/<character>/`. Within each namespace,
these precede shared rules; inherited parents have their own character files at
the same location. Diagnostics and processed output also go here. The name uses
the resolved namespace spelling, so underscore aliases share character files.
Replacing a bundled namespace with a user copy at the same resolved name keeps
these settings. A differently named copy has separate character settings.
The former `<namespace>/players/` location is no longer searched.

Organizational roots accept an optional underscore: `settings/_namespaces` or `settings/namespaces`, and `settings/_namespace-settings` or `settings/namespace-settings`. Bundled namespaces likewise accept `_namespaces/` or `namespaces/`. For each root, the underscore version wins when both exist; the two versions are never merged. Existing plain roots remain usable. When neither version exists, automatic creation uses the underscore version. Old `ns`, `_ns`, and `.ns` roots are not searched.

Each namespace path segment is resolved independently: the exact directory name
wins; if absent, Gambit tries an underscore-prefixed directory. Thus `xp/cleave`
can refer to `namespaces/_xp/_cleave`, `namespaces/xp/_cleave`, or `namespaces/_xp/cleave`.
Once an exact parent directory is selected, lookup does not backtrack into its
underscore-prefixed sibling to find missing children.

Commands, saved default namespaces, and `inherits_from` may keep logical names
such as `xp/cleave`. Explicit `_xp/_cleave` paths are also accepted. Inheritance
cycles are checked using resolved paths, so alternate spellings cannot hide a
cycle. Reserved names such as `actions`, `players`, and `events` remain reserved with an
underscore prefix too.

Loads, imports, common-file discovery, contribution precedence, configuration
creation use resolved physical directories; character saves use the separate
character-settings location above. Creating `xp/new` when
only `_xp` exists creates `_xp/new`; new segments are not automatically prefixed.
To create prefixed directories explicitly, use `_xp/_new`.
