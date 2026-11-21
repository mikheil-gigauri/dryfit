import { describe, expect, it } from 'vitest';
import { needsRestart } from './daemon-version.ts';

const daemon = (version: string, apiVersion = 1) => ({ version, apiVersion });

describe('needsRestart', () => {
  it('keeps a daemon of the same version', () => {
    expect(needsRestart(daemon('1.2.0'), '1.2.0', 1)).toBe(false);
  });

  it('replaces an older daemon, so an update takes effect', () => {
    expect(needsRestart(daemon('1.1.9'), '1.2.0', 1)).toBe(true);
    expect(needsRestart(daemon('1.2.0-dev.20261119143201'), '1.2.0', 1)).toBe(true);
  });

  it('keeps a newer daemon that speaks the same API, so two CLIs do not fight over it', () => {
    expect(needsRestart(daemon('1.3.0'), '1.2.0', 1)).toBe(false);
    expect(needsRestart(daemon('1.2.1'), '1.2.0', 1)).toBe(false);
  });

  it('replaces a daemon that speaks another API, whichever is newer', () => {
    expect(needsRestart(daemon('1.3.0', 2), '1.2.0', 1)).toBe(true);
    expect(needsRestart(daemon('1.1.0', 1), '1.2.0', 2)).toBe(true);
  });

  it('replaces a daemon whose version cannot be ordered', () => {
    expect(needsRestart(daemon('not-a-version'), '1.2.0', 1)).toBe(true);
  });
});
