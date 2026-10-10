/** V387: the Quick Operational Manual — the procedures a person reads, resolved against the portal's own menus.
 *  A step names a control in backticks and a menu item as {menu:<id>}; the id is resolved here to the item's current label
 *  (from the sidebars) and, given the route map, its page — so a menu renamed later renames the manual. Pure, node-tested. */
import { MENUS, type Menu } from "./menus.ts";

export type ManualCategory = "DASHBOARD" | "ACCOUNT" | "STUDENTS" | "PAYMENTS" | "ADMISSIONS" | "ACADEMICS" | "RESULTS" | "EXAMS" | "SUPPORT" | "REPORTS" | "SETTINGS";
export type ManualState = "DRAFT" | "PUBLISHED" | "ARCHIVED";
export type Routes = Record<string, string>;

export interface Procedure {
  id: string; slug: string; title: string; purpose: string; category: ManualCategory; offices: string[]; capabilities: string[];
  menu_id: string | null; route: string | null; steps: string[]; expected: string; sort_order: number; state: ManualState; version: number;
  seeded?: boolean; published_at?: string | null; archived_at?: string | null; updated_at?: string; updated_office?: string | null;
  updated_by_name?: string | null; versions?: number; readings?: number;
}
export interface Edition { version: string; updated_at: string; note: string | null; updated_by: string | null; updated_office: string | null }
export interface ManualView { edition: Edition; office: string; keys: string[]; capabilities: string[]; q: string | null; procedures: Procedure[] }
export interface ManualAdminView {
  edition: Edition; procedures: Procedure[]; keys: string[]; categories: string[]; capabilities: string[];
  counts: { published: number; draft: number; archived: number; readings_30d: number };
}

export const CATEGORY_WORD: Record<ManualCategory, string> = {
  DASHBOARD: "Dashboard", ACCOUNT: "Account", STUDENTS: "Students", PAYMENTS: "Payments", ADMISSIONS: "Admissions", ACADEMICS: "Academics",
  RESULTS: "Results", EXAMS: "Exams", SUPPORT: "Support", REPORTS: "Reports", SETTINGS: "Settings",
};
export const CATEGORIES = Object.keys(CATEGORY_WORD) as ManualCategory[];
export const STATE_WORD: Record<ManualState, string> = { DRAFT: "Draft", PUBLISHED: "Published", ARCHIVED: "Archived" };

/** a menu item as the portal labels it for the sidebars given (the first sidebar carrying the id wins); any sidebar when none of them carries it */
export function menuItem(id: string, menus: string[], routes: Routes = {}): { label: string; href: string | null; group: string; own: boolean } | null {
  const find = (key: string, own: boolean) => {
    const m: Menu | undefined = MENUS[key];
    if (!m) return null;
    for (const g of m.groups) for (const it of g.items) if (it.id === id) return { label: it.label, href: routes[id] ?? null, group: g.name, own };
    return null;
  };
  for (const key of menus) { const hit = find(key, true); if (hit) return hit; }
  for (const key of Object.keys(MENUS)) { const hit = find(key, false); if (hit) return hit; }
  return null;
}

export type Piece = { kind: "text"; text: string } | { kind: "control"; text: string } | { kind: "menu"; id: string; label: string; href: string | null; missing: boolean };

/** a step split into text, `controls` and resolved {menu:…} references */
export function pieces(step: string, menus: string[], routes: Routes = {}): Piece[] {
  const out: Piece[] = [];
  const re = /\{menu:([^}]+)\}|`([^`]+)`/g;
  let last = 0; let m: RegExpExecArray | null;
  while ((m = re.exec(step)) !== null) {
    if (m.index > last) out.push({ kind: "text", text: step.slice(last, m.index) });
    if (m[1] !== undefined) {
      const id = m[1].trim();
      const it = menuItem(id, menus, routes);
      out.push({ kind: "menu", id, label: it ? it.label : id, href: it ? it.href : null, missing: !it });
    } else out.push({ kind: "control", text: m[2] });
    last = m.index + m[0].length;
  }
  if (last < step.length) out.push({ kind: "text", text: step.slice(last) });
  return out;
}

/** the step as plain text (print, PDF, search): the resolved label in place of the reference; a control between its backticks */
export function plain(step: string, menus: string[]): string {
  return pieces(step, menus).map((p) => (p.kind === "menu" ? p.label : p.kind === "control" ? `\`${p.text}\`` : p.text)).join("");
}

/** the step for paper: controls without their backticks */
export function paper(step: string, menus: string[]): string {
  return pieces(step, menus).map((p) => (p.kind === "menu" ? p.label : p.text)).join("");
}

/** every {menu:…} id a procedure names: its menu item, its route and the steps */
export function menuIds(p: Pick<Procedure, "menu_id" | "route" | "steps">): string[] {
  const ids = new Set<string>();
  if (p.menu_id) ids.add(p.menu_id);
  if (p.route) ids.add(p.route);
  for (const s of p.steps) for (const m of s.matchAll(/\{menu:([^}]+)\}/g)) ids.add(m[1].trim());
  return [...ids];
}

/** the references a procedure makes that the portal does not carry for the offices it is bound to (Manual Management's validation) */
export function unresolved(p: Pick<Procedure, "menu_id" | "route" | "steps" | "offices">, routes: Routes): { id: string; where: string }[] {
  const out: { id: string; where: string }[] = [];
  for (const id of menuIds(p)) {
    if (!routes[id]) { out.push({ id, where: "no page" }); continue; }
    const missing = p.offices.filter((o) => o !== "everyone" && MENUS[o] && !MENUS[o].groups.some((g) => g.items.some((it) => it.id === id)));
    if (missing.length) out.push({ id, where: `not on the ${missing.join(", ")} menu` });
  }
  return out;
}

/** a search over the procedures already loaded (one person's manual is small): title, purpose, category, steps and the resolved labels */
export function search(rows: Procedure[], q: string, menus: string[]): Procedure[] {
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) return rows;
  return rows.filter((p) => {
    const hay = [p.title, p.purpose, CATEGORY_WORD[p.category] ?? p.category, p.expected, ...p.steps.map((s) => plain(s, menus))].join(" ").toLowerCase();
    return words.every((w) => hay.includes(w));
  });
}

/** the manual grouped by category, in the manual's order */
export function byCategory(rows: Procedure[]): { category: ManualCategory; word: string; rows: Procedure[] }[] {
  const out: { category: ManualCategory; word: string; rows: Procedure[] }[] = [];
  for (const c of CATEGORIES) {
    const rs = rows.filter((p) => p.category === c);
    if (rs.length) out.push({ category: c, word: CATEGORY_WORD[c], rows: rs });
  }
  return out;
}

/** the sidebars a person reads under: the sidebar the portal names beside the office, then the office */
export function readerMenus(office: string | null | undefined, menu: string | null | undefined): string[] {
  const out: string[] = [];
  if (menu) out.push(menu);
  if (office && !out.includes(office)) out.push(office);
  return out;
}

/** the reader's title as the sidebar names it */
export function readerLabel(office: string | null | undefined, menu: string | null | undefined): string {
  const key = menu || office || "";
  return MENUS[key]?.label ?? (office ?? "Portal user");
}

/** the menu items of the sidebars given, for Manual Management's pickers */
export function menuChoices(menus: string[]): { id: string; label: string; group: string; menu: string }[] {
  const out: { id: string; label: string; group: string; menu: string }[] = [];
  const seen = new Set<string>();
  for (const key of menus) {
    const m = MENUS[key];
    if (!m) continue;
    for (const g of m.groups) for (const it of g.items) {
      if (seen.has(it.id)) continue;
      seen.add(it.id);
      out.push({ id: it.id, label: it.label, group: g.name, menu: key });
    }
  }
  return out;
}

/** the day a reader sees */
export function dayOf(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
}
