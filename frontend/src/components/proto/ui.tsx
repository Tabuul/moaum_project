/**
 * The prototype's building blocks (proto/part7.html, part2.html), as React
 * components that emit exactly the markup the prototype emits, so that the
 * prototype's stylesheet styles them identically. Names are the prototype's
 * names: note, btn, pil, two, tiles, panel, pbody, dtable, kvGrid, ico.
 */
import type { CSSProperties, MouseEvent, ReactNode } from "react";
import Link from "next/link";
import { roleLabel } from "@/lib/offices";

const I: Record<string, string> = {
  home: '<path d="M4 10.5 12 4l8 6.5V19a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 19v-8.5Z"/>',
  book: '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 9h8M8 13h8M8 17h4"/>',
  card: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18M7 15h4"/>',
  cap: '<path d="M12 3 2 8l10 5 10-5-10-5Z"/><path d="M6 10.5V16c0 1.7 2.7 3 6 3s6-1.3 6-3v-5.5"/>',
  doc: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z"/><path d="M14 3v5h5"/>',
  user: '<circle cx="12" cy="8" r="3.6"/><path d="M4.5 20c0-4 3.4-6.5 7.5-6.5s7.5 2.5 7.5 6.5"/>',
  check: '<path d="M4 12.5 9.5 18 20 6.5"/>',
  swap: '<path d="M4 8h13l-3-3M20 16H7l3 3"/>',
  chart: '<path d="M4 19V9M10 19V5M16 19v-7M22 19H2"/>',
  alert: '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5.5l3.5 2"/>',
  print: '<path d="M7 9V4h10v5M7 18H5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-2M7 15h10v6H7z"/>',
  cal: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  upload: '<path d="M12 16V4M6 10l6-6 6 6M4 20h16"/>',
  bell: '<path d="M18 15V10a6 6 0 1 0-12 0v5l-2 3h16l-2-3Z"/><path d="M10 21h4"/>',
  bed: '<path d="M3 19v-9h13a4 4 0 0 1 4 4v5M3 14h17M3 10V7"/>',
  heart: '<path d="M12 20s-7-4.6-7-9.5A3.9 3.9 0 0 1 12 8a3.9 3.9 0 0 1 7 2.5C19 15.4 12 20 12 20Z"/>',
  life: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3.6"/><path d="m5.6 5.6 3.9 3.9M14.5 14.5l3.9 3.9M18.4 5.6l-3.9 3.9M9.5 14.5l-3.9 3.9"/>',
  box: '<path d="M3 8.5 12 4l9 4.5v7L12 20l-9-4.5v-7Z"/><path d="m3 8.5 9 4.5 9-4.5M12 13v7"/>',
  flask: '<path d="M9 3h6M10.5 3v6L5 19a1.6 1.6 0 0 0 1.4 2.4h11.2A1.6 1.6 0 0 0 19 19l-5.5-10V3"/>',
  shield: '<path d="M12 3 4 6v6c0 5 3.4 8.3 8 9.3 4.6-1 8-4.3 8-9.3V6l-8-3Z"/>',
  server: '<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01"/>',
  scale: '<path d="M12 4v16M7 20h10M6 8h12M6 8l-3 6h6l-3-6Zm12 0-3 6h6l-3-6Z"/>',
  eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>',
  edit: '<path d="M4 20h4L18.5 9.5a2 2 0 0 0 0-2.8l-1.2-1.2a2 2 0 0 0-2.8 0L4 16v4Z"/><path d="M13.5 6.5l4 4"/>',
  trash: '<path d="M4 7h16M9 7V4.5A1.5 1.5 0 0 1 10.5 3h3A1.5 1.5 0 0 1 15 4.5V7M6.5 7l.8 12.1A1.5 1.5 0 0 0 8.8 20.5h6.4a1.5 1.5 0 0 0 1.5-1.4L17.5 7"/><path d="M10 11v5.5M14 11v5.5"/>',
  eyeoff: '<path d="M9.9 4.24A10.7 10.7 0 0 1 12 4c6.5 0 10 7 10 7a18.6 18.6 0 0 1-2.2 3M6.5 6.6A18.5 18.5 0 0 0 2 12s3.5 7 10 7a10.6 10.6 0 0 0 4.4-.9"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2M3 3l18 18"/>',
};

export function Ico({ name, size = 17, stroke = "currentColor", w = 1.9 }: { name: string; size?: number; stroke?: string; w?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke={stroke}
      strokeWidth={w}
      strokeLinecap="round"
      strokeLinejoin="round"
      dangerouslySetInnerHTML={{ __html: I[name] ?? I.doc }}
    />
  );
}

export function Tick({ size, colour }: { size: number; colour: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={colour} strokeWidth={3.3} strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 12.5 9.5 18 20 6.5" />
    </svg>
  );
}

export function WarnIcon({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="var(--red-ink)" strokeWidth={2.2}>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7.5v5" strokeLinecap="round" />
      <circle cx="12" cy="16.2" r=".8" fill="var(--red-ink)" />
    </svg>
  );
}

export type NoteKind = "info" | "ok" | "bad";

/** the in-content page head: a title, a line of context, and the page's primary actions on the right */
export function PageHead({ title, description, actions, eyebrow }: { title: ReactNode; description?: ReactNode; actions?: ReactNode; eyebrow?: ReactNode }) {
  return (
    <div className="phead">
      <div style={{ minWidth: 0 }}>
        {eyebrow ? <div className="eyebrow">{eyebrow}</div> : null}
        <h2 className="phead__t">{title}</h2>
        {description ? <div className="phead__d">{description}</div> : null}
      </div>
      {actions ? <div className="phead__a">{actions}</div> : null}
    </div>
  );
}

/** one tab strip for the whole portal: segmented by default, or a line of underlined tabs; the count is optional */
export function Tabs<T extends string>({ items, value, onChange, look = "segmented", label }: {
  items: { id: T; label: ReactNode; count?: ReactNode; disabled?: boolean }[]; value: T; onChange: (id: T) => void; look?: "segmented" | "line"; label?: string;
}) {
  return (
    <div role="tablist" aria-label={label} className={`tabs${look === "line" ? " tabs--line" : ""}`}>
      {items.map((t) => (
        <button key={t.id} type="button" role="tab" className="tabs__t" aria-selected={t.id === value} disabled={t.disabled} onClick={() => onChange(t.id)}>
          {t.label}{t.count != null ? <span className="tabs__n">{t.count}</span> : null}
        </button>
      ))}
    </div>
  );
}

/** note(kind, title, text, action) */
export function Note({ kind, title, children, action }: { kind: NoteKind; title: ReactNode; children?: ReactNode; action?: ReactNode }) {
  const icon = kind === "bad" ? <WarnIcon size={19} /> : kind === "ok" ? <Tick size={19} colour="var(--green-ink)" /> : <Ico name="alert" size={18} stroke="var(--chrome)" w={2} />;
  return (
    <div className={`notice notice--${kind}`}>
      {icon}
      <div style={{ minWidth: 0 }}>
        <div className="notice__t">{title}</div>
        <p>{children}</p>
        {action ? <div className="notice__a">{action}</div> : null}
      </div>
    </div>
  );
}

/** the button hierarchy: primary (the one act), secondary (tinted), ghost (outline), go (a completing act), urgent (a destructive one) */
export type BtnKind = "primary" | "secondary" | "ghost" | "go" | "urgent";
export type BtnSize = "sm" | "md";

/** btn(kind, label, attrs) — small by default, as the desk screens use it; md for a form's or a page's main act */
export function Btn({
  kind,
  size = "sm",
  children,
  onClick,
  disabled,
  title,
  type = "button",
  style,
}: {
  kind: BtnKind;
  size?: BtnSize;
  children: ReactNode;
  onClick?: (e: MouseEvent<HTMLButtonElement>) => void;
  disabled?: boolean;
  title?: string;
  type?: "button" | "submit";
  style?: CSSProperties;
}) {
  return (
    <button type={type} className={`btn btn--${kind} btn--${size}`} onClick={onClick} disabled={disabled} title={title} style={style}>
      {children}
    </button>
  );
}

/** a link that looks like a button — the same hierarchy and sizes, for a route rather than an act */
export function LinkBtn({ kind = "ghost", size = "sm", href, children, title, prefetch }: {
  kind?: BtnKind; size?: BtnSize; href: string; children: ReactNode; title?: string; prefetch?: boolean;
}) {
  return (
    <Link href={href} className={`btn btn--${kind} btn--${size}`} title={title} prefetch={prefetch}>
      {children}
    </Link>
  );
}


/**
 * An icon-only action button — Edit (pencil), View (eye), Delete (trash) and the
 * like. The label is always given: it shows as the hover tooltip and is read by
 * assistive tech, so the control is professional and compact without losing its
 * meaning. {@code danger} tints a destructive action.
 */
export function IcoBtn({
  icon,
  label,
  kind = "ghost",
  onClick,
  disabled,
  danger,
}: {
  icon: string;
  label: string;
  kind?: BtnKind;
  onClick?: () => void;
  disabled?: boolean;
  danger?: boolean;
}) {
  return (
    <button
      type="button"
      className={`btn btn--${kind} btn--sm btn--icon${danger ? " is-danger" : ""}`}
      title={label}
      aria-label={label}
      onClick={onClick}
      disabled={disabled}
    >
      <Ico name={icon} size={16} />
      <span className="sr-only">{label}</span>
    </button>
  );
}

/**
 * Who works this desk, stated plainly. Names the office(s) that may act, and
 * tells the person signed in whether they can act or are viewing only — so the
 * role is never a mystery behind a greyed-out button.
 */
export function RoleLine({
  allowed,
  actingOffice,
  action,
  canAct,
}: {
  allowed: string[];
  actingOffice: string | null;
  action?: string;
  canAct?: boolean;
}) {
  const names = allowed.map((o) => roleLabel(o)).join(", ");
  const can = canAct ?? allowed.includes(actingOffice ?? "");
  return (
    <div
      style={{
        display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap",
        padding: "9px 13px", border: "1px solid var(--line)", borderRadius: 8,
        background: "var(--bg)", marginBottom: 12,
      }}
    >
      <Ico name={can ? "check" : "eye"} size={16} stroke={can ? "var(--green-ink)" : "var(--muted)"} />
      <span className="sub2">
        <strong style={{ color: "var(--ink)" }}>{action ?? "These actions"}</strong> {allowed.length === 1 ? "is worked by the " : "are worked by the "}{names}.
      </span>
      <span className="grow" />
      <Pil kind={can ? "ok" : "grey"}>
        {can ? `You may act — ${roleLabel(actingOffice)}` : `Signed in as ${roleLabel(actingOffice)} · view only`}
      </Pil>
    </div>
  );
}

/** pil(kind, text) */
export function Pil({ kind, children }: { kind: "grey" | "info" | "ok" | "bad" | "warn"; children: ReactNode }) {
  return <span className={`pill pill--${kind}`}>{children}</span>;
}

/** two(a, b) */
export function Two({ a, b }: { a: ReactNode; b: ReactNode }) {
  return (
    <>
      <strong>{a}</strong>
      <div className="sub2">{b}</div>
    </>
  );
}

/** tiles([[label, value, colour?, caption?]], cls) */
export function Tiles({ items, cls = "grid--4" }: { items: [ReactNode, ReactNode, string | null | undefined, ReactNode?, string?][]; cls?: string }) {
  return (
    <div className={`grid ${cls}`}>
      {items.map((t, i) => {
        /* a long string value (a matriculation/identifier, not a number) shrinks so it fits the tile
           on one line instead of wrapping at the big 29px KPI size; numbers stay large */
        const v = t[1];
        const len = typeof v === "string" ? v.length : 0;
        const nStyle: React.CSSProperties = {};
        if (t[2]) nStyle.color = t[2];
        if (len > 22) nStyle.fontSize = 13;
        else if (len > 16) nStyle.fontSize = 15;
        else if (len > 12) nStyle.fontSize = 18;
        const inner = (
          <>
            <span className="eyebrow">{t[0]}</span>
            <span className="n tnum" style={Object.keys(nStyle).length ? nStyle : undefined}>{v}</span>
            {t[3] ? <span className="c">{t[3]}</span> : null}
          </>
        );
        return t[4]
          ? <Link className="tile" key={i} href={t[4]} style={{ textDecoration: "none", color: "inherit", cursor: "pointer" }}>{inner}</Link>
          : <div className="tile" key={i}>{inner}</div>;
      })}
    </div>
  );
}

/** panel(title, right, inner) */
export function Panel({ title, right, children }: { title: ReactNode; right?: ReactNode; children: ReactNode }) {
  return (
    <div className="card">
      <div className="card__head">
        <span className="card__title">{title}</span>
        {right ? (
          <span className="sub2 ml-auto">
            {right}
          </span>
        ) : null}
      </div>
      {children}
    </div>
  );
}

/** pbody(inner, style) */
export function PBody({ children, style }: { children: ReactNode; style?: CSSProperties }) {
  return (
    <div className="card__body" style={style}>
      {children}
    </div>
  );
}

/** kvGrid(pairs, cls) */
export function KvGrid({ pairs, cls = "grid--4" }: { pairs: [ReactNode, ReactNode][]; cls?: string }) {
  return (
    <div className={`grid ${cls}`}>
      {pairs.map((p, i) => (
        <div className="kv" key={i}>
          <span className="k">{p[0]}</span>
          <span className="v">{p[1]}</span>
        </div>
      ))}
    </div>
  );
}
