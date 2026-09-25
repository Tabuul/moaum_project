/** vz — the prototype's data-visualisation primitives (proto _ac.html vz*), ported to React/SVG.
 *  A chart is for seeing the shape; each is meant to sit above its own table. Colours, the 2px
 *  surface gap between arcs, the recessive grid and axis, and text in text tokens rather than the
 *  series colour are all as the prototype draws them. Styling is .vz__* in styles/prototype.css. */
import type { ReactNode } from "react";

export const VZ = {
  s1: "#2a78d6", s2: "#eb6834", s3: "#1baf7a", s4: "#eda100", s5: "#e87ba4",
  good: "#0ca30c", warn: "#fab219", crit: "#d03b3b",
  seq: "#2a78d6", grid: "#E7EBEF", axis: "#8A939E",
} as const;

export const vzNum = (n: number) => Number(n || 0).toLocaleString();

export interface DonutItem { l: string; v: number; c: string; i?: ReactNode }

/* part of a whole, few slices, each directly labelled */
export function Donut({ items, capLabel, capValue, onPick }: { items: DonutItem[]; capLabel: string; capValue: string; onPick?: (item: DonutItem, index: number) => void }) {
  const total = items.reduce((a, i) => a + i.v, 0);
  const R = 62, W = 20, C = 2 * Math.PI * R;
  const fracs = items.map((i) => (total ? i.v / total : 0));
  const offsets = fracs.map((_, k) => fracs.slice(0, k).reduce((a, f) => a + f, 0) * C);
  const arcs = items.map((i, k) => {
    const frac = fracs[k];
    const len = Math.max(0, frac * C - 2);
    return (
      <circle key={k} className={`vz__arc${onPick ? " vz__arc--pick" : ""}`} cx={90} cy={90} r={R} fill="none" stroke={i.c} strokeWidth={W}
        strokeDasharray={`${len.toFixed(2)} ${(C - len).toFixed(2)}`} strokeDashoffset={(-offsets[k]).toFixed(2)} transform="rotate(-90 90 90)"
        onClick={onPick ? () => onPick(i, k) : undefined} role={onPick ? "button" : undefined} tabIndex={onPick ? 0 : undefined}
        onKeyDown={onPick ? (e) => { if (e.key === "Enter" || e.key === " ") onPick(i, k); } : undefined}>
        <title>{`${i.l}: ${vzNum(i.v)} (${Math.round(frac * 100)}%)`}</title>
      </circle>
    );
  });
  return (
    <div className="vz__donut">
      <svg viewBox="0 0 180 180" width={180} height={180} role="img" aria-label={`${capLabel}: ${items.map((i) => `${i.l} ${i.v}`).join(", ")}`}>
        <circle cx={90} cy={90} r={R} fill="none" stroke="#F1F4F6" strokeWidth={W} />
        {arcs}
        <text x={90} y={86} textAnchor="middle" className="vz__cv">{capValue}</text>
        <text x={90} y={104} textAnchor="middle" className="vz__cl">{capLabel}</text>
      </svg>
      <div className="vz__key">
        {items.map((i, k) => {
          const pct = total ? Math.round((i.v / total) * 100) : 0;
          return (
            <div className="vz__ki" key={k}>
              {i.i || null}
              <span className="vz__sw" style={{ background: i.c }} />
              <span className="vz__kl">{i.l}</span>
              <b className="tnum">{vzNum(i.v)}</b>
              <span className="vz__kp tnum">{pct}%</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export interface BarItem { l: string; v: number }

/* horizontal bars, one series */
export function HBars({ items, colour, onPick }: { items: BarItem[]; colour?: string; onPick?: (item: BarItem, index: number) => void }) {
  const max = items.reduce((a, i) => Math.max(a, i.v), 0) || 1;
  return (
    <div className="vz__hb">
      {items.map((i, k) => (
        <div className={`vz__hr${onPick ? " vz__hr--pick" : ""}`} key={k} title={`${i.l}: ${vzNum(i.v)}`} onClick={onPick ? () => onPick(i, k) : undefined}
          role={onPick ? "button" : undefined} tabIndex={onPick ? 0 : undefined} onKeyDown={onPick ? (e) => { if (e.key === "Enter" || e.key === " ") onPick(i, k); } : undefined}>
          <span className="vz__hl">{i.l}</span>
          <span className="vz__ht"><span className="vz__hf" style={{ width: `${((i.v / max) * 100).toFixed(1)}%`, background: colour || VZ.seq }} /></span>
          <b className="vz__hv tnum">{vzNum(i.v)}</b>
        </div>
      ))}
    </div>
  );
}

export interface LegendKey { l: string; c: string; i?: ReactNode }

export function Legend({ keys }: { keys: LegendKey[] }) {
  return (
    <div className="vz__leg">
      {keys.map((k, i) => (
        <span className="vz__li" key={i}>{k.i || null}<span className="vz__sw" style={{ background: k.c }} />{k.l}</span>
      ))}
    </div>
  );
}

/* stacked horizontal bars; the bold figure is the first part (here, the good one) */
export function Stack({ rows, keys }: { rows: { l: string; parts: number[] }[]; keys: LegendKey[] }) {
  const max = rows.reduce((a, r) => Math.max(a, r.parts.reduce((b, p) => b + p, 0)), 0) || 1;
  return (
    <>
      <div className="vz__hb">
        {rows.map((r, k) => {
          const tot = r.parts.reduce((a, p) => a + p, 0);
          return (
            <div className="vz__hr" key={k}>
              <span className="vz__hl">{r.l}</span>
              <span className="vz__ht" style={{ width: `${((tot / max) * 100).toFixed(1)}%` }}>
                {r.parts.map((p, i) => (
                  <span className="vz__seg" key={i} style={{ flex: `${p} 1 0`, background: keys[i].c }} title={`${keys[i].l}: ${vzNum(p)}`} />
                ))}
              </span>
              <b className="vz__hv tnum">{vzNum(r.parts[0])}</b>
            </div>
          );
        })}
      </div>
      <Legend keys={keys} />
    </>
  );
}

export interface Series { l: string; v: number[]; c: string }

/* line chart, cumulative, two series */
export function Line({ series, xs, yMax, yLabel }: { series: Series[]; xs: string[]; yMax: number; yLabel: string }) {
  const W = 660, H = 236, L = 52, R = 118, T = 14, B = 44;
  const pw = W - L - R, ph = H - T - B;
  const x = (i: number) => L + (xs.length < 2 ? 0 : (i / (xs.length - 1)) * pw);
  const y = (v: number) => T + ph - (v / (yMax || 1)) * ph;
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f, k) => {
    const v = Math.round((yMax || 1) * f);
    return (
      <g key={k}>
        <line x1={L} y1={y(v)} x2={L + pw} y2={y(v)} stroke={VZ.grid} strokeWidth={1} />
        <text x={L - 8} y={y(v) + 4} textAnchor="end" className="vz__ax">{vzNum(v)}</text>
      </g>
    );
  });
  return (
    <svg className="vz__svg" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={yLabel}>
      {ticks}
      <line x1={L} y1={T + ph} x2={L + pw} y2={T + ph} stroke={VZ.axis} strokeWidth={1} />
      {xs.map((t, i) => <text key={i} x={x(i)} y={T + ph + 20} textAnchor="middle" className="vz__ax">{t}</text>)}
      {series.map((s, si) => {
        const pts = s.v.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(" ");
        const last = s.v.length - 1;
        return (
          <g key={si}>
            <polyline points={pts} fill="none" stroke={s.c} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
            {s.v.map((v, i) => (
              <circle key={i} cx={x(i).toFixed(1)} cy={y(v).toFixed(1)} r={4} fill={s.c} stroke="#fff" strokeWidth={2}>
                <title>{`${s.l}, ${xs[i]}: ${vzNum(v)}`}</title>
              </circle>
            ))}
            {last >= 0 ? <text x={x(last) + 10} y={y(s.v[last]) + 4} className="vz__end" fill={s.c}>{`${s.l} ${vzNum(s.v[last])}`}</text> : null}
          </g>
        );
      })}
    </svg>
  );
}

export interface VBarItem { l: string; v: number; c: string }

/* vertical bars, ordered categories; v is a percentage */
export function VBars({ items }: { items: VBarItem[] }) {
  const max = items.reduce((a, i) => Math.max(a, i.v), 0) || 1;
  return (
    <div className="vz__vb">
      {items.map((i, k) => (
        <div className="vz__vc" key={k} title={`${i.l}: ${i.v}%`}>
          <b className="vz__vv tnum">{i.v}%</b>
          <span className="vz__vt"><span className="vz__vf" style={{ height: `${((i.v / max) * 100).toFixed(1)}%`, background: i.c }} /></span>
          <span className="vz__vl">{i.l}</span>
        </div>
      ))}
    </div>
  );
}

export interface GroupRow { l: string; v: number[]; key?: string }

/* grouped horizontal bars: one label, several series side by side (total, paid, registered…); the row is a door
   to its rows when a pick handler is given, and the chart scrolls rather than crushing its labels */
export function GroupBars({ rows, keys, onPick }: { rows: GroupRow[]; keys: LegendKey[]; onPick?: (row: GroupRow, index: number) => void }) {
  const max = rows.reduce((a, r) => Math.max(a, ...r.v), 0) || 1;
  return (
    <>
      <div className="vz__gb">
        {rows.map((r, k) => (
          <div className={`vz__gr${onPick ? " vz__hr--pick" : ""}`} key={r.key ?? k} onClick={onPick ? () => onPick(r, k) : undefined}
            role={onPick ? "button" : undefined} tabIndex={onPick ? 0 : undefined} onKeyDown={onPick ? (e) => { if (e.key === "Enter" || e.key === " ") onPick(r, k); } : undefined}>
            <span className="vz__hl" title={r.l}>{r.l}</span>
            <span className="vz__gt">
              {r.v.map((v, i) => (
                <span className="vz__gl" key={i} title={`${keys[i]?.l ?? ""}: ${vzNum(v)}`}>
                  <span className="vz__gf" style={{ width: `${((v / max) * 100).toFixed(1)}%`, background: keys[i]?.c ?? VZ.seq }} />
                  <b className="vz__gv tnum">{vzNum(v)}</b>
                </span>
              ))}
            </span>
          </div>
        ))}
      </div>
      <Legend keys={keys} />
    </>
  );
}
