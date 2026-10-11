import Link from "next/link";
import type { ReactNode } from "react";

/** the University's name as its website heads every page: two lines, the second the place */
export const UNIVERSITY_NAME: [string, string] = ["Rev. Fr. Moses Orshio Adasu", "University, Makurdi"];

/**
 * The University's brand, drawn once: the official crest (public/crest.png, 180×187) and its name. Every place the portal
 * names itself uses this — the side navigation and the drawer ("nav"), the bar across the top of a phone or tablet ("bar":
 * the crest and the University's name as the website heads its pages, the way home), and the plain frames a portal shows
 * before its shell is built ("plain"). The crest keeps its proportions at every size (object-fit: contain); it is never
 * redrawn, recoloured or replaced by text.
 */
export function UniversityBrand({ variant = "nav", sub, href = "/" }: { variant?: "nav" | "bar" | "plain"; sub?: ReactNode; href?: string }) {
  const crest = (cls: string) => (
    // eslint-disable-next-line @next/next/no-img-element
    <img src="/crest.png" alt="" className={cls} width={34} height={35} decoding="async" />
  );
  if (variant === "bar") {
    return (
      <Link href={href} className="ubrand ubrand--bar" aria-label={`${UNIVERSITY_NAME.join(" ")}: MOAUM Portal home`}>
        {crest("ubrand__crest")}
        <span className="ubrand__name" aria-hidden="true">
          <span className="ubrand__l1">{UNIVERSITY_NAME[0]}</span>
          <span className="ubrand__l2">{UNIVERSITY_NAME[1]}</span>
        </span>
      </Link>
    );
  }
  if (variant === "plain") {
    return (
      <span className="ubrand ubrand--plain">
        {crest("ubrand__crest")}
        <span className="ubrand__name">MOAUM Portal</span>
      </span>
    );
  }
  return (
    <div className="nav__brand ubrand">
      {crest("nav__crest")}
      <div>
        <span className="t">MOAUM Portal</span>
        {sub ? <span className="s">{sub}</span> : null}
      </div>
    </div>
  );
}
