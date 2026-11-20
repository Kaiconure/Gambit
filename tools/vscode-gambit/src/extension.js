'use strict';

const fs = require('fs/promises');
const path = require('path');
const vscode = require('vscode');
const {childNamespaceTarget, createChildNamespace, discoverNamespaces} = require('./namespace-model');

async function isGambitRoot(directory) {
    try {
        await fs.access(path.join(directory, 'Gambit.lua'));
        await fs.access(path.join(directory, 'actions'));
        return true;
    } catch (_) {
        return false;
    }
}

async function findGambitRoot() {
    for (const folder of vscode.workspace.workspaceFolders || []) {
        if (await isGambitRoot(folder.uri.fsPath)) return folder.uri.fsPath;
    }
    const candidates = await vscode.workspace.findFiles('**/Gambit.lua', '**/{.git,node_modules}/**', 20);
    for (const candidate of candidates) {
        const directory = path.dirname(candidate.fsPath);
        if (await isGambitRoot(directory)) return directory;
    }
}

class NamespaceTreeProvider {
    constructor(diagnostics) {
        this.diagnostics = diagnostics;
        this.namespaces = [];
        this.root = undefined;
        this.changeEmitter = new vscode.EventEmitter();
        this.onDidChangeTreeData = this.changeEmitter.event;
    }

    async refresh() {
        this.root = await findGambitRoot();
        this.namespaces = this.root ? await discoverNamespaces(this.root) : [];
        this.publishDiagnostics();
        this.changeEmitter.fire();
    }

    publishDiagnostics() {
        this.diagnostics.clear();
        const byFile = new Map();
        for (const namespace of this.namespaces) {
            for (const problem of namespace.problems) {
                const key = namespace.configPath;
                const items = byFile.get(key) || [];
                const severity = problem.severity === 'error'
                    ? vscode.DiagnosticSeverity.Error
                    : vscode.DiagnosticSeverity.Warning;
                const diagnostic = new vscode.Diagnostic(
                    new vscode.Range(0, 0, 0, 1),
                    problem.message,
                    severity,
                );
                diagnostic.source = 'Gambit Namespace Tools';
                items.push(diagnostic);
                byFile.set(key, items);
            }
        }
        for (const [file, diagnostics] of byFile) {
            this.diagnostics.set(vscode.Uri.file(file), diagnostics);
        }
    }

    getTreeItem(element) {
        if (element.kind === 'message') {
            const item = new vscode.TreeItem(element.message, vscode.TreeItemCollapsibleState.None);
            item.iconPath = new vscode.ThemeIcon('info');
            return item;
        }
        if (element.kind === 'group') {
            const item = new vscode.TreeItem(element.label, vscode.TreeItemCollapsibleState.Expanded);
            item.id = element.source;
            item.iconPath = new vscode.ThemeIcon(element.source === 'user' ? 'account' : 'package');
            return item;
        }
        if (element.kind === 'namespace') {
            const collapsible = element.namespace.problems.length
                ? vscode.TreeItemCollapsibleState.Expanded
                : vscode.TreeItemCollapsibleState.None;
            const item = new vscode.TreeItem(element.namespace.name, collapsible);
            item.id = element.namespace.configPath;
            item.contextValue = 'gambitNamespace';
            item.description = element.namespace.parent ? `← ${element.namespace.parent}` : undefined;
            item.tooltip = new vscode.MarkdownString([
                `**${element.namespace.name}**`,
                '',
                `Source: ${element.namespace.source}`,
                element.namespace.parent ? `Inherits from: ${element.namespace.parent}` : 'No explicit parent',
                '',
                `$(file) ${element.namespace.configPath}`,
            ].join('\n\n'));
            item.iconPath = new vscode.ThemeIcon(element.namespace.problems.length ? 'warning' : 'symbol-namespace');
            item.command = {
                command: 'gambitNamespaces.openConfig',
                title: 'Open Namespace Configuration',
                arguments: [element.namespace],
            };
            return item;
        }
        const item = new vscode.TreeItem(element.problem.message, vscode.TreeItemCollapsibleState.None);
        item.iconPath = new vscode.ThemeIcon(element.problem.severity === 'error' ? 'error' : 'warning');
        item.tooltip = element.problem.path;
        return item;
    }

    getChildren(element) {
        if (!element) {
            if (!this.root) return [{kind: 'message', message: 'Open the Gambit repository to inspect namespaces.'}];
            return [
                {kind: 'group', label: 'User Namespaces', source: 'user'},
                {kind: 'group', label: 'Stock Namespaces', source: 'stock'},
            ];
        }
        if (element.kind === 'group') {
            return this.namespaces
                .filter(namespace => namespace.source === element.source)
                .map(namespace => ({kind: 'namespace', namespace}));
        }
        if (element.kind === 'namespace') {
            return element.namespace.problems.map(problem => ({kind: 'problem', problem}));
        }
        return [];
    }

    getParent(element) {
        if (element.kind === 'namespace') {
            return this.getChildren().find(group => group.source === element.namespace.source);
        }
    }

    dispose() {
        this.changeEmitter.dispose();
    }
}

async function activate(context) {
    const diagnostics = vscode.languages.createDiagnosticCollection('gambitNamespaces');
    const provider = new NamespaceTreeProvider(diagnostics);
    const tree = vscode.window.createTreeView('gambitNamespaces', {treeDataProvider: provider});
    context.subscriptions.push(
        diagnostics,
        provider,
        tree,
        vscode.commands.registerCommand('gambitNamespaces.refresh', () => provider.refresh()),
        vscode.commands.registerCommand('gambitNamespaces.openConfig', async namespace => {
            if (!namespace || !namespace.configPath) return;
            const document = await vscode.workspace.openTextDocument(namespace.configPath);
            await vscode.window.showTextDocument(document);
        }),
        vscode.commands.registerCommand('gambitNamespaces.createChild', async element => {
            if (element?.kind !== 'namespace' || !provider.root) return;
            const root = provider.root;
            const parent = element.namespace;
            const name = await vscode.window.showInputBox({
                title: `New Child Namespace under ${parent.name}`,
                prompt: 'Enter the name of the new folder',
                validateInput: async value => {
                    if (!value) return;
                    try {
                        const target = await childNamespaceTarget(root, parent, value);
                        return {
                            message: path.relative(root, target.directory),
                            severity: vscode.InputBoxValidationSeverity.Info,
                        };
                    } catch (error) {
                        return error.message;
                    }
                },
            });
            if (!name) return;
            let configPath;
            try {
                configPath = await createChildNamespace(root, parent, name);
            } catch (error) {
                vscode.window.showErrorMessage(`Could not create the child namespace. ${error.message}`);
                return;
            }
            try {
                await provider.refresh();
                const namespace = provider.namespaces.find(item => item.configPath === configPath);
                if (namespace) await tree.reveal({kind: 'namespace', namespace}, {select: true});
            } catch (error) {
                vscode.window.showWarningMessage(`The child namespace was created, but the tree could not show it. ${error.message}`);
            }
            const document = await vscode.workspace.openTextDocument(configPath);
            const column = document.lineAt(1).text.lastIndexOf('"');
            await vscode.window.showTextDocument(document, {selection: new vscode.Range(1, column, 1, column)});
        }),
    );

    const watcher = vscode.workspace.createFileSystemWatcher('**/{namespaces,_namespaces}/**/*');
    const refresh = () => provider.refresh();
    watcher.onDidCreate(refresh, undefined, context.subscriptions);
    watcher.onDidChange(refresh, undefined, context.subscriptions);
    watcher.onDidDelete(refresh, undefined, context.subscriptions);
    context.subscriptions.push(watcher);

    await provider.refresh();
}

function deactivate() {}

module.exports = {activate, deactivate};
