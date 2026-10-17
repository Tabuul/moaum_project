"use client";

/**
 * V513: the staff on the portal with no employment record in service, with what the portal already holds of each — the names and
 * contact, the category, the department (a lecturer's department grant, or the establishment record), the unit, rank, sex and first
 * appointment — downloaded as the appointment template filled in. Human Resources adds the grade, step and date of appointment and
 * uploads it on this screen; each row is checked before anything is written.
 */
import { useEffect, useState } from "react";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notifyProblem } from "@/components/proto/Toast";
import { buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import { CATEGORY_LABEL, TEMPLATE_HEAD } from "@/lib/appointments";

interface Unemployed {
  person_id: string; staff_no: string; surname: string; given_names: string; email: string | null; phone: string | null; category: string | null;
  department: string | null; department_name: string | null; unit: string | null; unit_name: string | null; rank: string | null; sex: string | null;
  first_appointment: string | null; source: "LECTURER" | "ESTABLISHMENT" | "ESTABLISHMENT_AND_LECTURER" | "PERSON_ONLY";
}
interface UnemployedList { counts: Record<string, number>; total: number; rows: Unemployed[] }

const SOURCE: { key: string; label: string; who: string }[] = [
  { key: "LECTURER", label: "Lecturers", who: "Department from the lecturer grant; academic" },
  { key: "ESTABLISHMENT", label: "On the establishment", who: "Unit, rank and category from the staff record" },
  { key: "ESTABLISHMENT_AND_LECTURER", label: "Both", who: "Staff record and lecturer grant" },
  { key: "PERSON_ONLY", label: "Name only", who: "HR completes the category and place" },
];
const vz = (n: number | null | undefined) => Number(n ?? 0).toLocaleString("en-GB");
const ddmmyyyy = (iso: string | null) => (iso ? iso.slice(0, 10).split("-").reverse().join("/") : "");

export function StaffWithoutEmployment() {
  const [list, setList] = useState<UnemployedList | null>(null);
  const [source, setSource] = useState("");
  const [q, setQ] = useState("");
  const [search, setSearch] = useState("");

  useEffect(() => {
    let alive = true;
    void (async () => {
      const qs = new URLSearchParams({ size: "5000" });
      if (q) qs.set("q", q);
      const r = await fetch(`/api/bff/api/v1/hr/appointments/without-employment?${qs.toString()}`, { cache: "no-store", headers: { "X-Background": "1" } });
      const j = await r.json().catch(() => null);
      if (!alive) return;
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setList(j as UnemployedList);
    })();
    return () => { alive = false; };
  }, [q]);

  const rows = (list?.rows ?? []).filter((r) => !source || r.source === source);

  function template() {
    downloadBlob(buildXlsx(TEMPLATE_HEAD, rows.map((r) => [
      r.staff_no, r.surname, r.given_names, r.sex ?? "", r.email ?? "", r.phone ?? "", r.category ?? "", "", "", ddmmyyyy(r.first_appointment),
      r.department ?? "", r.unit ?? "", r.rank ?? "", "", "", "", "",
    ]), "Appointments"), "staff-without-employment.xlsx");
  }

  return (
    <Panel title="Staff on the portal without an employment record" right={list ? `${vz(list.total)} in all` : "Counting…"}>
      <PBody>
        <div className="sub2">Download them as the appointment template, filled in with what the portal already holds. Add each one&rsquo;s grade, step and date of appointment (and the category and department or unit where blank), then upload the file above. Every row is checked before anything is written.</div>
        <div className="grid grid--4 mt-2" role="group" aria-label="Staff without an employment record, by where the details come from">
          {SOURCE.map((x) => (
            <button key={x.key} type="button" className="tile stat-tile" aria-pressed={source === x.key} onClick={() => setSource(source === x.key ? "" : x.key)}
              style={{ textAlign: "left", font: "inherit", border: source === x.key ? "2px solid var(--chrome)" : undefined }}>
              <div className="eyebrow">{x.label}</div>
              <div className="n tnum">{list ? vz(list.counts[x.key]) : "…"}</div>
              <div className="c">{x.who}</div>
            </button>
          ))}
        </div>
        <div className="row row--between mt-2" style={{ flexWrap: "wrap", gap: 8 }}>
          <form className="row row--inline" style={{ gap: 8 }} onSubmit={(e) => { e.preventDefault(); setQ(search.trim()); }}>
            <input className="ctl" aria-label="Search by staff number or name" placeholder="Staff number or name" value={search} onChange={(e) => setSearch(e.target.value)} />
            <Btn kind="ghost" type="submit">Search</Btn>
          </form>
          <Btn kind="secondary" size="sm" disabled={!rows.length} onClick={() => template()}>Download {vz(rows.length)} as the appointment template</Btn>
        </div>
      </PBody>
      {list && !list.total ? <PBody><Note kind="ok" title="Everyone on the portal with a staff number has an employment record" /></PBody> : null}
      {rows.length ? (
        <DTable pageSize={25} cols={["Staff No.", "Name", "Category", "Department / unit", "Rank", "From"]}
          rows={rows.map((r) => [
            <span key="n" className="tnum">{r.staff_no}</span>,
            <span key="m">{r.surname}, {r.given_names}</span>,
            <span key="c">{r.category ? CATEGORY_LABEL[r.category] ?? r.category : "—"}</span>,
            <span key="d">{r.department_name ?? r.department ?? r.unit_name ?? r.unit ?? "—"}</span>,
            <span key="k" className="sub2">{r.rank ?? "—"}</span>,
            <span key="s" className="sub2">{SOURCE.find((x) => x.key === r.source)?.label ?? r.source}</span>,
          ])} />
      ) : null}
    </Panel>
  );
}
