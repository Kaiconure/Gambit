# Namespace folder names

Names may contain letters, numbers, underscores, hyphens, and dots, with `/`
separating nested folders. For example, `boss/s.behemoth` is valid both when
selecting a namespace and in `.nsconfig` inheritance references. Standalone `.`
and `..` segments, leading/trailing dots, and Windows device names remain invalid.

Bundled namespaces live under `namespaces/<name>/`; user namespaces live under
`settings/namespaces/<name>/`. Each contains a `.nsconfig` and shared rules. A user
namespace replaces the entire bundled namespace with the same name, even if the
user folder lacks a `.nsconfig`. Files are never merged between those two copies.
Only explicitly inherited parents contribute additional namespace content,
followed by the normal global settings and shipped-library fallbacks.
`//gbt ns -list` marks bundled namespaces. Selecting one does not write into its
folder. To customize shared rules, copy it into the user root or create a
differently named user namespace that inherits it.

Gambit reads and writes global character files under
`settings/players/<character>/` by default. It uses the legacy
`settings/<character>/` tree when that tree already contains files and the
organized character directory is absent. An existing organized character
directory takes precedence for all global settings, actions, events, data,
and output.

Prefix a namespace reference with `gambit:` to bypass a same-named user
namespace and address the bundled namespace explicitly. This works for both
selection and inheritance, for example `{"inherits_from":"gambit:follow"}`.
The bundled origin is transitive: unqualified parents of that bundled namespace
also resolve from bundled namespace folders. Character settings and processed
output remain under `settings/namespace-settings/<name>/`.

For **all** namespaces, character files are loaded and saved under
`settings/namespace-settings/<name>/players/<character>/`. Within each namespace,
these precede shared rules; inherited parents have their own character files at
the same location. Diagnostics and processed output also go here. The name uses
the resolved namespace spelling, so underscore aliases share character files.
Replacing a bundled namespace with a user copy at the same resolved name keeps
these settings. A differently named copy has separate character settings.
The former `<namespace>/players/` location is no longer searched.

Organizational roots accept an optional underscore: `settings/namespaces` or `settings/_namespaces`, and `settings/namespace-settings` or `settings/_namespace-settings`. Bundled namespaces likewise accept `namespaces/` or `_namespaces/`. For each root, the plain version wins when both exist; the two versions are never merged. Existing underscored roots remain usable. When neither version exists, automatic creation uses the plain version. Old `ns`, `_ns`, and `.ns` roots are not searched.

Add `index.json` to the active user namespace root to define aliases for commands,
character defaults, and `inherits_from`.

```json
{
  "aliases": {
    "xp": "battle",
    "xp/di": "battle/di",
    "di": "battle/di",
    "ghatjot": "sortie/ghatjot"
  }
}
```

Alias keys match the full reference exactly. Define each nested alias explicitly.
Existing folders take precedence, and a `gambit:` reference goes directly to the
bundled namespace root. Each alias target must resolve to an existing folder for
the alias to take effect. Character files use the target's resolved folder.

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
