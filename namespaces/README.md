# Bundled namespaces

Place each bundled namespace in its own folder with a `.nsconfig` and shared
action/event files. User namespaces under `settings/_namespaces/` take precedence over
bundled namespaces with the same name as a whole; their files are not merged.
Additional namespace content comes only from explicit `inherits_from` parents.
Use a `gambit:`-qualified reference to select or inherit bundled content even
when a same-named user namespace exists.

Character overrides and generated files belong under
`settings/_namespace-settings/<name>/players/<character>/`, for both bundled and
user namespaces. Do not put character files in these bundled folders.

See [namespace paths](../docs/namespace-folders.md) for resolution and inheritance.
