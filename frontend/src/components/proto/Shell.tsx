"use client";

/**
 * The prototype's shell (proto/part6.html renderBase and navHTML): the
 * navigation with the crest, the "Signed in as" select, the folded groups
 * with their counts, the collapse control and the foot; the topbar with the
 * menu button, the screen's title and the search; and the content area.
 * Same classes, same structure. The menu is the acting office's, exactly as
 * the prototype lays it out for each of the offices (lib/menus); items the
 * portal does not yet serve are the same buttons, and say so when pressed.
 */
import { useState, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Ico } from "./ui";
import { OFFICE_COOKIE, roleLabel, roleUnit } from "@/lib/offices";
import { MENUS, type Menu, type MenuGroup } from "@/lib/menus";
import { TITLES as PROTOTYPE_TITLES } from "@/lib/titles";

/* where the portal serves each screen; every other item is still the prototype's */
export const ROUTES: Record<string, string> = {
  "t/search": "/search",
  "r/academic": "/",
  "t/records": "/records",
  "t/students": "/students",
  "t/student": "/students",
  "t/biochange": "/students/biodata-changes",
  "r/classlist": "/registration/class-list",
  "r/allocate": "/allocate",
  "t/deptcourses": "/catalogue",
  "t/eligibility": "/eligibility",
  "t/overview": "/overview",
  "t/refunds": "/finance/refunds",
  "t/pv": "/vouchers",
  "t/prepayment": "/vouchers",
  "t/budget": "/finance/budget",
  "t/tenders": "/finance/tenders",
  "t/audit": "/audit",
  "t/notify": "/notices",
  "t/channels": "/notices",
  "t/api": "/api-keys",
  "t/migration": "/migrations",
  "t/admissions": "/admissions",
  "t/admissionsetup": "/admissions/settings",
  "t/capsintake": "/admissions/caps",
  "t/applicants": "/admissions/applicants",
  "t/merit": "/admissions/merit",
  "t/putme": "/admissions/scores",
  "t/candidatedata": "/admissions/candidate-data",
  "t/matriculation": "/matriculation",
  "t/reports": "/reports",
  "t/college": "/college",
  "t/session": "/calendar",
  "t/examsession": "/examinations/sessions",
  "t/clearance": "/clearance",
  "t/transcripts": "/credentials/transcripts",
  "t/certificates": "/credentials/certificates",
  "t/graduation": "/graduation",
  "t/approvals": "/results/approvals",
  "t/chain": "/results/chain",
  "r/self": "/me",
  "t/users": "/people",
  "a/password": "/account/password",
  /* the student's side (proto/part3, part4, part29) */
  "s/dashboard": "/student",
  "s/register": "/student/register",
  "s/form": "/student/form",
  "s/results": "/student/results",
  "s/slip": "/student/results",
  "s/fees": "/student/fees",
  "s/pay": "/student/fees",
  "s/receipt": "/student/fees",
  "s/profile": "/student/profile",
  "s/notifications": "/student/notifications",
  "s/query": "/student/query",
  "s/carryover": "/student/carryover",
  "s/transcript": "/student/transcript",
  "s/exams": "/student/exams",
  "s/timetable": "/student/timetable",
  "s/attendance": "/student/attendance",
  "s/idcard": "/student/idcard",
  "s/graduation": "/student/graduation",
  "s/hostel": "/student/hostel",
  "t/hostel": "/hostel",
  "s/library": "/student/library",
  "t/circulation": "/library/circulation",
  "s/health": "/student/health",
  "t/clinic": "/clinic",
  "s/wallet": "/student/wallet",
  "t/nelfund": "/finance/nelfund",
  "t/nelmatch": "/finance/nelfund?tab=match",
  "t/nelstatus": "/finance/nelfund?tab=status",
  "s/courses": "/student/courses",
  "t/lms": "/lms",
  "r/upload": "/lms?tab=upload",
  "s/support": "/student/support",
  "s/biodata": "/student/biodata",
  "t/support": "/support",
  "t/gateways": "/finance/gateways",
  "t/mail": "/platform/mail",
  "t/ledger": "/finance/ledger",
  "t/hanging": "/finance/hanging",
  "t/reconcile": "/finance/reconcile",
  "t/exception": "/finance/exceptions",
  "t/cashdesk": "/finance/exceptions",
  "t/feesched": "/finance/fees",
  "t/feesetup": "/finance/fees",
  "t/scores": "/results/sheets",
  "t/sheet": "/results/sheets",
  "t/bulk": "/results/sheets",
  "t/resultdesk": "/results/desk",
  "t/review": "/results/chain",
  "t/pipeline": "/results/pipeline",
  "t/broadsheet": "/results/broadsheet",
  "t/senate": "/results/senate",
  "t/publish": "/results/publish",
  "t/idcards": "/credentials/idcards",
  "t/queries": "/results/queries",
  /* the applicant's journey (proto/part13.html) */
  "a/dashboard": "/applicant",
  "a/apply": "/applicant/apply",
  "a/fee": "/applicant/fee",
  "a/screening": "/applicant/screening",
  "a/score": "/applicant/score",
  "a/status": "/applicant/status",
  "a/accept": "/applicant/accept",
  "a/clearance": "/applicant/clearance",
  "a/matric": "/applicant/matric",
};

/* the portal's own subtitles where the prototype's named an invented figure */
const OVERRIDES: Record<string, [string, string]> = {
  "t/student": ["Student record", "Assembled live from the modules that own it"],
  "t/admissions": ["Admissions", "The admission cycle"],
  "t/admissionsetup": ["Admission settings", "The Central Admissions Committee’s guidelines, made into settings the portal applies"],
  "t/matriculation": ["Matriculation", "Numbers issued over the confirmed register"],
  "t/examsession": ["Examination sessions", "Every sheet, and whose it is"],
  "t/certificates": ["Certificates", "The register, and the stock it is printed on"],
  "t/approvals": ["Results to Senate", "Where every result set has reached"],
  "t/chain": ["Approval chain", "One sheet, every desk it passes"],
  "a/password": ["Your password", "Chosen by you, known to nobody else"],
  "s/graduation": ["Graduation", "The audit, Senate's word, clearance and the certificate"],
  "t/support": ["Help & requests", "What students have put to this office, the oldest open first"],
  "t/reports": ["Reports & returns", "The University's statutory returns, read off the register and branded for print"],
};

export const TITLES: Record<string, [string, string]> = { ...PROTOTYPE_TITLES, ...OVERRIDES };

/* an office the prototype drew no menu for still signs in */
const FALLBACK: Menu = {
  label: "Office",
  home: "r/academic",
  groups: [
    { name: "Records", items: [{ id: "t/search", icon: "user", label: "Search" }, { id: "r/academic", icon: "home", label: "Dashboard" }] },
    { name: "Me", items: [{ id: "r/self", icon: "user", label: "Leave & payslip" }] },
  ],
};

export interface Me {
  actorId: string;
  activeOffice: string | null;
  offices: string[];
  name?: string | null;
  staffNumber?: string | null;
  sessionId?: string | null;
  /** what waits in each queue, by menu item id: the count, or "!" where an act is needed (iam/me) */
  waiting?: Record<string, string> | null;
}

/* the prototype drew its counts as fixtures; the portal draws what the API says is waiting, and nothing else */
function navWaiting(g: MenuGroup, waiting: Record<string, string>): number {
  let n = 0;
  for (const it of g.items) {
    const badge = waiting[it.id];
    if (!badge) continue;
    n += /^\d+$/.test(badge) ? parseInt(badge, 10) : 1;
  }
  return n;
}

function initials(label: string): string {
  const w = label.replace(/[()]/g, "").split(/[\s,]+/).filter(Boolean);
  return ((w[0]?.[0] ?? "") + (w[1]?.[0] ?? "")).toUpperCase() || "MP";
}

export function Shell({ route, me, children }: { route: string; me: Me | null; children: ReactNode }) {
  const router = useRouter();
  const [navOpen, setNavOpen] = useState(false);
  const [navSlim, setNavSlim] = useState(false);
  const [navg, setNavg] = useState<Record<string, boolean>>({});
  const [said, setSaid] = useState<string | null>(null);
  const office = me?.activeOffice ?? null;
  const menu = (office && MENUS[office]) || FALLBACK;
  const waiting = me?.waiting ?? {};
  const current = route === "r/academic" ? menu.home : route;
  const [t0, t1] = TITLES[current] ?? TITLES[route] ?? ["", ""];
  const label = roleLabel(office);
  const who = me?.name ?? label;

  const isOpen = (g: MenuGroup) => {
    if (Object.prototype.hasOwnProperty.call(navg, g.name)) return !!navg[g.name];
    return g.items.some((it) => it.id === current);
  };

  function chooseOffice(code: string) {
    document.cookie = `${OFFICE_COOKIE}=${encodeURIComponent(code)}; path=/; max-age=31536000; samesite=lax`;
    router.refresh();
  }

  async function signOut() {
    await fetch("/api/auth/sign-out", { method: "POST" }).catch(() => null);
    router.push("/login");
    router.refresh();
  }

  const href = (id: string) => (id === menu.home ? "/" : ROUTES[id]);

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

          <div className="nav__list" style={{ flexGrow: 1, paddingBottom: 8 }}>
            {menu.groups.map((g) => {
              const open = isOpen(g);
              const folded = navWaiting(g, waiting);
              return (
                <div key={g.name}>
                  <button className="nav__gh" aria-expanded={open ? "true" : "false"} onClick={() => setNavg({ ...navg, [g.name]: !open })}>
                    <span className="gname">{g.name}</span>
                    {!open && folded ? <span className="gcount">{folded}</span> : null}
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
                            {waiting[it.id] ? <span className="nav__badge">{waiting[it.id]}</span> : null}
                          </>
                        );
                        const isCurrent = current === it.id ? "page" : undefined;
                        const to = href(it.id);
                        return to ? (
                          <Link key={it.id} href={to} className="nav__item" aria-current={isCurrent}>
                            {inner}
                          </Link>
                        ) : (
                          <button key={it.id} className="nav__item" aria-current={isCurrent} onClick={() => setSaid(it.label)} title="Still the prototype's screen">
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
          <div className="nav__foot">
            <div className="avatar">{initials(who)}</div>
            <div style={{ minWidth: 0, flexGrow: 1 }}>
              <div className="nav__who">{who}</div>
              <div className="nav__sub">{me ? (me.name ? label : roleUnit(office) || `${me.offices.length} office${me.offices.length === 1 ? "" : "s"} held`) : "Not signed in"}</div>
            </div>
            <button title="Sign out" aria-label="Sign out" style={{ color: "var(--chrome-ink)", padding: 6 }} onClick={() => void signOut()}>
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
            <button className="topsrch" aria-label="Search" onClick={() => router.push("/search")}>
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
