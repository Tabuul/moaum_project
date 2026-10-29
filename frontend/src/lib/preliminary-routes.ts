/**
 * V701 — the preliminary and proficiency routes' own words, apart from lib/preliminary (whose calls need the browser): each
 * route's public page, the entry requirement in one sentence, the qualifications a route accepts, a duration, the serial of a
 * route's exported reports. Pure, so the unit tests read it directly.
 */
import type { PrelimPublic, PrelimRules } from "./preliminary";

/** V701: the public page of each route, and the routes of the preliminary stack */
export const PRELIM_PAGES: Record<string, string> = {
  PRELIMINARY_SCIENCE: "/preliminary-science", PRELIMINARY_TECHNOLOGY: "/preliminary-technology", PROFICIENCY_CERTIFICATE: "/proficiency-certificate",
};
export const PRELIM_SLUGS: Record<string, string> = Object.fromEntries(Object.entries(PRELIM_PAGES).map(([r, path]) => [path.slice(1), r]));
export const isPrelimRoute = (route: string | null | undefined): boolean => !!route && route in PRELIM_PAGES;
export const prelimPage = (route: string): string => PRELIM_PAGES[route] ?? "/preliminary-science";

/** the entry requirement in one sentence, as the route's rule states it */
export function requirementWords(p: Pick<PrelimPublic, "rules" | "groupWord" | "entryRequirement">): string {
  const r = p.rules;
  if (r.kind === "ATTEMPTED_CERTIFICATE") return p.entryRequirement ?? "An attempted secondary school certificate: the examination sat and its results given.";
  const req = r.requiredSubjects.length ? `, including ${r.requiredSubjects.join(" and ")}` : "";
  const core = r.coreByTarget ? `${r.minCoreCredits} of them in the subjects of the ${p.groupWord} you choose`
    : `${r.minCoreCredits} of them in ${r.coreSubjects.join(", ")}`;
  return `At least ${r.minCredits} O'Level credit passes (${r.creditGrade} or better)${req}, in at most ${r.maxSittings} sitting${r.maxSittings === 1 ? "" : "s"}; ${core}. An awaiting result is not accepted.`;
}

/** "9 months" */
export const monthsWords = (n: number | null | undefined): string => (n == null ? "Not configured" : `${n} month${n === 1 ? "" : "s"}`);

/** the serial prefix of a route's exported reports */
export const prelimSerial = (route: string): string =>
  ({ PRELIMINARY_SCIENCE: "PRESCI", PRELIMINARY_TECHNOLOGY: "PRETECH", PROFICIENCY_CERTIFICATE: "PROFCERT" } as Record<string, string>)[route] ?? "PRELIM";

export const EXAM_TYPES: [string, string][] = [["SSCE", "School certificate (May/June)"], ["GCE", "GCE (Nov/Dec)"], ["OTHER", "Another"]];
/** V701: the qualifications a route accepts, as its rule lists them (the school certificate, the GCE, the NTC, the NBC, City & Guilds, …) */
export const examTypes = (r: Pick<PrelimRules, "qualifications"> | null | undefined): [string, string][] =>
  r?.qualifications?.length ? r.qualifications.map((q) => [q.code, q.label] as [string, string]) : EXAM_TYPES;
