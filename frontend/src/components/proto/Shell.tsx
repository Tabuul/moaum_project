"use client";

/**
 * The prototype's shell (proto/part6.html renderBase and navHTML): the
 * navigation with the crest, the "Signed in as" select, the folded groups
 * with their counts, the collapse control and the foot; the topbar with the
 * menu button, the screen's title and the search; and the content area.
 * Same classes, same structure. The Academic Office's menu is the
 * prototype's (proto/part17.html); items the portal does not yet serve are
 * the same buttons, and say so when pressed.
 */
import { useState, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Ico } from "./ui";
import { OFFICE_COOKIE, roleLabel, roleUnit } from "@/lib/offices";

interface NavItem {
  id: string;
  icon: string;
  label: string;
  badge?: string;
}
interface NavGroup {
  name: string;
  items: NavItem[];
}

/* the Academic Office, as the prototype lays it out */
const GROUPS: NavGroup[] = [
  { name: "Records", items: [
    { id: "t/search", icon: "user", label: "Search" },
    { id: "r/academic", icon: "home", label: "Dashboard" },
    { id: "t/records", icon: "chart", label: "Records & queries" },
    { id: "t/students", icon: "cap", label: "Student records" },
    { id: "t/biochange", icon: "user", label: "Biodata changes", badge: "4" },
    { id: "r/classlist", icon: "user", label: "Registered students" },
    { id: "t/admissions", icon: "doc", label: "Admissions" },
    { id: "t/admissionsetup", icon: "doc", label: "Admission settings", badge: "!" },
    { id: "t/capsintake", icon: "box", label: "JAMB admission lists", badge: "6" },
    { id: "t/candidatedata", icon: "user", label: "Passports, DOB & O’Level" },
    { id: "t/matriculation", icon: "cap", label: "Matriculation", badge: "!" },
    { id: "t/college", icon: "swap", label: "College of Health Sciences" },
  ]},
  { name: "Calendar", items: [
    { id: "t/session", icon: "cal", label: "Session & semester setup" },
    { id: "t/examsession", icon: "cal", label: "Examination sessions" },
  ]},
  { name: "Credentials", items: [
    { id: "t/clearance", icon: "check", label: "Clearance", badge: "54" },
    { id: "t/transcripts", icon: "doc", label: "Transcripts", badge: "9" },
    { id: "t/certificates", icon: "cap", label: "Certificates" },
    { id: "t/graduation", icon: "cap", label: "Graduation" },
  ]},
  { name: "Senate business", items: [
    { id: "t/approvals", icon: "check", label: "Results to Senate" },
    { id: "t/chain", icon: "doc", label: "Approval chain" },
  ]},
  { name: "Me", items: [{ id: "r/self", icon: "user", label: "Leave & payslip" }] },
];

/* the screens the portal serves so far; every other item is still the prototype's */
const ROUTES: Record<string, string> = {
  "r/academic": "/",
  "t/capsintake": "/admissions/caps",
  "t/admissionsetup": "/admissions/settings",
};

/* the topbar titles (proto/part2.html TITLES) */
export const TITLES: Record<string, [string, string]> = {
  "r/academic": ["Academic Affairs", "Registration, credentials and Senate business"],
  "t/capsintake": ["JAMB admission lists", "UTME and Direct Entry · downloaded from CAPS, reconciled both ways"],
  "t/admissionsetup": ["Admission settings", "The Central Admissions Committee’s guidelines, made into settings the portal applies"],
};

export interface Me {
  actorId: string;
  activeOffice: string | null;
  offices: string[];
}

function navWaiting(g: NavGroup): number {
  let n = 0;
  for (const it of g.items) {
    if (!it.badge) continue;
    n += /^\d+$/.test(it.badge) ? parseInt(it.badge, 10) : 1;
  }
  return n;
}

function initials(label: string): string {
  const w = label.replace(/[()]/g, "").split(/\s+/).filter(Boolean);
  return ((w[0]?.[0] ?? "") + (w[1]?.[0] ?? "")).toUpperCase() || "MP";
}

export function Shell({ route, me, children }: { route: string; me: Me | null; children: ReactNode }) {
  const router = useRouter();
  const [navOpen, setNavOpen] = useState(false);
  const [navSlim, setNavSlim] = useState(false);
  const [navg, setNavg] = useState<Record<string, boolean>>({});
  const [said, setSaid] = useState<string | null>(null);
  const [t0, t1] = TITLES[route] ?? ["", ""];
  const office = me?.activeOffice ?? null;
  const label = roleLabel(office);

  const isOpen = (g: NavGroup) => {
    if (Object.prototype.hasOwnProperty.call(navg, g.name)) return !!navg[g.name];
    return g.items.some((it) => it.id === route);
  };

  function chooseOffice(code: string) {
    document.cookie = `${OFFICE_COOKIE}=${encodeURIComponent(code)}; path=/; max-age=31536000; samesite=lax`;
    router.refresh();
  }

  const slimBtn = (
    <div style={{ padding: "6px 10px 0" }}>
      <button
        className="nav__slim"
        aria-label={navSlim ? "Expand the menu" : "Collapse the menu"}
        title={navSlim ? "Expand the menu" : "Collapse the menu"}
        onClick={() => {
          setNavSlim(!navSlim);
          document.body.classList.toggle("nav-slim", !navSlim);
        }}
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M15 6l-6 6 6 6" />
        </svg>
      </button>
    </div>
  );

  return (
    <>
      {navOpen && <div className="scrim" onClick={() => { setNavOpen(false); document.body.classList.remove("nav-open"); }} />}
      <div className="shell">
        <nav className="nav" aria-label="Main">
          <div className="nav__brand">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/crest.png" alt="" style={{ width: 34, height: 35, objectFit: "contain", flexShrink: 0 }} />
            <div>
              <span className="t">MOAUM Portal</span>
              <span className="s">{label}</span>
            </div>
          </div>

          <div className="ws">
            <label htmlFor="office">Signed in as</label>
            <select id="office" className="ws__select" value={office ?? ""} onChange={(e) => chooseOffice(e.target.value)}>
              {(me?.offices ?? []).map((o) => (
                <option key={o} value={o}>
                  {roleLabel(o)}
                </option>
              ))}
              {!office && <option value="">No office</option>}
            </select>
          </div>

          <div style={{ overflowY: "auto", flexGrow: 1, paddingBottom: 8 }}>
            {GROUPS.map((g) => {
              const open = isOpen(g);
              const waiting = navWaiting(g);
              return (
                <div key={g.name}>
                  <button className="nav__gh" aria-expanded={open ? "true" : "false"} onClick={() => setNavg({ ...navg, [g.name]: !open })}>
                    <span className="gname">{g.name}</span>
                    {!open && waiting ? <span className="gcount">{waiting}</span> : null}
                    <svg className="gchev" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M5 9l7 7 7-7" />
                    </svg>
                  </button>
                  {open && (
                    <div className="nav__list">
                      {g.items.map((it) => {
                        const inner = (
                          <>
                            <Ico name={it.icon} size={17} />
                            <span>{it.label}</span>
                            {it.badge ? <span className="nav__badge">{it.badge}</span> : null}
                          </>
                        );
                        const current = route === it.id ? "page" : undefined;
                        return ROUTES[it.id] ? (
                          <Link key={it.id} href={ROUTES[it.id]} className="nav__item" aria-current={current}>
                            {inner}
                          </Link>
                        ) : (
                          <button key={it.id} className="nav__item" aria-current={current} onClick={() => setSaid(it.label)} title="Still the prototype's screen">
                            {inner}
                          </button>
                        );
                      })}
                    </div>
                  )}
                </div>
              );
            })}
          </div>

          {slimBtn}
          {slimBtn}
          <div className="nav__foot">
            <div className="avatar">{initials(label)}</div>
            <div style={{ minWidth: 0, flexGrow: 1 }}>
              <div className="nav__who">{label}</div>
              <div className="nav__sub">{me ? roleUnit(office) || `${me.offices.length} office${me.offices.length === 1 ? "" : "s"} held` : "Not signed in"}</div>
            </div>
            <button title="Sign out" aria-label="Sign out" style={{ color: "var(--chrome-ink)", padding: 6 }}>
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                <path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4M10 8l-4 4 4 4M6 12h9" />
              </svg>
            </button>
          </div>
        </nav>

        <div className="main">
          <header className="topbar">
            <button className="menu-btn" aria-label="Open menu" onClick={() => { setNavOpen(true); document.body.classList.add("nav-open"); }}>
              <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <path d="M4 7h16M4 12h16M4 17h16" />
              </svg>
            </button>
            <div style={{ flexGrow: 1, minWidth: 0 }}>
              <h1>{t0}</h1>
              <div className="sub">{t1}</div>
            </div>
            <button className="topsrch" aria-label="Search" onClick={() => setSaid("Search")}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <circle cx="11" cy="11" r="7" />
                <path d="M20 20l-3.5-3.5" />
              </svg>
              <span>Search records</span>
              <kbd>/</kbd>
            </button>
          </header>
          <div className="content">
            {said && (
              <div className="notice notice--info">
                <Ico name="alert" size={18} stroke="var(--chrome)" w={2} />
                <div>
                  <div className="notice__t" style={{ color: "var(--chrome)" }}>
                    {said} is still the prototype&rsquo;s screen
                  </div>
                  <p style={{ color: "#124A63" }}>
                    The portal is built screen by screen against the API and the database. Until this one arrives,
                    it is the prototype&rsquo;s, exactly as designed.
                  </p>
                  <div style={{ marginTop: 11 }}>
                    <button className="btn btn--ghost btn--sm" onClick={() => setSaid(null)}>
                      Close
                    </button>
                  </div>
                </div>
              </div>
            )}
            {children}
          </div>
        </div>
      </div>
    </>
  );
}
