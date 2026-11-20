'use strict';

const fs = require('fs/promises');
const path = require('path');

function namespaceName(namespaceRoot, directory) {
    return path.relative(namespaceRoot, directory)
        .split(path.sep)
        .filter(Boolean)
        .map(part => part.replace(/^_/, ''))
        .join('/');
}

async function exists(target) {
    try {
        await fs.access(target);
        return true;
    } catch (_) {
        return false;
    }
}

async function namespaceRoot(directory) {
    const plain = path.join(directory, 'namespaces');
    const prefixed = path.join(directory, '_namespaces');
    return await exists(plain) || !await exists(prefixed) ? plain : prefixed;
}

async function childNamespaceTarget(gambitRoot, parent, name) {
    if (!/^[a-z0-9_.-]+$/i.test(name) || name.startsWith('.') || name.endsWith('.')) {
        throw new Error('Enter one folder name using letters, numbers, underscores, hyphens, or dots. Dots cannot start or end the name.');
    }
    const normalized = name.toLowerCase().replace(/^_+/, '');
    if (/^(actions|events|players|global|gambit)$/.test(normalized)
        || /^(con|nul|aux|prn|com[1-9]|lpt[1-9])(?:\.|$)/.test(normalized)) {
        throw new Error('That folder name is reserved.');
    }
    if (!parent.config || typeof parent.config !== 'object' || Array.isArray(parent.config)
        || parent.config.inheritable === false) {
        throw new Error('Choose a parent with a valid .nsconfig that allows inheritance.');
    }

    const userRoot = await namespaceRoot(path.join(gambitRoot, 'settings'));
    const sourceRoot = parent.source === 'stock' ? await namespaceRoot(gambitRoot) : userRoot;
    const segments = path.relative(sourceRoot, parent.directory).split(path.sep);
    let directory = parent.directory;
    if (parent.source === 'stock') {
        directory = userRoot;
        for (const segment of parent.name.split('/')) {
            const plain = path.join(directory, segment);
            const prefixed = path.join(directory, '_' + segment);
            directory = !await exists(plain) && await exists(prefixed) ? prefixed : plain;
        }
    }
    const child = path.join(directory, name);
    const siblings = await fs.readdir(directory).catch(error => {
        if (error.code === 'ENOENT') return [];
        throw error;
    });
    const alias = name.toLowerCase().replace(/^_/, '');
    if (siblings.some(sibling => sibling.toLowerCase().replace(/^_/, '') === alias)) {
        throw new Error('A folder or file with that namespace name already exists.');
    }
    return {
        directory: child,
        inheritsFrom: (parent.source === 'stock' ? 'gambit:' : '') + segments.join('/'),
    };
}

async function createChildNamespace(gambitRoot, parent, name) {
    const target = await childNamespaceTarget(gambitRoot, parent, name);
    const configPath = path.join(target.directory, '.nsconfig');
    const commonDirectory = path.join(target.directory, 'actions', 'lib', 'common');
    await fs.mkdir(path.dirname(target.directory), {recursive: true});
    await fs.mkdir(target.directory);
    try {
        await fs.mkdir(commonDirectory, {recursive: true});
        await fs.writeFile(path.join(commonDirectory, 'common.json'),
            JSON.stringify({vars: {}, contributions: []}, null, 2) + '\n', {flag: 'wx'});
        await fs.writeFile(configPath,
            JSON.stringify({inherits_from: target.inheritsFrom}, null, 2) + '\n', {flag: 'wx'});
    } catch (error) {
        await fs.rm(target.directory, {recursive: true, force: true});
        throw error;
    }
    return configPath;
}

async function findConfigs(directory, results = []) {
    if (!await exists(directory)) return results;
    const entries = await fs.readdir(directory, {withFileTypes: true});
    for (const entry of entries) {
        const target = path.join(directory, entry.name);
        if (entry.isDirectory()) await findConfigs(target, results);
        else if (entry.isFile() && entry.name === '.nsconfig') results.push(target);
    }
    return results;
}

async function misplacedActionDirectories(namespaceDirectory) {
    const actions = path.join(namespaceDirectory, 'actions');
    if (!await exists(actions)) return [];
    const entries = await fs.readdir(actions, {withFileTypes: true});
    return entries
        .filter(entry => entry.isDirectory() && entry.name !== 'lib')
        .map(entry => ({
            severity: 'warning',
            message: `The directory actions/${entry.name}/ is ignored. Namespace action libraries belong under actions/lib/${entry.name}/.`,
            path: path.join(actions, entry.name),
        }));
}

async function readNamespace(namespaceRoot, configPath, source) {
    const directory = path.dirname(configPath);
    const record = {
        name: namespaceName(namespaceRoot, directory),
        physicalName: path.relative(namespaceRoot, directory).split(path.sep).join('/'),
        source,
        directory,
        configPath,
        parent: undefined,
        problems: [],
    };
    try {
        const text = await fs.readFile(configPath, 'utf8');
        const config = JSON.parse(text);
        record.config = config;
        if (typeof config.inherits_from === 'string' && config.inherits_from.trim()) {
            record.parent = config.inherits_from.replace(/^gambit:/i, '');
        }
    } catch (error) {
        record.problems.push({
            severity: 'error',
            message: `Unable to read .nsconfig: ${error.message}`,
            path: configPath,
        });
    }
    record.problems.push(...await misplacedActionDirectories(directory));
    return record;
}

function addInheritanceProblems(namespaces) {
    const names = new Set();
    for (const item of namespaces) {
        for (const name of [item.name, item.physicalName]) {
            names.add(name.toLowerCase());
            if (item.source === 'stock') names.add('gambit:' + name.toLowerCase());
        }
    }
    for (const namespace of namespaces) {
        if (namespace.parent && !names.has(namespace.config.inherits_from.toLowerCase())) {
            namespace.problems.push({
                severity: 'warning',
                message: `Inherited namespace '${namespace.parent}' was not found in settings/namespaces or namespaces.`,
                path: namespace.configPath,
            });
        }
    }
}

async function discoverNamespaces(gambitRoot) {
    const roots = [
        {source: 'user', directory: await namespaceRoot(path.join(gambitRoot, 'settings'))},
        {source: 'stock', directory: await namespaceRoot(gambitRoot)},
    ];
    const namespaces = [];
    for (const root of roots) {
        for (const configPath of await findConfigs(root.directory)) {
            namespaces.push(await readNamespace(root.directory, configPath, root.source));
        }
    }
    addInheritanceProblems(namespaces);
    namespaces.sort((a, b) => a.name.localeCompare(b.name) || a.source.localeCompare(b.source));
    return namespaces;
}

module.exports = {
    childNamespaceTarget,
    createChildNamespace,
    discoverNamespaces,
    namespaceName,
};
