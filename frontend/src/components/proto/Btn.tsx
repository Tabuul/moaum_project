"use client";

/**
 * The portal's buttons (re-exported from ./ui as Btn and IcoBtn), aware of the act they start. The moment a click sends a
 * request (lib/activity ties it to the button), or the click handler returns a promise, the button shows that the act is
 * under way: a spinner, the act's own word ("Save changes" reads "Saving…", "Approve" "Approving…", "Sign out" "Signing
 * out…"), aria-busy, and disabled, so a second click cannot send it twice. Nothing is timed: the state is the request's
 * own, and the button is itself again the moment the server answers or the request fails (the screen's notice says which).
 * A screen that holds its own state may say so with `busy` (and `busyLabel`). The width the button had is kept, so a
 * shorter word does not shift the layout.
 */
import { Children, useEffect, useRef, useState, useSyncExternalStore, type CSSProperties, type MouseEvent, type ReactNode } from "react";
import { installActivity, isBusy, subscribe } from "@/lib/activity";
import { doingWord } from "@/lib/act-words";

/** the button hierarchy: primary (the one act), secondary (tinted), ghost (outline), go (a completing act), urgent (a destructive one) */
export type BtnKind = "primary" | "secondary" | "ghost" | "go" | "urgent";
export type BtnSize = "sm" | "md";

/** the button's own words while its act runs (lib/act-words): "Sign out" → "Signing out…", "Save changes" → "Saving…";
 *  null when the label is not plain words, or its first word is not an act the list knows (the label then stays, beside
 *  the spinner) */
export function doingLabel(children: ReactNode): string | null {
  const parts = Children.toArray(children);
  if (!parts.length || parts.some((p) => typeof p !== "string" && typeof p !== "number")) return null;
  return doingWord(parts.join(""));
}

export function Spinner() {
  return (
    <svg className="btn__spin" width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity=".25" strokeWidth="3" />
      <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

/** the act's state for one button: a request its click sent still in flight (lib/activity), or the promise its handler
 *  returned not yet settled; `run` is the button's click */
function useAct(onClick: ((e: MouseEvent<HTMLButtonElement>) => unknown) | undefined) {
  const ref = useRef<HTMLButtonElement>(null);
  const [pending, setPending] = useState(false);
  const alive = useRef(true);
  const [width, setWidth] = useState<number | null>(null);
  useEffect(() => {
    alive.current = true;
    installActivity();
    return () => { alive.current = false; };
  }, []);
  const sent = useSyncExternalStore(subscribe, () => isBusy(ref.current), () => false);
  // the act under way is known at once, not only once the button is drawn again: a second click in the same moment (or
  // the second submission it would cause) is refused here
  const running = useRef(false);
  function run(e: MouseEvent<HTMLButtonElement>) {
    if (running.current || isBusy(e.currentTarget)) {
      e.preventDefault();
      return;
    }
    setWidth(e.currentTarget.offsetWidth || null);
    if (!onClick) return;
    const r = onClick(e);
    if (r && typeof (r as PromiseLike<unknown>).then === "function") {
      running.current = true;
      setPending(true);
      const done = () => {
        running.current = false;
        if (alive.current) setPending(false);
      };
      Promise.resolve(r).then(done, done);
    }
  }
  return { ref, on: pending || sent, run, width };
}

/** btn(kind, label, attrs) — small by default, as the desk screens use it; md for a form's or a page's main act */
export function Btn({
  kind,
  size = "sm",
  children,
  onClick,
  disabled,
  busy,
  busyLabel,
  title,
  type = "button",
  style,
  className,
  "aria-label": ariaLabel,
}: {
  kind: BtnKind;
  size?: BtnSize;
  children: ReactNode;
  /** a handler that returns a promise holds the button busy until it settles (a request it sends does so already) */
  onClick?: (e: MouseEvent<HTMLButtonElement>) => unknown;
  disabled?: boolean;
  /** the screen's own word that this button's act is under way */
  busy?: boolean;
  /** what the button reads while busy, where its first word does not say it */
  busyLabel?: string;
  title?: string;
  type?: "button" | "submit";
  style?: CSSProperties;
  className?: string;
  "aria-label"?: string;
}) {
  const { ref, on: sending, run, width } = useAct(onClick);
  const on = sending || !!busy;
  const doing = on ? (busyLabel ?? doingLabel(children)) : null;
  const held = on && width ? { ...style, minWidth: width } : style;
  return (
    <button
      ref={ref}
      data-act=""
      type={type}
      className={`btn btn--${kind} btn--${size}${on ? " is-busy" : ""}${className ? " " + className : ""}`}
      onClick={run}
      disabled={disabled || on}
      aria-busy={on || undefined}
      title={title}
      style={held}
      aria-label={on && ariaLabel ? `${ariaLabel} — under way, please wait` : ariaLabel}
    >
      {on ? <Spinner /> : null}
      {on && doing ? doing : children}
      {on && !ariaLabel ? <span className="sr-only"> — under way, please wait</span> : null}
    </button>
  );
}

/**
 * An icon-only action button — Edit (pencil), View (eye), Delete (trash) and the
 * like. The label is always given: it shows as the hover tooltip and is read by
 * assistive tech, so the control is professional and compact without losing its
 * meaning. {@code danger} tints a destructive action. While its act is under way
 * the spinner takes the icon's place.
 */
export function IcoBtn({
  icon,
  label,
  kind = "ghost",
  onClick,
  disabled,
  danger,
}: {
  /** the icon (./ui passes its Ico) */
  icon: ReactNode;
  label: string;
  kind?: BtnKind;
  onClick?: () => unknown;
  disabled?: boolean;
  danger?: boolean;
}) {
  const { ref, on, run } = useAct(onClick ? () => onClick() : undefined);
  return (
    <button
      ref={ref}
      data-act=""
      type="button"
      className={`btn btn--${kind} btn--sm btn--icon${danger ? " is-danger" : ""}${on ? " is-busy" : ""}`}
      title={label}
      aria-label={on ? `${label} — under way, please wait` : label}
      aria-busy={on || undefined}
      onClick={run}
      disabled={disabled || on}
    >
      {on ? <Spinner /> : icon}
      <span className="sr-only">{label}</span>
    </button>
  );
}
