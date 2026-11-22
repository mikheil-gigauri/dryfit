import type React from 'react';
import {
  Easing,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import { color, font } from './theme';

const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;

/** 0→1 over [start, end] frames, eased. */
export const ease = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, end], [0, 1], { ...clamp, easing: Easing.bezier(0.22, 1, 0.36, 1) });

/** Fades a scene in over its first frames and out over its last. */
export const SceneFade: React.FC<{
  duration: number;
  children: React.ReactNode;
  inFrames?: number;
  outFrames?: number;
}> = ({ duration, children, inFrames = 8, outFrames = 8 }) => {
  const frame = useCurrentFrame();
  const fadeIn = inFrames > 0 ? ease(frame, 0, inFrames) : 1;
  const fadeOut = outFrames > 0 ? ease(frame, duration - outFrames, duration) : 0;
  const opacity = Math.min(fadeIn, 1 - fadeOut);
  return <div style={{ position: 'absolute', inset: 0, opacity }}>{children}</div>;
};

/** The one line of text each scene carries, for people watching muted. */
export const Headline: React.FC<{ text: string; delay?: number; top?: number }> = ({
  text,
  delay = 0,
  top = 64,
}) => {
  const frame = useCurrentFrame();
  const t = ease(frame, delay, delay + 14);
  return (
    <div
      style={{
        position: 'absolute',
        top,
        width: '100%',
        textAlign: 'center',
        fontFamily: font.sans,
        fontSize: 54,
        fontWeight: 650,
        letterSpacing: -1.2,
        color: color.text,
        opacity: t,
        transform: `translateY(${(1 - t) * 18}px)`,
      }}
    >
      {text}
    </div>
  );
};

export type Line = { text: string; at: number; tone?: 'ok' | 'info' | 'err' | 'cmd' | 'dim' };

/** A terminal window: `command` is typed from `typeFrom`, then each line appears at its frame. */
export const Terminal: React.FC<{
  command: string;
  cwd?: string;
  typeFrom?: number;
  lines: Line[];
  width?: number;
  title?: string;
  fontSize?: number;
  style?: React.CSSProperties;
}> = ({
  command,
  cwd = '~/code/acme/ui',
  typeFrom = 0,
  lines,
  width = 1180,
  title = 'zsh',
  fontSize = 26,
  style,
}) => {
  const frame = useCurrentFrame();
  const typed = Math.max(0, Math.min(command.length, Math.floor((frame - typeFrom) * 1.6)));
  const typing = typed < command.length;
  const caret = Math.floor(frame / 8) % 2 === 0;
  const tone = (t?: Line['tone']) =>
    t === 'ok'
      ? color.green
      : t === 'err'
        ? color.red
        : t === 'dim'
          ? color.faint
          : t === 'info'
            ? color.muted
            : color.text;
  return (
    <Window width={width} title={title} style={style}>
      <div
        style={{
          padding: '26px 32px 32px',
          fontFamily: font.mono,
          fontSize,
          lineHeight: 1.55,
          color: color.text,
        }}
      >
        <div>
          <span style={{ color: color.teal }}>{cwd}</span>
          <span style={{ color: color.faint }}> % </span>
          {command.slice(0, typed)}
          {typing || lines.every((l) => frame < l.at) ? (
            <span style={{ opacity: caret ? 1 : 0, color: color.teal }}>▍</span>
          ) : null}
        </div>
        {lines.map((line) => {
          const t = ease(frame, line.at, line.at + 6);
          return frame >= line.at ? (
            <div
              key={line.text}
              style={{
                color: tone(line.tone),
                opacity: t,
                transform: `translateX(${(1 - t) * -8}px)`,
                whiteSpace: 'pre',
              }}
            >
              {line.text}
            </div>
          ) : null;
        })}
      </div>
    </Window>
  );
};

/** A dark macOS-style window frame for the terminal and the editor. */
export const Window: React.FC<{
  width: number;
  title: string;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ width, title, children, style }) => (
  <div
    style={{
      width,
      borderRadius: 18,
      background: 'rgba(22,25,31,0.96)',
      border: `1px solid ${color.panelEdge}`,
      boxShadow: '0 40px 120px rgba(0,0,0,0.55), 0 0 0 1px rgba(0,0,0,0.6)',
      overflow: 'hidden',
      ...style,
    }}
  >
    <div
      style={{
        height: 46,
        display: 'flex',
        alignItems: 'center',
        gap: 9,
        padding: '0 18px',
        borderBottom: `1px solid ${color.panelEdge}`,
        position: 'relative',
      }}
    >
      {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
        <div key={c} style={{ width: 14, height: 14, borderRadius: 7, background: c }} />
      ))}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontFamily: font.sans,
          fontSize: 17,
          color: color.muted,
        }}
      >
        {title}
      </div>
    </div>
    {children}
  </div>
);

/** Size of the window stills in public/ui: a 1000×690pt window captured at 2x. */
const STILL = { width: 2000, height: 1380 };

export type Still = { src: string; at: number };
/** A cursor position in still pixels, reached at frame `at`. */
export type CursorKey = { at: number; x: number; y: number };
/** A rectangle in still pixels that glows briefly from frame `at`, to point at what changed. */
export type Flash = { at: number; x: number; y: number; w: number; h: number };

/**
 * dryfit's window as real captures of its states (public/ui, made by the menubar's PromoCapture test),
 * cross-faded in turn at their frames, with a cursor that clicks at `clicks`.
 */
export const AppStills: React.FC<{
  stills: Still[];
  cursor?: CursorKey[];
  clicks?: number[];
  flashes?: Flash[];
  width?: number;
}> = ({ stills, cursor = [], clicks = [], flashes = [], width = 1240 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 200 }, durationInFrames: 18 });
  const k = width / STILL.width;
  return (
    <div
      style={{
        position: 'relative',
        width,
        height: STILL.height * k,
        borderRadius: 20 * k * 2,
        overflow: 'hidden',
        boxShadow: '0 50px 140px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.07)',
        transform: `translateY(${(1 - enter) * 40}px) scale(${0.97 + enter * 0.03})`,
        opacity: enter,
      }}
    >
      {stills.map((still, i) => (
        <Img
          key={still.src}
          src={staticFile(still.src)}
          style={{
            position: 'absolute',
            inset: 0,
            width: '100%',
            height: '100%',
            opacity: i === 0 ? 1 : ease(frame, still.at, still.at + 5),
          }}
        />
      ))}
      {flashes.map((f) => {
        const t = ease(frame, f.at, f.at + 6) * (1 - ease(frame, f.at + 22, f.at + 34));
        return (
          <div
            key={`${f.at}-${f.y}`}
            style={{
              position: 'absolute',
              left: f.x * k,
              top: f.y * k,
              width: f.w * k,
              height: f.h * k,
              borderRadius: 10,
              border: `2px solid ${color.teal}`,
              background: 'rgba(63,215,207,0.12)',
              boxShadow: '0 0 24px rgba(63,215,207,0.45)',
              opacity: t,
              transform: `scale(${1.08 - 0.08 * t})`,
            }}
          />
        );
      })}
      {cursor.length > 0 ? <Cursor keys={cursor} clicks={clicks} scale={k} /> : null}
    </div>
  );
};

/** The macOS arrow, gliding between keys, with a ring at each click. */
const Cursor: React.FC<{ keys: CursorKey[]; clicks: number[]; scale: number }> = ({ keys, clicks, scale }) => {
  const frame = useCurrentFrame();
  const frames = keys.map((key) => key.at);
  const along = (values: number[]) =>
    keys.length === 1
      ? values[0]
      : interpolate(frame, frames, values, { ...clamp, easing: Easing.bezier(0.45, 0, 0.2, 1) });
  const x = along(keys.map((key) => key.x)) * scale;
  const y = along(keys.map((key) => key.y)) * scale;
  const first = keys[0].at;
  const last = keys[keys.length - 1].at;
  const opacity = ease(frame, first - 6, first) * (1 - ease(frame, last + 10, last + 18));
  const press = clicks.some((c) => frame >= c && frame < c + 4);
  return (
    <>
      {clicks.map((c) => {
        const t = ease(frame, c, c + 14);
        return frame >= c && frame < c + 16 ? (
          <div
            key={c}
            style={{
              position: 'absolute',
              left: x - 30,
              top: y - 30,
              width: 60,
              height: 60,
              borderRadius: 30,
              border: `3px solid ${color.teal}`,
              opacity: 1 - t,
              transform: `scale(${0.3 + t})`,
            }}
          />
        ) : null;
      })}
      <svg
        width={30}
        height={44}
        viewBox="0 0 15 22"
        style={{
          position: 'absolute',
          left: x - 3,
          top: y - 2,
          opacity,
          transform: `scale(${press ? 0.88 : 1})`,
          transformOrigin: '3px 2px',
          filter: 'drop-shadow(0 3px 6px rgba(0,0,0,0.45))',
        }}
      >
        <path d="M1.5 1.5v16.2l4-3.9 2.6 6.1 2.6-1.1-2.6-6h5.6z" fill="#111" stroke="#fff" strokeWidth={1.4} />
      </svg>
    </>
  );
};

/** A small pill of text, used for the notes over recordings. */
export const Pill: React.FC<{ children: React.ReactNode; at: number; style?: React.CSSProperties }> = ({
  children,
  at,
  style,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = spring({ frame: frame - at, fps, config: { damping: 18, stiffness: 160 } });
  return (
    <div
      style={{
        position: 'absolute',
        padding: '16px 26px',
        borderRadius: 999,
        background: 'rgba(20,23,28,0.92)',
        border: `1px solid ${color.panelEdge}`,
        boxShadow: '0 20px 60px rgba(0,0,0,0.5)',
        fontFamily: font.sans,
        fontSize: 28,
        color: color.text,
        display: 'flex',
        alignItems: 'center',
        gap: 14,
        opacity: frame >= at ? Math.min(1, t * 1.4) : 0,
        transform: `scale(${0.85 + 0.15 * t})`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};
