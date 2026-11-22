import type React from 'react';
import {
  AbsoluteFill,
  Audio,
  Img,
  interpolate,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import { AppStills, ease, Headline, type Line, Pill, SceneFade, Terminal, Window } from './components';
import { color, font, SCENES, s, VO } from './theme';

export const Promo: React.FC = () => (
  <AbsoluteFill style={{ background: color.bg }}>
    <Backdrop />
    {Object.entries(SCENES).map(([name, { from, to }]) => {
      const Scene = scenes[name as keyof typeof SCENES];
      return (
        <Sequence key={name} from={from} durationInFrames={to - from} name={name}>
          <SceneFade
            duration={to - from}
            inFrames={name === 'problem' ? 0 : 8}
            outFrames={name === 'end' ? 0 : 8}
          >
            <Scene duration={to - from} />
          </SceneFade>
        </Sequence>
      );
    })}
    {VO.map((line) => {
      const length = s(line.to - line.from);
      return (
        <Sequence key={line.at} from={s(line.at)} durationInFrames={length} name={`vo ${line.at}s`}>
          <Audio
            src={staticFile('vo.mp3')}
            trimBefore={s(line.from)}
            trimAfter={s(line.to)}
            volume={(f) =>
              interpolate(f, [0, 2, length - 3, length], [0, 1, 1, 0], { extrapolateRight: 'clamp' })
            }
          />
        </Sequence>
      );
    })}
  </AbsoluteFill>
);

/** The dark stage everything sits on: a faint teal glow and a fine grid. */
const Backdrop: React.FC = () => {
  const frame = useCurrentFrame();
  const drift = Math.sin(frame / 90) * 40;
  return (
    <AbsoluteFill>
      <AbsoluteFill
        style={{
          background: `radial-gradient(1100px 700px at ${960 + drift}px -120px, rgba(63,215,207,0.16), transparent 70%),
            radial-gradient(900px 600px at 1700px 1200px, rgba(76,157,255,0.08), transparent 70%)`,
        }}
      />
      <AbsoluteFill
        style={{
          backgroundImage:
            'linear-gradient(rgba(255,255,255,0.025) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.025) 1px, transparent 1px)',
          backgroundSize: '64px 64px',
          maskImage: 'radial-gradient(ellipse at center, black 30%, transparent 75%)',
        }}
      />
    </AbsoluteFill>
  );
};

const Center: React.FC<{ children: React.ReactNode; top?: number }> = ({ children, top }) => (
  <AbsoluteFill
    style={{
      alignItems: 'center',
      justifyContent: top === undefined ? 'center' : 'flex-start',
      paddingTop: top,
    }}
  >
    {children}
  </AbsoluteFill>
);

// 1. "Testing a library change in a real app shouldn't mean symlinks and broken builds."
const Problem: React.FC<{ duration: number }> = () => {
  const frame = useCurrentFrame();
  const shakeAt = 50;
  const shake =
    frame >= shakeAt ? Math.sin((frame - shakeAt) * 2.2) * 14 * Math.exp(-(frame - shakeAt) / 6) : 0;
  const lines: Line[] = [
    { text: 'added 1 package in 1s', at: 24, tone: 'dim' },
    { text: '~/code/acme/shop % npm start', at: 36, tone: 'dim' },
    { text: 'Error: Invalid hook call.', at: shakeAt, tone: 'err' },
    { text: 'You might have more than one copy of React in the same app.', at: shakeAt + 6, tone: 'err' },
    { text: '  ↳ node_modules/@acme/ui → ../../ui (symlink)', at: shakeAt + 14, tone: 'err' },
  ];
  return (
    <>
      <Center>
        <Terminal
          command="npm link ../ui"
          cwd="~/code/acme/shop"
          typeFrom={6}
          lines={lines}
          width={1240}
          fontSize={27}
          style={{ transform: `translateX(${shake}px)` }}
        />
      </Center>
      <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'flex-end', paddingBottom: 120 }}>
        <div style={{ display: 'flex', gap: 28 }}>
          <Struck word="symlinks" at={s(3.7)} />
          <Struck word="broken builds" at={s(4.5)} />
        </div>
      </AbsoluteFill>
    </>
  );
};

const Struck: React.FC<{ word: string; at: number }> = ({ word, at }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame: frame - at, fps, config: { damping: 14, stiffness: 180 } });
  const strike = ease(frame, at + 6, at + 14);
  return (
    <div
      style={{
        position: 'relative',
        padding: '14px 30px',
        borderRadius: 14,
        background: 'rgba(255,107,94,0.12)',
        border: '1px solid rgba(255,107,94,0.35)',
        fontFamily: font.sans,
        fontSize: 40,
        fontWeight: 600,
        color: color.red,
        opacity: frame >= at ? 1 : 0,
        transform: `scale(${0.7 + 0.3 * pop})`,
      }}
    >
      {word}
      <div
        style={{
          position: 'absolute',
          left: 22,
          right: 22,
          top: '52%',
          height: 4,
          borderRadius: 2,
          background: color.red,
          transformOrigin: 'left',
          transform: `scaleX(${strike})`,
        }}
      />
    </div>
  );
};

// 2. "Dryfit installs your change into the apps you choose, exactly the way a real release would."
const Link: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const handoff = 78;
  const out = ease(frame, handoff, handoff + 14);
  return (
    <>
      <Headline text="Installed the way a release would be" delay={2} />
      <Center top={250}>
        <div style={{ opacity: 1 - out, transform: `translateY(${-out * 40}px) scale(${1 - out * 0.04})` }}>
          <Terminal
            command="dryfit link ../shop ../admin"
            typeFrom={8}
            width={1360}
            fontSize={24}
            lines={[
              {
                text: '✓ Linked @acme/ui into ~/code/acme/shop (snapshot taken, commit guard installed)',
                at: 32,
                tone: 'ok',
              },
              { text: '  running 1.4.1-dev.20261120190218', at: 37, tone: 'info' },
              {
                text: '✓ Linked @acme/ui into ~/code/acme/admin (snapshot taken, commit guard installed)',
                at: 44,
                tone: 'ok',
              },
              { text: '  running 1.4.1-dev.20261120190218', at: 49, tone: 'info' },
            ]}
          />
        </div>
      </Center>
      <Sequence from={handoff} durationInFrames={duration - handoff}>
        <Center top={170}>
          <AppStills
            stills={[
              { src: 'ui/link-0.png', at: 0 },
              { src: 'ui/link-0b.png', at: 28 },
              { src: 'ui/link-1.png', at: 46 },
              { src: 'ui/link-1b.png', at: 64 },
              { src: 'ui/link-2.png', at: 82 },
            ]}
            cursor={[
              { at: 8, x: 1500, y: 880 },
              { at: 26, x: 1872, y: 466 },
              { at: 46, x: 1872, y: 466 },
              { at: 62, x: 1872, y: 565 },
              { at: 84, x: 1872, y: 565 },
              { at: 104, x: 1640, y: 840 },
            ]}
            clicks={[28, 64]}
          />
        </Center>
      </Sequence>
    </>
  );
};

// 3. "Every save builds, publishes, installs, and clears the caches that would hide it."
const Watch: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const handoff = 100;
  const out = ease(frame, handoff, handoff + 14);
  return (
    <>
      <Headline text="Every save lands in every app" delay={2} />
      <AbsoluteFill
        style={{
          flexDirection: 'row',
          alignItems: 'flex-start',
          justifyContent: 'center',
          gap: 36,
          paddingTop: 290,
          opacity: 1 - out,
          transform: `translateY(${-out * 40}px)`,
        }}
      >
        <Editor />
        <Terminal
          command="dryfit watch"
          typeFrom={0}
          width={950}
          fontSize={22}
          lines={[
            { text: '✓ Watching @acme/ui: every change builds, publishes and installs', at: 10, tone: 'ok' },
            { text: '• @acme/ui changed', at: 34, tone: 'info' },
            { text: '• Building @acme/ui…', at: 40, tone: 'info' },
            { text: '✓ Built @acme/ui', at: 48, tone: 'ok' },
            { text: '✓ Published @acme/ui@1.4.1-dev.20261120190230', at: 56, tone: 'ok' },
            { text: '• Installing into ~/code/acme/shop…', at: 64, tone: 'info' },
            { text: '✓ Installed into ~/code/acme/shop', at: 71, tone: 'ok' },
            { text: '• Installing into ~/code/acme/admin…', at: 77, tone: 'info' },
            { text: '✓ Installed into ~/code/acme/admin', at: 84, tone: 'ok' },
          ]}
        />
      </AbsoluteFill>
      <Sequence from={handoff} durationInFrames={duration - handoff}>
        <Center top={170}>
          <AppStills
            stills={[
              { src: 'ui/watch-a.png', at: 0 },
              { src: 'ui/watch-b.png', at: 24 },
              { src: 'ui/watch-c.png', at: 46 },
              { src: 'ui/watch-d.png', at: 70 },
            ]}
            flashes={[
              { at: 24, x: 640, y: 92, w: 580, h: 46 },
              { at: 46, x: 1420, y: 334, w: 240, h: 56 },
              { at: 70, x: 1420, y: 442, w: 240, h: 56 },
            ]}
          />
        </Center>
      </Sequence>
    </>
  );
};

/** src/index.js, with the one-line edit typed in and saved. */
const Editor: React.FC = () => {
  const frame = useCurrentFrame();
  const before = "module.exports = { button: 'v1.4.0' };";
  const after = "module.exports = { button: 'v1.4.1', radius: 12 };";
  // Select the old value, then type the new one.
  const prefix = "module.exports = { button: 'v1.4.";
  const typed = Math.max(0, Math.min(after.length - prefix.length, Math.floor((frame - 10) * 1.3)));
  const text = frame < 10 ? before : prefix + after.slice(prefix.length, prefix.length + typed);
  const saved = frame >= 30;
  const badge = ease(frame, 30, 36) * (1 - ease(frame, 70, 80));
  return (
    <div style={{ position: 'relative' }}>
      <Window width={800} title={saved ? 'index.js' : 'index.js — Edited'}>
        <div
          style={{
            padding: '26px 30px 34px',
            fontFamily: font.mono,
            fontSize: 22,
            lineHeight: 1.7,
            color: color.text,
          }}
        >
          <Code n={1} text="// @acme/ui — src/index.js" dim />
          <Code n={2} text={text} highlight={frame >= 10} caret={!saved} />
          <Code n={3} text="" />
        </div>
      </Window>
      <div
        style={{
          position: 'absolute',
          right: -18,
          bottom: -26,
          padding: '12px 22px',
          borderRadius: 14,
          background: color.teal,
          color: '#05201f',
          fontFamily: font.sans,
          fontSize: 28,
          fontWeight: 700,
          opacity: badge,
          transform: `scale(${0.8 + 0.2 * badge})`,
          boxShadow: '0 16px 40px rgba(63,215,207,0.35)',
        }}
      >
        ⌘S saved
      </div>
    </div>
  );
};

const Code: React.FC<{ n: number; text: string; dim?: boolean; highlight?: boolean; caret?: boolean }> = ({
  n,
  text,
  dim,
  highlight,
  caret,
}) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        display: 'flex',
        gap: 22,
        background: highlight ? 'rgba(63,215,207,0.08)' : undefined,
        margin: '0 -30px',
        padding: '0 30px',
        whiteSpace: 'pre',
      }}
    >
      <span style={{ color: color.faint, width: 20, textAlign: 'right' }}>{n}</span>
      <span style={{ color: dim ? color.faint : color.text }}>
        {text}
        {caret && Math.floor(frame / 8) % 2 === 0 ? <span style={{ color: color.teal }}>▍</span> : null}
      </span>
    </div>
  );
};

// 4. "See it all from your menu bar."
const Menu: React.FC<{ duration: number }> = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const open = spring({ frame: frame - 6, fps, config: { damping: 20, stiffness: 170 } });
  const iconX = 1520;
  return (
    <>
      <Img
        src={staticFile('ui/watch-d.png')}
        style={{
          position: 'absolute',
          width: 1500,
          left: 120,
          top: 170,
          borderRadius: 18,
          filter: 'blur(10px) brightness(0.45)',
          transform: `scale(${1.02 - 0.02 * open})`,
        }}
      />
      {/* The macOS menu bar, right side: dryfit's own icon next to the clock. */}
      <div
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          right: 0,
          height: 50,
          background: 'rgba(28,30,36,0.82)',
          borderBottom: '1px solid rgba(255,255,255,0.06)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'flex-end',
          paddingRight: 44,
          gap: 34,
          fontFamily: font.sans,
          fontSize: 22,
          color: color.text,
        }}
      >
        <div
          style={{
            position: 'absolute',
            left: iconX - 30,
            top: 6,
            width: 60,
            height: 38,
            borderRadius: 10,
            background: `rgba(255,255,255,${0.16 * Math.min(1, open)})`,
          }}
        />
        <Img
          src={staticFile('icon-idle.png')}
          style={{
            position: 'absolute',
            left: iconX - 17,
            top: 10,
            width: 34,
            height: 30,
            filter: 'invert(1)',
          }}
        />
        <span>Fri 20 Nov</span>
        <span>23:04</span>
      </div>
      <Img
        src={staticFile('ui/menu.png')}
        style={{
          position: 'absolute',
          top: 62,
          left: iconX - 255,
          width: 510,
          borderRadius: 20,
          boxShadow: '0 40px 120px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.1)',
          transformOrigin: '50% 0%',
          opacity: Math.min(1, open * 1.5),
          transform: `translateY(${(1 - open) * -16}px) scale(${0.94 + 0.06 * open})`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 150,
          top: 430,
          width: 900,
          fontFamily: font.sans,
          fontSize: 76,
          fontWeight: 700,
          letterSpacing: -2,
          lineHeight: 1.05,
          color: color.text,
          opacity: ease(frame, 4, 18),
          transform: `translateY(${(1 - ease(frame, 4, 18)) * 20}px)`,
        }}
      >
        All of it, from
        <br />
        <span style={{ color: color.teal }}>your menu bar.</span>
      </div>
    </>
  );
};

// 5. "When you're done, every app goes back exactly as it was."
const Restore: React.FC<{ duration: number }> = () => (
  <>
    <Headline text="Back exactly as it was" delay={2} />
    <Center top={170}>
      <AppStills
        stills={[
          { src: 'ui/watch-d.png', at: 0 },
          { src: 'ui/restore-1.png', at: 28 },
          { src: 'ui/restore-2.png', at: 46 },
          { src: 'ui/restore-2b.png', at: 62 },
          { src: 'ui/restore-3.png', at: 78 },
        ]}
        cursor={[
          { at: 6, x: 1500, y: 840 },
          { at: 26, x: 1852, y: 470 },
          { at: 44, x: 1852, y: 470 },
          { at: 60, x: 1852, y: 362 },
          { at: 80, x: 1852, y: 362 },
          { at: 96, x: 1640, y: 760 },
        ]}
        clicks={[28, 62]}
      />
    </Center>
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'flex-end', paddingBottom: 40 }}>
      <div style={{ position: 'relative', width: 0, height: 70 }}>
        <Pill at={88} style={{ left: -390, whiteSpace: 'nowrap', fontFamily: font.mono, fontSize: 25 }}>
          <span style={{ color: color.green }}>✓</span>
          <span style={{ color: color.muted }}>git status</span>
          <span>nothing to commit, working tree clean</span>
        </Pill>
      </div>
    </AbsoluteFill>
  </>
);

// 6. "Dryfit. Try it before you ship it."
const End: React.FC<{ duration: number }> = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const icon = spring({ frame, fps, config: { damping: 14, stiffness: 120 } });
  const word = ease(frame, 4, 16);
  const tag = ease(frame, 36, 50);
  const cmd = ease(frame, 52, 64);
  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', fontFamily: font.sans }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 40, marginTop: -60 }}>
        <Img
          src={staticFile('app-icon.png')}
          style={{
            width: 200,
            height: 200,
            transform: `scale(${0.6 + 0.4 * icon}) rotate(${(1 - icon) * -12}deg)`,
            opacity: Math.min(1, icon * 2),
          }}
        />
        <div
          style={{
            fontSize: 168,
            fontWeight: 750,
            letterSpacing: -6,
            color: color.text,
            opacity: word,
            transform: `translateX(${(1 - word) * -24}px)`,
          }}
        >
          dryfit
        </div>
      </div>
      <div
        style={{
          marginTop: 26,
          fontSize: 58,
          fontWeight: 600,
          letterSpacing: -1.2,
          color: color.teal,
          opacity: tag,
          transform: `translateY(${(1 - tag) * 16}px)`,
        }}
      >
        Try it before you ship it.
      </div>
      <div
        style={{
          marginTop: 48,
          padding: '16px 30px',
          borderRadius: 14,
          background: 'rgba(255,255,255,0.06)',
          border: `1px solid ${color.panelEdge}`,
          fontFamily: font.mono,
          fontSize: 32,
          color: color.text,
          opacity: cmd,
        }}
      >
        <span style={{ color: color.faint }}>$ </span>npm i -g @dryfit/cli
      </div>
      <div
        style={{
          position: 'absolute',
          bottom: 44,
          right: 56,
          fontSize: 18,
          color: color.faint,
          opacity: cmd,
        }}
      >
        Voiceover: ElevenLabs
      </div>
    </AbsoluteFill>
  );
};

const scenes: Record<keyof typeof SCENES, React.FC<{ duration: number }>> = {
  problem: Problem,
  link: Link,
  watch: Watch,
  menu: Menu,
  restore: Restore,
  end: End,
};
