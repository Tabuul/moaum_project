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
import { useEffect, useState, type ReactNode } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
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
  "r/siwes": "/siwes",
  "r/mysiwes": "/me/siwes",
  "t/deptcourses": "/catalogue",
  "t/structure": "/catalogue/structure",
  "t/courseupload": "/catalogue/upload",
  "t/facultyupload": "/structure/faculties",
  "t/programmeupload": "/structure/programmes",
  "t/departmentupload": "/structure/departments",
  "t/eligibility": "/eligibility",
  "t/overview": "/overview",
  "r/admin": "/admin",
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
  "t/de-screening": "/admissions/de-screening",
  "t/pgadmissions": "/admissions/postgraduate",
  "t/pgcourses": "/admissions/postgraduate/courses",
  "t/pgcalendar": "/admissions/postgraduate/calendar",
  "t/pgstudents": "/admissions/postgraduate/students",
  "t/pgscores": "/admissions/postgraduate/results",
  "t/pgexams": "/admissions/postgraduate/examinations",
  "t/pgregistration": "/admissions/postgraduate/registration",
  "t/pgsenate": "/admissions/postgraduate/senate",
  "t/pgboard": "/admissions/postgraduate/board",
  "t/pgexaminers": "/admissions/postgraduate/examiners",
  "t/pgresearch": "/admissions/postgraduate/research",
  "t/pgsupervision": "/admissions/postgraduate/research?stage=REGISTERED",
  "t/pgproposals": "/admissions/postgraduate/research?stage=PROPOSAL_SUBMITTED",
  "t/pgseminars": "/admissions/postgraduate/research?stage=PROPOSAL_APPROVED",
  "t/pgpanels": "/admissions/postgraduate/research?stage=DRAFT_SUBMITTED",
  "t/pgtheses": "/admissions/postgraduate/research",
  "t/pgclearance": "/admissions/postgraduate/clearance",
  "t/postutme": "/admissions/computed-screening",
  "t/screening": "/admissions/screening",
  "t/putme": "/admissions/scores",
  "t/candidatedata": "/admissions/candidate-data",
  "t/migrate": "/admissions/migrate",
  "t/readiness": "/readiness",
  "t/teaching": "/me/teaching",
  "t/deptstaff": "/hod/staff",
  "t/matriculation": "/matriculation",
  "t/reports": "/reports",
  "t/regstudents": "/reports/students",
  "t/regstaff": "/reports/staff",
  "t/college": "/college",
  "t/postings": "/college/postings",
  "t/supervision": "/college/supervision",
  "t/collegeexams": "/college/examinations",
  "t/collegecalendar": "/college/calendar",
  "t/collegesheets": "/college/scoresheets",
  "r/mbbscoordinator": "/college/coordinator",
  "r/college": "/college/dashboard",
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
  "t/lecturers": "/people/lecturers",
  "t/staffupload": "/people/staff",
  "a/password": "/account/password",
  /* the student's side (proto/part3, part4, part29) */
  "s/dashboard": "/student",
  "s/register": "/student/register",
  "s/form": "/student/form",
  "s/results": "/student/results",
  "s/research": "/student/research",
  "s/pgcourses": "/student/pg-courses",
  "s/broadsheet": "/student/broadsheet",
  "s/slip": "/student/results",
  "s/fees": "/student/fees",
  "s/pay": "/student/fees",
  "s/receipt": "/student/fees",
  "s/profile": "/student/profile",
  "s/notifications": "/student/notifications",
  "s/query": "/student/query",
  "s/carryover": "/student/carryover",
  "s/reghistory": "/student/registration-history",
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
  "t/fundsources": "/finance/sources",
  "t/legacyfees": "/finance/legacy-fees",
  "t/nelmatch": "/finance/nelfund?tab=match",
  "t/nelstatus": "/finance/nelfund?tab=status",
  "s/courses": "/student/courses",
  "t/lms": "/lms",
  "r/upload": "/lms?tab=upload",
  "s/support": "/student/support",
  "s/biodata": "/student/biodata",
  "t/support": "/support",
  /* ICT support tickets (V251): the requester's side, the desk, the Director's reports and settings */
  "s/tickets": "/tickets",
  "r/tickets": "/tickets",
  "t/helpdesk": "/helpdesk",
  "t/helpdeskreports": "/helpdesk/reports",
  "t/helpdesksettings": "/helpdesk/settings",
  /* external examiners (V254): the examiner's workspace, and the desk */
  "x/dashboard": "/examiner",
  "x/projects": "/examiner/projects",
  "x/pending": "/examiner/projects?filter=pending",
  "x/submitted": "/examiner/projects?filter=submitted",
  "x/profile": "/examiner/profile",
  "t/extexaminers": "/examiners",
  "t/extappointments": "/examiners/appointments",
  "t/extassignments": "/examiners/projects",
  "t/extassessments": "/examiners/assignments",
  "t/extreports": "/examiners/reports",
  "t/gateways": "/finance/gateways",
  "t/mail": "/platform/mail",
  "t/sms": "/platform/sms",
  "t/ledger": "/finance/ledger",
  "t/accounts": "/finance/accounting",
  "t/payments": "/finance/payments",
  "t/paymenthistory": "/finance/payments-history",
  "t/hanging": "/finance/hanging",
  "t/heldscripts": "/finance/held-scripts",
  "t/reconcile": "/finance/reconcile",
  "t/payroll": "/payroll",
  "t/auditpayroll": "/payroll/variance",
  "t/staff": "/staff",
  "t/transfers": "/transfers",
  "s/transfer": "/student/transfer",
  "t/matlist": "/matriculation",
  "t/alumni": "/alumni",
  "t/leave": "/hr/leave",
  "t/movement": "/hr/movements",
  "t/recruit": "/hr/recruitment",
  "t/appraisal": "/hr/appraisal",
  "t/governance": "/governance",
  "t/security": "/security",
  "t/dr": "/disaster-recovery",
  "t/cloud": "/cloud",
  "t/release": "/release",
  "t/ethics": "/ethics",
  "t/requisitions": "/finance/requisitions",
  "t/stores": "/stores",
  "t/projects": "/research/projects",
  "t/auditassets": "/audit/assets",
  "t/cbtbank": "/exams/question-bank",
  "t/exams": "/examinations/sessions",
  "t/idlost": "/credentials/idcards",
  "t/auditrevenue": "/audit/revenue",
  "t/auditstaff": "/audit/staff",
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
  "t/legacy": "/records/migration",
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
  /* the postgraduate applicant's own portal (pg/portal, pg/apply) */
  "pg/portal": "/pg/portal",
  "pg/apply": "/pg/apply",
  "pg/summary": "/pg/summary/pdf",
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
  "t/staffupload": ["Non-Academic Staff", "The nominal roll loaded into the unit register; no sign-ins issued"],
  "s/tickets": ["My Support Tickets", "Your tickets with the Directorate of ICT, and a new one"],
  "r/tickets": ["My Support Tickets", "Your tickets with the Directorate of ICT, and a new one"],
  "t/helpdesk": ["ICT Support Desk", "The queue, the figures, and each ticket's every act on the record"],
  "t/helpdeskreports": ["ICT Support Reports", "Tickets by date, category, status, unit, requester and agent; response and resolution times"],
  "t/helpdesksettings": ["ICT Support Settings", "The categories and what each asks for, the SLA by priority, the quiet spell"],
  "x/dashboard": ["Examiner Workspace", "The projects assigned to you, their deadlines, and what has gone in"],
  "x/projects": ["My Assigned Projects", "Every project the University has sent you"],
  "x/pending": ["Pending Reviews", "Assessments not yet submitted"],
  "x/submitted": ["Submitted Reviews", "Assessments submitted; read-only unless reopened"],
  "x/profile": ["My Profile", "Your record as the University holds it"],
  "t/extexaminers": ["External Examiners", "The register, their appointments, the projects sent to them"],
  "t/extappointments": ["Examiner Appointments", "Each engagement for a session and a unit"],
  "t/extassignments": ["Project Assignments", "Projects registered for external examination, and the examiners each is with"],
  "t/extassessments": ["Assessments", "Every assignment and its assessment: read, locked, reopened"],
  "t/extreports": ["Examiner Reports", "Real figures from the assignments and assessments on record"],
  "t/reports": ["Reports & returns", "The University's statutory returns, read off the register and branded for print"],
  "t/regstudents": ["Student register", "Every student on the books — filter by faculty, programme, level, sex, status and entry; search by name or number"],
  "t/regstaff": ["Staff register", "Every member of staff — filter by faculty, department, rank, category and status; search by name or number"],
  "t/sms": ["SMS gateway", "The eBulkSMS account the portal sends text messages from"],
  "r/lecturer": ["Lecturer dashboard", "Your courses, marks and staff profile this session"],
  "r/hod": ["Head of Department", "Your department's desk — approvals, allocation and results"],
  "r/pgschool": ["School of Postgraduate Studies", ""],
  "t/pgregistration": ["Registration & matriculation", "Fresh students, semester renewal and the lapsed — Policy 7–8"],
  "t/pgexams": ["Course examinations", "Sittings and the results the Chief Examiners have submitted — Policy 17"],
  "t/pgclearance": ["Thesis clearance", "Final versions cleared for binding — Policy 31–32"],
  "t/pgsenate": ["Results to Senate", "Computed results with Senate, and the awarded of the session — Policy 33–34"],
  "r/college": ["College of Health Sciences", "The Provost, the Registry and the Finance of the College"],
  "r/mbbscoordinator": ["MBBS Coordinator", "The level's cohorts, score sheet, results and years"],
  "t/pgcalendar": ["Postgraduate calendar", "The School's own sessions and semesters, apart from the undergraduate calendar"],
  "pg/portal": ["Your postgraduate application", "Applicant portal"],
  "pg/apply": ["Apply for a postgraduate programme", "School of Postgraduate Studies"],
};

export const TITLES: Record<string, [string, string]> = { ...PROTOTYPE_TITLES, ...OVERRIDES };

/* an office the prototype drew no menu for still signs in */
const FALLBACK: Menu = {
  label: "Office",
  home: "r/academic",
  groups: [
    { name: "Records", items: [{ id: "t/search", icon: "user", label: "Search" }, { id: "r/academic", icon: "home", label: "Dashboard" }] },
    { name: "Me", items: [{ id: "r/self", icon: "user", label: "Leave & Payslip" }] },
  ],
};

export interface Me {
  actorId: string;
  activeOffice: string | null;
  offices: string[];
  name?: string | null;
  staffNumber?: string | null;
  sessionId?: string | null;
  /** an optional sub-line for the nav foot (e.g. a student's programme); falls back to the role's unit */
  unit?: string | null;
  /** what waits in each queue, by menu item id: the count, or "!" where an act is needed (iam/me) */
  waiting?: Record<string, string> | null;
  /** a menu other than the office's own — a postgraduate signs in as a student but reads the School's sidebar */
  menu?: string | null;
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

export function Shell({ route, me, children, sub, title }: { route: string; me: Me | null; children: ReactNode; sub?: string; title?: string }) {
  const router = useRouter();
  const pathname = usePathname();
  // the drawer (a body class the CSS reads) closes on every navigation — the Shell remounts per page, the body does not
  useEffect(() => { document.body.classList.remove("nav-open"); }, [pathname]);
  // the collapsed state lives on the body too; the button's label follows it after mount
  const [navSlim, setNavSlim] = useState(() => typeof document !== "undefined" && document.body.classList.contains("nav-slim"));
  const [navg, setNavg] = useState<Record<string, boolean>>({});
  const [said, setSaid] = useState<string | null>(null);
  const office = me?.activeOffice ?? null;
  const menu = (me?.menu && MENUS[me.menu]) || (office && MENUS[office]) || FALLBACK;
  const waiting = me?.waiting ?? {};
  const current = route === "r/academic" ? menu.home : route;
  const [t0def, t1def] = TITLES[current] ?? TITLES[route] ?? ["", ""];
  // a page may pass a live title and subtitle (the sheet's own course, the lecturer's real name) that beat the static ones
  const t0 = title && title.trim() ? title : t0def;
  const t1 = sub && sub.trim() ? sub : t1def;
  const label = me?.menu && MENUS[me.menu] ? MENUS[me.menu].label : roleLabel(office);
  const who = me?.name ?? label;

  const isOpen = (g: MenuGroup) => {
    if (Object.prototype.hasOwnProperty.call(navg, g.name)) return !!navg[g.name];
    return g.items.some((it) => it.id === current);
  };
  // the crumb above the title: the menu group the page sits in, and the page as the menu names it
  const crumbGroup = menu.groups.find((g) => g.items.some((it) => it.id === current));
  const crumbItem = crumbGroup?.items.find((it) => it.id === current);
  // "/" opens the search the hint in the top bar promises — never while typing in a field
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "/" || e.ctrlKey || e.metaKey || e.altKey) return;
      const t = e.target as HTMLElement | null;
      if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable)) return;
      e.preventDefault();
      router.push("/search");
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [router]);

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
        suppressHydrationWarning
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
      <div className="scrim" onClick={() => document.body.classList.remove("nav-open")} />
      <div className="shell">
        <nav className="nav" aria-label="Main">
          <div className="nav__brand">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/crest.png" alt="" className="nav__crest" />
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

          <div className="nav__list nav__list--all">
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
            <div className="nav__me">
              <div className="nav__who">{who}</div>
              <div className="nav__sub">{me ? (me.unit || (me.name ? label : roleUnit(office) || `${me.offices.length} office${me.offices.length === 1 ? "" : "s"} held`)) : "Not signed in"}</div>
            </div>
            <button className="nav__out" title="Sign out" aria-label="Sign out" onClick={() => void signOut()}>
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
                <path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4M10 8l-4 4 4 4M6 12h9" />
              </svg>
            </button>
          </div>
        </nav>

        <div className="main">
          <header className="topbar">
            <button className="menu-btn" aria-label="Open menu" onClick={() => document.body.classList.add("nav-open")}>
              <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <path d="M4 7h16M4 12h16M4 17h16" />
              </svg>
            </button>
            <div className="topbar__t">
              {crumbGroup && crumbItem && crumbItem.label !== t0 ? (
                <nav className="crumb" aria-label="Breadcrumb"><span>{crumbGroup.name}</span><span className="crumb__s" aria-hidden="true">›</span><span>{crumbItem.label}</span></nav>
              ) : crumbGroup ? (
                <nav className="crumb" aria-label="Breadcrumb"><span>{crumbGroup.name}</span></nav>
              ) : null}
              <h1>{t0}</h1>
              {t1 ? <div className="sub">{t1}</div> : null}
            </div>
            {me ? (
              <div className="topbar__me" title={label}>
                <div className="avatar avatar--sm">{initials(who)}</div>
                <div className="topbar__who"><div className="topbar__name">{who}</div><div className="topbar__role">{label}</div></div>
              </div>
            ) : null}
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
                  <div className="notice__t">{said} is still the prototype&rsquo;s screen</div>
                  <p>
                    The portal is built screen by screen against the API and the database. Until this one arrives,
                    it is the prototype&rsquo;s, exactly as designed.
                  </p>
                  <div className="notice__a">
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
