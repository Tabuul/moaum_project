/**
 * The sign-in pages' layout — sign in, password reset, the first account, the applications — drawn as the University's
 * CMS sign-in is (cms.moaum.edu.ng): the navy brand card with the crest turning in its orbits, and the page's own content
 * on white beside it. A page gives the card its paragraph and figures, and the panel its context line; its own heading and
 * form go in the panel as they are, and take the CMS's look from here.
 */
import type { ReactNode } from "react";
import css from "./AuthLayout.module.css";

function Shield() {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" />
      <path d="m9 12 2 2 4-4" />
    </svg>
  );
}

export function AuthLayout({ lead, stats, eyebrow, wide = false, bare = false, children }: {
  /** the card's paragraph under "MOAUM Portal" */
  lead?: ReactNode;
  /** the page's figures on the card: [figure, what it counts] */
  stats?: [ReactNode, ReactNode][];
  /** the panel's context line above the page's heading (Admissions 2026/2027, Account recovery, …) */
  eyebrow?: ReactNode;
  /** a long form (an application) is given a wider panel */
  wide?: boolean;
  /** the page draws its own panel (the sign-in form) */
  bare?: boolean;
  children: ReactNode;
}) {
  return (
    <main className={css.page}>
      <aside className={css.aside}>
        <div className={css.card}>
          <div className={css.cardBg} aria-hidden="true" />
          <div className={css.cardDots} aria-hidden="true" />
          <div className={css.blobCrimson} aria-hidden="true" />
          <div className={css.blobAmber} aria-hidden="true" />
          <div className={css.sheen} aria-hidden="true" />

          <div className={css.brand}>
            <div className={css.crestBox}>
              <span className={css.ringA} aria-hidden="true" />
              <span className={css.ring} aria-hidden="true" />
              <span className={css.ringB} aria-hidden="true" />
              <span className={css.ripple} aria-hidden="true" />
              <span className={css.ripple2} aria-hidden="true" />
              <div className={css.scene}>
                <div className={css.halo}>
                  <div className={css.coin}>
                    <div className={css.face}>
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src="/crest.png" alt="Crest of Rev. Fr. Moses Orshio Adasu University, Makurdi" />
                    </div>
                    <div className={`${css.face} ${css.faceBack}`} aria-hidden="true">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src="/crest.png" alt="" />
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <div className={css.titleBlock}>
              <p className={css.uni}>Rev. Fr. Moses Orshio Adasu University, Makurdi</p>
              <h1 className={css.title}>MOAUM Portal<span className={css.titleDot} aria-hidden="true" /></h1>
              <span className={css.bar} aria-hidden="true" />
              {lead ? <p className={css.lead}>{lead}</p> : null}
              {stats && stats.length ? (
                <div className={css.stats}>
                  {stats.map(([n, l], i) => <div className={css.stat} key={i}><b>{n}</b><span>{l}</span></div>)}
                </div>
              ) : null}
            </div>
          </div>

          <p className={css.motto}>
            <span>Scientia Liberatio Populorum</span>
            <span>Knowledge for the liberation of the people</span>
          </p>
        </div>
      </aside>

      <section className={css.main}>
        <div className={css.mainLines} aria-hidden="true">
          <svg viewBox="0 0 1600 400" preserveAspectRatio="xMidYMid slice" fill="none">
            <defs>
              <linearGradient id="auth-a" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#0f172a" stopOpacity="0.055" /><stop offset="1" stopColor="#0f172a" stopOpacity="0.005" /></linearGradient>
              <linearGradient id="auth-b" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#0284c7" stopOpacity="0.06" /><stop offset="1" stopColor="#0284c7" stopOpacity="0.005" /></linearGradient>
            </defs>
            <polygon points="-80,-40 520,-80 300,300" fill="url(#auth-a)" />
            <polygon points="300,300 520,-80 780,180" fill="url(#auth-b)" stroke="#94a3b8" strokeWidth="1" opacity="0.22" vectorEffect="non-scaling-stroke" />
            <polygon points="1060,-60 1700,-20 1700,330 1320,420" fill="url(#auth-b)" />
            <polygon points="1320,420 1700,330 1700,430" fill="url(#auth-a)" stroke="#94a3b8" strokeWidth="1" opacity="0.22" vectorEffect="non-scaling-stroke" />
            <path d="M0 250 L1600 120" stroke="#0f172a" strokeWidth="1" opacity="0.035" vectorEffect="non-scaling-stroke" />
          </svg>
        </div>
        <div className={css.mainDots} aria-hidden="true" />
        {bare ? children : (
          <div className={`${css.panel}${wide ? ` ${css.panelWide}` : ""}`}>
            {eyebrow ? <p className={css.panelEyebrow}><Shield />{eyebrow}</p> : null}
            {children}
          </div>
        )}
      </section>
    </main>
  );
}
