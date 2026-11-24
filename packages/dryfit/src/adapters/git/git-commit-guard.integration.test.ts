import { chmod, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createTempDir } from '../../testing/temp-dir.ts';
import { NodeProcessRunner } from '../node/node-process-runner.ts';
import { GitCommitGuard } from './git-commit-guard.ts';

const git = new NodeProcessRunner({
  env: {
    GIT_AUTHOR_NAME: 'dryfit test',
    GIT_AUTHOR_EMAIL: 'test@dryfit.invalid',
    GIT_COMMITTER_NAME: 'dryfit test',
    GIT_COMMITTER_EMAIL: 'test@dryfit.invalid',
    GIT_CONFIG_GLOBAL: '/dev/null',
    GIT_CONFIG_NOSYSTEM: '1',
  },
});

describe('GitCommitGuard, with real git', () => {
  let repo: string;
  let cleanup: () => Promise<void>;
  const guard = new GitCommitGuard(git);

  const run = async (...args: string[]) => git.run({ command: 'git', args, cwd: repo });
  const commit = async (file: string, content: string) => {
    await mkdir(join(repo, file, '..'), { recursive: true });
    await writeFile(join(repo, file), content);
    await run('add', file);
    return run('commit', '-m', `change ${file}`);
  };
  const leaky = JSON.stringify({ dependencies: { '@acme/ui': '1.4.1-dev.20261118143201' } });

  beforeEach(async () => {
    ({ path: repo, cleanup } = await createTempDir());
    await run('init', '-q');
  });
  afterEach(() => cleanup());

  it('refuses to commit a manifest or lockfile carrying a dev version, anywhere in the repo', async () => {
    expect(await guard.install(repo)).toBe('installed');

    const root = await commit('package.json', leaky);
    const nested = await commit('apps/shop/package-lock.json', leaky);

    expect([root.exitCode, nested.exitCode]).toEqual([1, 1]);
    expect(root.stderr).toContain('dryfit: these staged files point at a local dev build');
    expect(nested.stderr).toContain('apps/shop/package-lock.json');
  });

  it('refuses to commit the dev server setting dryfit keeps while linked', async () => {
    await guard.install(repo);
    const setting = '{ "options": { "prebundle": { "exclude": ["@acme/ui", "dryfit:linked"] } } }';
    expect((await commit('angular.json', '{ "prebundle": { "exclude": ["@acme/ui"] } }')).exitCode).toBe(0);

    const workspace = await commit('angular.json', setting);
    const nx = await commit('apps/shop/project.json', setting);

    expect([workspace.exitCode, nx.exitCode]).toEqual([1, 1]);
    expect(workspace.stderr).toContain('angular.json');
    expect(nx.stderr).toContain('apps/shop/project.json');
  });

  it('catches files whose paths git would quote, such as non-ASCII folder names', async () => {
    await guard.install(repo);

    const result = await commit('apps/café/package.json', leaky);

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain('apps/café/package.json');
  });

  it('lets clean commits through', async () => {
    await guard.install(repo);

    expect((await commit('package.json', '{"dependencies":{"@acme/ui":"1.4.0"}}')).exitCode).toBe(0);
    expect((await commit('src/main.ts', 'const v = "1.4.1-dev.20261118143201";')).exitCode).toBe(0);
  });

  it('runs before an existing hook and leaves it working', async () => {
    const hook = join(repo, '.git/hooks/pre-commit');
    await writeFile(hook, '#!/bin/sh\necho existing hook ran >&2\n');
    await chmod(hook, 0o755);

    await guard.install(repo);
    const result = await commit('README.md', 'hi');

    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain('existing hook ran');
  });

  it('follows core.hooksPath, which is where Husky puts its hooks', async () => {
    await run('config', 'core.hooksPath', '.husky/_');
    // Husky ignores its own folder, so its hooks are not part of the repository.
    await mkdir(join(repo, '.husky/_'), { recursive: true });
    await writeFile(join(repo, '.husky/_/.gitignore'), '*\n');

    await guard.install(repo);

    expect(await readFile(join(repo, '.husky/_/pre-commit'), 'utf8')).toContain('dryfit commit guard');
    expect((await commit('package.json', leaky)).exitCode).toBe(1);
  });

  it('takes itself out again, deleting a hook it created and restoring one it joined', async () => {
    const created = join(repo, '.git/hooks/pre-commit');
    await guard.install(repo);
    await guard.remove(repo);
    await expect(stat(created)).rejects.toThrow(/ENOENT/);

    await writeFile(created, '#!/bin/sh\necho mine\n');
    await guard.install(repo);
    await guard.remove(repo);
    expect(await readFile(created, 'utf8')).toBe('#!/bin/sh\necho mine\n');
  });

  it('gives back an existing empty hook as it was', async () => {
    const hook = join(repo, '.git/hooks/pre-commit');
    await writeFile(hook, '');

    await guard.install(repo);
    await guard.remove(repo);

    expect(await readFile(hook, 'utf8')).toBe('');
  });

  it('leaves a hook the repository shares alone, so the guard is never committed for everyone', async () => {
    await run('config', 'core.hooksPath', '.githooks');
    await commit('.githooks/pre-commit', '#!/bin/sh\necho team hook\n');

    await expect(guard.install(repo)).rejects.toThrow(/part of the repository/);
    expect(await readFile(join(repo, '.githooks/pre-commit'), 'utf8')).toBe('#!/bin/sh\necho team hook\n');
  });

  it('leaves a hook written in another language alone', async () => {
    const hook = join(repo, '.git/hooks/pre-commit');
    await writeFile(hook, '#!/usr/bin/env node\nconsole.log("lint")\n');

    await expect(guard.install(repo)).rejects.toThrow(/not a shell script/);
    expect(await readFile(hook, 'utf8')).toBe('#!/usr/bin/env node\nconsole.log("lint")\n');
  });

  it('gives a hook that was not executable its mode back', async () => {
    const hook = join(repo, '.git/hooks/pre-commit');
    await writeFile(hook, '#!/bin/sh\nexit 1\n');
    await chmod(hook, 0o644);

    await guard.install(repo);
    await guard.remove(repo);

    expect((await stat(hook)).mode & 0o777).toBe(0o644);
    expect(await readFile(hook, 'utf8')).toBe('#!/bin/sh\nexit 1\n');
  });

  it('reports a folder that is not a git repository', async () => {
    const { path, cleanup: cleanOther } = await createTempDir();

    expect(await guard.install(path)).toBe('not-a-repo');
    await guard.remove(path);
    await cleanOther();
  });
});
