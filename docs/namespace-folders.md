# Namespace folder names

Gambit prefers `settings/_ns` as its namespace root. If that directory does not
exist, an existing `settings/.ns` is used. If neither exists, new namespaces are
created under `_ns`. When both exist, only `_ns` is searched; roots never merge.
Existing folders are not automatically renamed. You may rename `.ns` to `_ns`
and reload settings when ready.

Each namespace path segment is resolved independently: the exact directory name
wins; if absent, Gambit tries an underscore-prefixed directory. Thus `xp/cleave`
can refer to `_ns/_xp/_cleave`, `_ns/xp/_cleave`, or `_ns/_xp/cleave`.
Once an exact parent directory is selected, lookup does not backtrack into its
underscore-prefixed sibling to find missing children.

Commands, saved default namespaces, and `inherits_from` may keep logical names
such as `xp/cleave`. Explicit `_xp/_cleave` paths are also accepted. Inheritance
cycles are checked using resolved paths, so alternate spellings cannot hide a
cycle. Reserved names such as `actions` and `players` remain reserved with an
underscore prefix too.

Loads, imports, common-file discovery, contribution precedence, configuration
creation, and saves use resolved physical directories. Creating `xp/new` when
only `_xp` exists creates `_xp/new`; new segments are not automatically prefixed.
To create prefixed directories explicitly, use `_xp/_new`.
