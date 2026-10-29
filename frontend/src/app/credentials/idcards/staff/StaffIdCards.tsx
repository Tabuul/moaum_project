"use client";

/**
 * V698: the Security Unit's staff identity cards — every member of staff in service (an office on the portal, or the HR staff register,
 * with a staff number), the card in force, issued and printed one at a time or all at once. The narrowing (faculty, unit, search,
 * card) is the server's, kept in the address, so the issue and the print take the same people the list shows.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { rankCase } from "@/lib/staff-card-face";
import { issueWords, printAllHref, staffCardsHref, type StaffCardFilters } from "@/lib/staff-cards";

export interface StaffRosterRow {
  person_id: string; staff_number: string; surname: string; given_names: string; category: string | null; rank: string | null;
  unit_code: string | null; unit: string | null; faculty_code: string | null; faculty: string | null; has_photo: boolean;
  blood_group: string | null; in_office: boolean; card_id: string | null; card_no: string | null; issued_at: string | null; valid_to: string | null;
  verify_path?: string;
}
export interface StaffRoster {
  counts: { staff: number; withCard: number; withoutCard: number; withoutPhoto: number; registerOnly: number };
  rows: StaffRosterRow[];
  faculties: { code: string; name: string }[];
  units: { code: string; name: string; faculty_code: string | null }[];
}

const dayOf = (v: string | null) => (v ? new Date(v).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");

export function StaffIdCards({ roster, filters, actingOffice }: { roster: StaffRoster; filters: StaffCardFilters; actingOffice: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  // GAP-005: the Security Unit (and super) issues and prints; HR and the other offices read the list
  const may = ["security", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [search, setSearch] = useState(filters.q ?? "");
  const c = roster.counts;
  const go = (f: Partial<StaffCardFilters>) => queryNav(staffCardsHref({ ...filters, ...f }));
  const units = roster.units.filter((u) => !filters.faculty || u.faculty_code === filters.faculty);
  const narrowed = Boolean(filters.faculty || filters.unit || filters.q);
  const what = filters.unit ? roster.units.find((u) => u.code === filters.unit)?.name ?? filters.unit
    : filters.faculty ? roster.faculties.find((f) => f.code === filters.faculty)?.name ?? filters.faculty
    : filters.q ? `"${filters.q}"` : "the University";

  async function post(key: string, path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/credentials/identity-cards${path}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j && typeof j === "object" && "status" in j ? j : { status: r.status, title: r.statusText }) as Problem; setProblem(p); notifyProblem(p); return null; }
      return (j ?? {}) as Record<string, unknown>;
    } finally { setBusy(null); }
  }

  async function issueAll() {
    if (!window.confirm(`Issue a staff identity card to each of the ${c.withoutCard} member${c.withoutCard === 1 ? "" : "s"} of staff in ${what} with none in force? Each card is numbered and valid to 31 December three years on.`)) return;
    const j = await post("all", "/staff/issue-all", { faculty: filters.faculty, unit: filters.unit, q: filters.q, reason: `Staff identity cards issued in bulk — ${what}` },
      `Staff identity cards issued in bulk — ${what}`);
    if (!j) return;
    notify(issueWords((j.tally ?? {}) as Record<string, number>));
    router.refresh();
  }

  async function issueOne(row: StaffRosterRow) {
    const j = await post(`one-${row.person_id}`, "/staff/issue", { staffNumber: row.staff_number }, `Staff identity card issued to ${row.staff_number}`);
    if (!j) return;
    notify(`Card ${String(j.cardNo ?? "")} issued to ${row.surname}, ${row.given_names}`);
    router.refresh();
  }

  return (
    <>
      <Tiles items={[
        ["Staff in service", String(c.staff), null, narrowed ? `In ${what}` : "Office or HR staff register"],
        ["Cards in force", String(c.withCard), c.withCard ? "var(--green-ink)" : null, "Printable now"],
        ["Without a card", String(c.withoutCard), c.withoutCard ? "var(--red-ink)" : null, "To issue"],
        ["Without a photograph", String(c.withoutPhoto), c.withoutPhoto ? "var(--chrome)" : null, "Printed with a blank frame"],
      ]} />
      <Note kind="info" title="A staff card is issued on the staff number to a member of staff in service">
        In service means holding an office on the portal today, or being on the HR staff register (the non-teaching staff). A card is
        numbered and valid to 31 December three years on; the print carries its QR, which the public check answers. A lost or
        damaged card is replaced on the Student ID Card desk&rsquo;s staff list.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title="Print and issue" right={<span className="sub2">{what}</span>}>
        <PBody>
          <div className="row row--inline" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
            <label className="sub2" htmlFor="sc-fac">Faculty</label>
            <select id="sc-fac" className="ctl" style={{ maxWidth: 240 }} value={filters.faculty ?? ""} onChange={(e) => go({ faculty: e.target.value || null, unit: null })}>
              <option value="">All faculties and units</option>
              {roster.faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}
            </select>
            <label className="sub2" htmlFor="sc-unit">Department or unit</label>
            <select id="sc-unit" className="ctl" style={{ maxWidth: 280 }} value={filters.unit ?? ""} onChange={(e) => go({ unit: e.target.value || null })}>
              <option value="">All</option>
              {units.map((u) => <option key={u.code} value={u.code}>{u.name}</option>)}
            </select>
            <form className="row row--inline row--tight" onSubmit={(e) => { e.preventDefault(); go({ q: search.trim() || null }); }}>
              <input className="ws__in" value={search} placeholder="Name, staff number or card number" aria-label="Search the staff" onChange={(e) => setSearch(e.target.value)} />
              <Btn kind="ghost" size="sm" type="submit">Search</Btn>
            </form>
            <select className="ctl" aria-label="Card" style={{ maxWidth: 180 }} value={filters.card ?? ""} onChange={(e) => go({ card: e.target.value || null })}>
              <option value="">With or without a card</option>
              <option value="WITH">Card in force</option>
              <option value="WITHOUT">Without a card</option>
            </select>
          </div>
          {may ? (
            <div className="row row--inline mt-3" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
              <a className={`btn btn--primary${c.withCard ? "" : " is-disabled"}`} aria-disabled={!c.withCard} href={c.withCard ? printAllHref(filters) : undefined} target="_blank" rel="noopener"
                title="One PDF, a card (front and back) to a page, names A–Z">Print all {c.withCard} card{c.withCard === 1 ? "" : "s"} in force (PDF)</a>
              <Btn kind="secondary" disabled={busy !== null || !c.withoutCard} onClick={() => void issueAll()}>
                {busy === "all" ? "Issuing…" : `Issue cards to all ${c.withoutCard} without one`}
              </Btn>
              <span className="sub2">Issue first, then print: the print carries each card&rsquo;s number.</span>
            </div>
          ) : <div className="sub2 mt-3">The Security Unit issues and prints the cards; you can read the list.</div>}
        </PBody>
      </Panel>

      <Panel title="Staff" right={`${roster.rows.length} shown`}>
        {roster.rows.length ? (
          <DTable
            cols={["S/N|num", "Member of staff", "Rank", "Department or unit", "Photo|mid", "Card", "|num"]}
            rows={roster.rows.map((r, i) => [
              <span key="sn" className="tnum sub2">{i + 1}</span>,
              <Two key="n" a={`${r.surname}, ${r.given_names}`} b={`${r.staff_number}${r.category ? ` · ${r.category === "ACADEMIC" ? "Academic" : "Non-teaching"}` : ""}`} />,
              <span key="r" className="sub2">{rankCase(r.rank) || "—"}</span>,
              <Two key="u" a={r.unit ?? "—"} b={r.faculty ?? ""} />,
              r.has_photo ? <Pil key="p" kind="ok">On file</Pil> : <Pil key="p" kind="grey">None</Pil>,
              r.card_no ? <Two key="c" a={r.card_no} b={`Valid to ${dayOf(r.valid_to)}`} /> : <Pil key="c" kind="warn">No card</Pil>,
              <span key="a" className="row row--inline row--tight" style={{ flexWrap: "nowrap", justifyContent: "flex-end" }}>
                {may && r.card_no ? <a className="btn btn--ghost btn--sm" href={`/staff/idcard/pdf?id=${encodeURIComponent(r.person_id)}`} target="_blank" rel="noopener">Print</a> : null}
                {may && !r.card_no ? <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => void issueOne(r)}>{busy === `one-${r.person_id}` ? "Issuing…" : "Issue"}</Btn> : null}
              </span>,
            ])}
            texts={roster.rows.map((r) => `${r.surname} ${r.given_names} ${r.staff_number} ${r.card_no ?? ""} ${r.unit ?? ""} ${r.rank ?? ""}`)}
          />
        ) : <PBody><div className="sub2">No member of staff in service matches{narrowed ? ` ${what}` : ""}.</div></PBody>}
      </Panel>
    </>
  );
}
