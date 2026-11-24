import { describe, expect, it } from 'vitest';
import type { Manifest } from '../../core/model.ts';
import type { ProjectInfo } from '../../core/ports.ts';
import { cachePathsFor } from '../../core/project/cache-paths.ts';
import { angular } from './angular.ts';
import { builtInIntegrations } from './index.ts';
import { nativeFederation } from './native-federation.ts';
import { vite } from './vite.ts';

const project = (
  manifest: Manifest,
  { rootFiles = [], configs = {} }: { rootFiles?: string[]; configs?: Record<string, unknown> } = {},
): ProjectInfo => ({
  root: '/apps/shop',
  manifest,
  rootFiles: ['package.json', ...rootFiles],
  configs: new Map(Object.entries(configs)),
});

describe('angular', () => {
  it('detects @angular/core', () => {
    expect(angular.detect(project({ dependencies: { '@angular/core': '^20.0.0' } }))).toBe(true);
  });

  it('detects an angular.json without the dependency (e.g. hoisted in a workspace)', () => {
    expect(angular.detect(project({}, { rootFiles: ['angular.json'] }))).toBe(true);
  });

  it('ignores unrelated projects', () => {
    expect(angular.detect(project({ dependencies: { react: '^19.0.0' } }))).toBe(false);
  });

  it('clears the default cache folder', () => {
    expect(angular.cachePaths(project({}, { rootFiles: ['angular.json'] }))).toEqual(['.angular/cache']);
  });

  it('honours a custom cache path from angular.json', () => {
    const custom = project({}, { configs: { 'angular.json': { cli: { cache: { path: 'tmp/ng-cache' } } } } });

    expect(angular.cachePaths(custom)).toEqual(['tmp/ng-cache']);
  });

  it('asks for angular.json to be parsed', () => {
    expect(angular.configFiles).toEqual(['angular.json']);
  });
});

describe('angular live reload', () => {
  const setting = angular.liveReload;
  if (!setting) throw new Error('angular has a live reload setting');

  /** An angular.json laid out the way Prettier leaves it: tabs, short arrays on one line. */
  const workspace = (serve: string) =>
    [
      '{',
      '\t"version": 1,',
      '\t"projects": {',
      '\t\t"shop": {',
      '\t\t\t"architect": {',
      '\t\t\t\t"build": {',
      '\t\t\t\t\t"builder": "@angular/build:application",',
      '\t\t\t\t\t"options": { "polyfills": ["zone.js"] }',
      '\t\t\t\t},',
      `\t\t\t\t"serve": ${serve}`,
      '\t\t\t}',
      '\t\t}',
      '\t}',
      '}',
      '',
    ].join('\n');
  const devServer = (
    options: string,
    configurations = '{ "development": { "buildTarget": "shop:build" } }',
  ) =>
    `{ "builder": "@angular/build:dev-server", "options": ${options}, "configurations": ${configurations} }`;
  const prebundle = (text: string) => {
    const serve = (
      JSON.parse(text) as { projects: { shop: { architect: { serve: Record<string, unknown> } } } }
    ).projects.shop.architect.serve;
    return {
      options: (serve.options as Record<string, unknown>).prebundle,
      configurations: serve.configurations,
    };
  };

  it('lives in angular.json and project.json', () => {
    expect(setting.files).toEqual(['angular.json', 'project.json']);
  });

  it('keeps linked libraries out of the dev server pre-bundle, marked as dryfit’s', () => {
    const edited = setting.apply(workspace(devServer('{ "port": 4200 }')), ['@acme/ui']);

    expect(edited).toBeDefined();
    expect(prebundle(edited ?? '').options).toEqual({ exclude: ['@acme/ui', 'dryfit:linked'] });
  });

  it('changes nothing else in the file, byte for byte, keeping a one-line object on one line', () => {
    const original = workspace(devServer('{ "port": 4200 }'));

    const edited = setting.apply(original, ['@acme/ui']) ?? '';

    expect(edited).toBe(
      original.replace(
        '"options": { "port": 4200 }',
        '"options": { "port": 4200, "prebundle": { "exclude": ["@acme/ui", "dryfit:linked"] } }',
      ),
    );
  });

  it('puts the setting on its own lines, at the file’s indent, in an object laid out that way', () => {
    const original = workspace(devServer('{\n\t\t\t\t\t\t"port": 4200\n\t\t\t\t\t}'));

    expect(setting.apply(original, ['@acme/ui'])).toBe(
      original.replace(
        '\t\t\t\t\t\t"port": 4200\n',
        [
          '\t\t\t\t\t\t"port": 4200,',
          '\t\t\t\t\t\t"prebundle": {',
          '\t\t\t\t\t\t\t"exclude": [',
          '\t\t\t\t\t\t\t\t"@acme/ui",',
          '\t\t\t\t\t\t\t\t"dryfit:linked"',
          '\t\t\t\t\t\t\t]',
          '\t\t\t\t\t\t}',
          '',
        ].join('\n'),
      ),
    );
  });

  it('adds to an exclude list the app already has, and to configurations that set their own', () => {
    const original = workspace(
      devServer(
        '{ "prebundle": { "exclude": ["@acme/charts"] } }',
        '{ "development": { "prebundle": true }, "production": { "buildTarget": "shop:build" } }',
      ),
    );

    const edited = prebundle(setting.apply(original, ['@acme/ui']) ?? '');

    expect(edited.options).toEqual({ exclude: ['@acme/charts', '@acme/ui', 'dryfit:linked'] });
    expect(edited.configurations).toEqual({
      development: { prebundle: { exclude: ['@acme/ui', 'dryfit:linked'] } },
      production: { buildTarget: 'shop:build' },
    });
  });

  it('adds a library linked later before its mark, as if both were linked at once', () => {
    const original = workspace(devServer('{}'));
    const one = setting.apply(original, ['@acme/ui']) ?? '';

    expect(setting.apply(one, ['@acme/ui', '@acme/forms'])).toBe(
      setting.apply(original, ['@acme/ui', '@acme/forms']),
    );
  });

  it('leaves a dev server that pre-bundles nothing alone, since it already rebuilds from node_modules', () => {
    expect(setting.apply(workspace(devServer('{ "prebundle": false }')), ['@acme/ui'])).toBeUndefined();
  });

  it('edits dev servers only, under the Angular CLI and Nx spellings', () => {
    const nx = JSON.stringify({
      targets: {
        serve: { executor: '@angular-devkit/build-angular:dev-server', options: {} },
        build: { executor: '@angular-devkit/build-angular:application', options: {} },
      },
    });

    const edited = JSON.parse(setting.apply(nx, ['@acme/ui']) ?? '{}');

    expect(edited.targets.serve.options.prebundle).toEqual({ exclude: ['@acme/ui', 'dryfit:linked'] });
    expect(edited.targets.build.options).toEqual({});
  });

  it('keeps comments, which the Angular CLI accepts in angular.json', () => {
    const original = workspace(devServer('{ /* local only */ "port": 4200 }'));

    expect(setting.apply(original, ['@acme/ui'])).toContain('/* local only */');
  });

  it('leaves a file it cannot read, or with nothing to edit, alone', () => {
    expect(setting.apply('{ "projects": ', ['@acme/ui'])).toBeUndefined();
    expect(
      setting.apply(workspace('{ "builder": "@angular-eslint/builder:lint" }'), ['@acme/ui']),
    ).toBeUndefined();
  });

  it('knows when the setting is on for every linked library', () => {
    const original = workspace(devServer('{}'));
    const on = setting.apply(original, ['@acme/ui']) ?? '';

    expect(setting.isOn(on, ['@acme/ui'])).toBe(true);
    expect(setting.isOn(on, ['@acme/ui', '@acme/forms'])).toBe(false);
    expect(setting.isOn(original, ['@acme/ui'])).toBe(false);
  });

  it('reverts to the original bytes when nothing else changed', () => {
    const original = workspace(devServer('{ "port": 4200 }'));
    const on = setting.apply(setting.apply(original, ['@acme/ui']) ?? '', ['@acme/ui', '@acme/forms']) ?? '';

    expect(setting.revert(on, original, ['@acme/ui', '@acme/forms'])).toBe(original);
  });

  it('reverts only its own setting when the user changed the file while linked', () => {
    const original = workspace(devServer('{ "prebundle": { "exclude": ["@acme/charts"] } }'));
    const changed = (setting.apply(original, ['@acme/ui']) ?? '').replace(
      '"zone.js"',
      '"zone.js", "@angular/localize/init"',
    );

    const reverted = setting.revert(changed, original, ['@acme/ui']) ?? '';

    expect(prebundle(reverted).options).toEqual({ exclude: ['@acme/charts'] });
    expect(reverted).toContain('"@angular/localize/init"');
  });

  it('cannot revert a file that no longer parses', () => {
    expect(setting.revert('{ "projects": ', workspace(devServer('{}')), ['@acme/ui'])).toBeUndefined();
  });
});

describe('nativeFederation', () => {
  it.each(['@angular-architects/native-federation', '@softarc/native-federation'])('detects %s', (name) => {
    expect(nativeFederation.detect(project({ devDependencies: { [name]: '^20.0.0' } }))).toBe(true);
  });

  it('clears its shared-bundle cache', () => {
    expect(nativeFederation.cachePaths(project({}))).toEqual(['node_modules/.cache/native-federation']);
  });
});

describe('vite', () => {
  it('detects vite', () => {
    expect(vite.detect(project({ devDependencies: { vite: '^7.0.0' } }))).toBe(true);
  });

  it('clears the dependency pre-bundle cache', () => {
    expect(vite.cachePaths(project({}))).toEqual(['node_modules/.vite']);
  });
});

describe('cachePathsFor', () => {
  it('unions the cache paths of every detected integration', () => {
    const app = project(
      {
        dependencies: { '@angular/core': '^20.0.0' },
        devDependencies: { '@angular-architects/native-federation': '^20.0.0' },
      },
      { rootFiles: ['angular.json'] },
    );

    expect(cachePathsFor(app, builtInIntegrations)).toEqual([
      '.angular/cache',
      'node_modules/.cache/native-federation',
    ]);
  });

  it('adds user-configured extra paths without duplicates', () => {
    const app = project({ devDependencies: { vite: '^7.0.0' } });

    expect(cachePathsFor(app, builtInIntegrations, ['node_modules/.vite', '.turbo'])).toEqual([
      'node_modules/.vite',
      '.turbo',
    ]);
  });

  it('never returns the project itself, anything outside it, or an absolute path', () => {
    const app = project({});
    const unsafe = ['.', './', '/', '..', '../sibling', 'a/../..', 'a/..', '/tmp/cache', ''];

    expect(cachePathsFor(app, [], [...unsafe, 'tmp/cache'])).toEqual(['tmp/cache']);
  });

  it('ignores a dangerous cache path configured in angular.json', () => {
    const app = project(
      {},
      { rootFiles: ['angular.json'], configs: { 'angular.json': { cli: { cache: { path: '..' } } } } },
    );

    expect(cachePathsFor(app, builtInIntegrations)).toEqual([]);
  });
});
