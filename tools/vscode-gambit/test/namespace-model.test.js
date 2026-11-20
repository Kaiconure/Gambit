'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const {createChildNamespace, discoverNamespaces, namespaceName} = require('../src/namespace-model');

async function writeJson(file, value) {
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, JSON.stringify(value, null, 2));
}

test('normalizes underscored path segments to namespace names', () => {
    const root = path.join('root', 'namespaces');
    assert.equal(namespaceName(root, path.join(root, '_base')), 'base');
    assert.equal(namespaceName(root, path.join(root, 'boss', '_normal')), 'boss/normal');
});

test('discovers inheritance and warns about misplaced action libraries', async t => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'gambit-vscode-'));
    t.after(() => fs.rm(root, {recursive: true, force: true}));

    const namespaces = path.join(root, 'settings', 'namespaces');
    await writeJson(path.join(namespaces, '_base', '.nsconfig'), {});
    await writeJson(path.join(namespaces, 'xp', '.nsconfig'), {inherits_from: 'base'});
    await writeJson(path.join(namespaces, 'xp', 'cleave', '.nsconfig'), {inherits_from: 'xp'});
    await writeJson(path.join(namespaces, 'xp', 'di', '.nsconfig'), {inherits_from: 'xp/cleave'});
    await writeJson(path.join(namespaces, 'xp', 'di', 'actions', 'common', 'common.json'), {vars: {}});

    const found = await discoverNamespaces(root);
    const di = found.find(namespace => namespace.name === 'xp/di');
    assert.ok(di);
    assert.equal(di.parent, 'xp/cleave');
    assert.match(di.problems[0].message, /actions\/common\/.*actions\/lib\/common\//);
});

test('reports missing parents and malformed namespace configuration', async t => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'gambit-vscode-'));
    t.after(() => fs.rm(root, {recursive: true, force: true}));

    const namespaces = path.join(root, 'settings', 'namespaces');
    await writeJson(path.join(namespaces, 'child', '.nsconfig'), {inherits_from: 'missing'});
    const malformed = path.join(namespaces, 'broken', '.nsconfig');
    await fs.mkdir(path.dirname(malformed), {recursive: true});
    await fs.writeFile(malformed, '{');

    const found = await discoverNamespaces(root);
    assert.match(found.find(namespace => namespace.name === 'child').problems[0].message, /was not found/);
    assert.match(found.find(namespace => namespace.name === 'broken').problems[0].message, /Unable to read/);
});

test('scaffolds a user child of a stock namespace and preserves existing files', async t => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'gambit-vscode-'));
    t.after(() => fs.rm(root, {recursive: true, force: true}));

    await writeJson(path.join(root, 'namespaces', '_boss', '.nsconfig'), {});
    const userParent = path.join(root, 'settings', '_namespaces', '_boss');
    await writeJson(path.join(userParent, '.nsconfig'), {});
    const namespaces = await discoverNamespaces(root);
    const stock = namespaces.find(namespace => namespace.source === 'stock');
    const configPath = await createChildNamespace(root, stock, 's.behemoth');
    assert.equal(configPath, path.join(userParent, 's.behemoth', '.nsconfig'));
    assert.deepEqual(JSON.parse(await fs.readFile(configPath, 'utf8')), {inherits_from: 'gambit:_boss'});
    const commonPath = path.join(path.dirname(configPath), 'actions', 'lib', 'common', 'common.json');
    assert.deepEqual(JSON.parse(await fs.readFile(commonPath, 'utf8')), {vars: {}, contributions: []});
    await assert.rejects(createChildNamespace(root, stock, '_S.BEHEMOTH'), /already exists/);
    await assert.rejects(createChildNamespace(root, stock, '../escape'), /one folder name/);
    const child = (await discoverNamespaces(root)).find(namespace => namespace.configPath === configPath);
    assert.deepEqual(child.problems, []);

    const user = namespaces.find(namespace => namespace.source === 'user');
    const userConfig = await createChildNamespace(root, user, 'another');
    assert.deepEqual(JSON.parse(await fs.readFile(userConfig, 'utf8')), {inherits_from: '_boss'});
});
