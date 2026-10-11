"use client";

/** The account pill in the top bar, opening the person's own settings: for now the display density (Normal, Compact, Very
 *  compact; Compact by default). The choice is a cookie the page's head reads before it paints (app/layout.tsx), so a page
 *  opens at the chosen density without a flicker; it changes spacing on screens 1024px wide and above, never the
 *  browser's zoom, and the CBT examination room, printing and the PDFs keep their own sizes. */
import { useState } from "react";

export type Density = "normal" | "compact" | "very";
const DENSITIES: { key: Density; label: string; hint: string }[] = [
  { key: "normal", label: "Normal", hint: "The spacing as it was" },
  { key: "compact", label: "Compact", hint: "More on screen (the default)" },
  { key: "very", label: "Very compact", hint: "The most on screen" },
];
/** the choice kept for a year, and applied to this page at once */
function remember(d: Density) {
  document.cookie = `moaum_density=${d}; path=/; max-age=31536000; samesite=lax`;
  document.documentElement.setAttribute("data-density", d);
}
const read = (): Density => {
  const d = typeof document === "undefined" ? null : document.documentElement.getAttribute("data-density");
  return d === "normal" || d === "very" ? d : "compact";
};

export function AccountMenu({ who, label, initials }: { who: string; label: string; initials: string }) {
  const [density, setDensity] = useState<Density>("compact");

  function choose(d: Density) {
    remember(d);
    setDensity(d);
  }

  return (
    <details className="topbar__me acct" onToggle={(e) => { if ((e.currentTarget as HTMLDetailsElement).open) setDensity(read()); }}>
      <summary title={label} aria-label={`${who}, ${label}: display settings`}>
        <div className="avatar avatar--sm">{initials}</div>
        <div className="topbar__who"><div className="topbar__name">{who}</div><div className="topbar__role">{label}</div></div>
      </summary>
      <div className="acct__menu" role="radiogroup" aria-label="Display density">
        <div className="acct__h">Display density</div>
        {DENSITIES.map((o) => (
          <label key={o.key} className={`acct__opt${density === o.key ? " is-on" : ""}`}>
            <input type="radio" name="moaum-density" value={o.key} checked={density === o.key} onChange={() => choose(o.key)} />
            <span><b>{o.label}</b><span className="sub2 blk">{o.hint}</span></span>
          </label>
        ))}
        <div className="sub2 acct__note">On screens 1024px wide and above. Your browser&rsquo;s zoom is not changed.</div>
      </div>
    </details>
  );
}
