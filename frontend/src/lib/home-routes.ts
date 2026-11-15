/**
 * Where each office lands after signing in — its dashboard. The bare address ("/", app/page.tsx) draws the dashboard of most
 * offices; the offices listed here are sent on to their own desk, and app/page.tsx redirects from this one list, so the
 * dashboard the prompts read (V749: the blood group asked, the staff identity panel shown "on the dashboard") and the
 * dashboard a person lands on cannot drift apart.
 */

/** the offices whose home is a desk of their own, not the dashboard at "/" */
export const OFFICE_HOME: Readonly<Record<string, string>> = {
  /* the JUPEB office works from its own desk (V339) */
  jupeb: "/jupeb",
  /* V379: the Centre for Continuing Education's home is its desk */
  cce: "/cce",
  /* the administrator's home is the whole institution at one desk (proto part18) */
  admin: "/admin",
  /* the Vice-Chancellor's home is the institutional overview (menus.ts home t/overview) */
  vc: "/overview",
  /* the Librarian's home is the identity-card desk — "Card printing" (menus.ts home t/idcards); the circulation figures have
     their own desk under Library → Circulation */
  library: "/credentials/idcards",
  /* the College of Health Sciences officers land in the College module — its own dashboard area. They sign in through this
     same login (single sign-on); the login gate routes them here. */
  provost: "/college/dashboard",
  collegesecretary: "/college/dashboard",
  financecontroller: "/college/dashboard",
  mbbscoordinator: "/college/coordinator",
  /* the ICT Support Agent's home is the desk's queue (V251) */
  ictagent: "/helpdesk",
  /* an external examiner's home is their own workspace (V254) */
  extexaminer: "/examiner",
  /* the Linkages & Partnerships office and the Legal Officer work from the partnerships desk (V658) */
  linkages: "/partnerships",
  legal: "/partnerships",
  /* the preliminary and proficiency offices work from their desk (V446, V701): each opens on its own programmes */
  prelim: "/preliminary",
  prelimtech: "/preliminary",
  /* the Dean of Student Affairs runs the hostels (V290): their home is the hostel dashboard (menus.ts home t/hostel), not the
     general dashboard at "/", which has no figures for the office */
  dsa: "/hostel",
};

/** the student's dashboards: the University's student portal, and the College's own student area for a programme the College
 *  runs itself (MBBS, V603) — app/page.tsx sends a student to one or the other from GET /me */
export const STUDENT_HOMES: readonly string[] = ["/student", "/college/student"];

/** an applicant's home is their application, or the JUPEB candidate's portal (V339) */
export const APPLICANT_HOMES: readonly string[] = ["/applicant", "/jupeb/portal"];

/** the one landing path of a staff office: its own desk, or the dashboard at "/" */
export function officeHome(office: string | null | undefined): string {
  return (office && OFFICE_HOME[office]) || "/";
}

/** every path that is the office's dashboard */
export function homePaths(office: string | null | undefined): readonly string[] {
  if (office === "student") return STUDENT_HOMES;
  if (office === "applicant") return APPLICANT_HOMES;
  return [officeHome(office)];
}

/** whether the page shown is the acting office's dashboard (a trailing slash read as none) */
export function isHomePath(office: string | null | undefined, pathname: string | null | undefined): boolean {
  if (!pathname) return false;
  const path = pathname.length > 1 ? pathname.replace(/\/+$/, "") : pathname;
  return homePaths(office).includes(path);
}
