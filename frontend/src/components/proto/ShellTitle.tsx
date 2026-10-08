"use client";

import { createContext, useContext, type ReactNode } from "react";

/** the title the Shell's top bar shows for this page — a page's own heading does not say it a second time */
export const ShellTitle = createContext<string | null>(null);

const SMALL = new Set(["the", "a", "an", "of", "and", "my", "your"]);

/** two titles that say the same thing: the same words, whatever their case, punctuation, "&" or "and", and the small words between */
export function sameTitle(a: string | null | undefined, b: string | null | undefined): boolean {
  const words = (t: string) => t.toLowerCase().replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").trim().split(/\s+/).filter((w) => w && !SMALL.has(w));
  if (!a || !b) return false;
  const x = words(a), y = words(b);
  return x.length > 0 && x.length === y.length && x.every((w, i) => w === y[i]);
}

/** the page head's body: its title, unless the top bar already says it; its description, eyebrow and actions as they are */
export function PageHeadBody({ title, description, actions, eyebrow }: { title?: ReactNode; description?: ReactNode; actions?: ReactNode; eyebrow?: ReactNode }) {
  const shell = useContext(ShellTitle);
  const showTitle = title !== undefined && title !== null && title !== "" && !(typeof title === "string" && sameTitle(title, shell));
  if (!showTitle && !description && !actions && !eyebrow) return null;
  return (
    <div className="phead">
      <div style={{ minWidth: 0 }}>
        {eyebrow ? <div className="eyebrow">{eyebrow}</div> : null}
        {showTitle ? <h2 className="phead__t">{title}</h2> : null}
        {description ? <div className="phead__d">{description}</div> : null}
      </div>
      {actions ? <div className="phead__a">{actions}</div> : null}
    </div>
  );
}
