# Gambit Namespace Tools

An exploratory VS Code extension for inspecting and validating Gambit namespaces.

## Current functionality

- Detects a Gambit workspace from `Gambit.lua` and the stock `actions` folder.
- Lists user and stock namespaces in the Explorer sidebar.
- Displays each namespace's `inherits_from` value.
- Opens `.nsconfig` files directly from the namespace tree.
- Creates child namespaces from the tree's **New Child Namespace…** context menu.
- Reports malformed `.nsconfig` files and missing inheritance parents.
- Warns about ignored namespace action directories such as `actions/common/`,
  which should be `actions/lib/common/`.
- Refreshes automatically as namespace files change.

Right-click a namespace and choose **New Child Namespace…**, then enter a single
folder name. The extension creates a child with an explicit `inherits_from`
setting and a starter `actions/lib/common/common.json` containing empty
`vars` and `contributions`. Children of stock namespaces go under the user
namespace root and inherit the selected stock namespace via `gambit:`.

## Running from the Gambit repository

1. Open the Gambit repository root in VS Code.
2. Open **Run and Debug** (`Ctrl+Shift+D`).
3. Select **Run Gambit Namespace Tools**.
4. Press `F5`.
5. In the Extension Development Host window, expand **Gambit Namespaces** in
   the Explorer sidebar.

The prototype uses plain JavaScript and has no build step or npm dependencies.
VS Code's extension host executes it directly.

## Packaging later

Packaging requires Node.js and Microsoft's `@vscode/vsce` tool:

```powershell
npx @vscode/vsce package
```

That command creates an installable `.vsix` file. Node is not required merely
to launch this prototype with `F5`.

## Near-term direction

1. Add schema-aware `.nsconfig` validation and quick fixes.
2. Show the full inheritance chain and detect cycles.
3. Expose effective per-job values and their source provenance using Gambit's
   actual compilation rules.
