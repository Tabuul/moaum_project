"use client";
/** The students behind a GST or EPS figure (V314): the same rows the dashboard counted, paged fifty at a time, searched on the
 *  server, and the whole set as a branded Excel workbook or PDF with S/N first and names A–Z. S/N is display only.
 *  V366: each student with the office's own answer — whether its courses concern them and why — the lists of carryovers, of the
 *  students no course concerns, of payments no course requires, and "View eligibility" for the whole answer. */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { GstEligibilityView } from "@/components/gst/GstEligibilityView";
import { ELIGIBILITY_WORD, OFFICE_WORD, PAY_WORD, STAGE_WORD, dayOf, gstQuery, naira, num, reasonWord, type GstEpsExplain, type GstFilters, type GstStudentPage, type GstStudentRow } from "@/lib/gst";

export function GstStudents({ data, filters, base }: { data: GstStudentPage; filters: GstFilters; base: string }) {
  const go = useQueryNav();
  const o = data.office;
  const eps = o === "EPS";
  const word = eps ? "EPS" : "GST";
  const [q, setQ] = useState(filters.q ?? "");
  const [busy, setBusy] = useState(false);
  const [why, setWhy] = useState<{ row: GstStudentRow; data: GstEpsExplain | null } | null>(null);
  const f: GstFilters = { ...filters, session: data.session, semester: data.semester == null ? "" : String(data.semester) };
  async function openWhy(row: GstStudentRow) {
    setWhy({ row, data: null });
    const r = await fetch(`/api/bff/api/v1/gst/${o}/students/${row.student_id}?session=${encodeURIComponent(data.session)}`, { cache: "no-store" }).catch(() => null);
    const j = r ? await r.json().catch(() => null) : null;
    if (!r || !r.ok || !j?.explain) { notifyProblem((j as { status: number; title: string }) ?? { status: 503, title: "The eligibility could not be read just now." }); setWhy(null); return; }
    setWhy({ row, data: j.explain as GstEpsExplain });
  }
  const pages = Math.max(1, Math.ceil(data.total / data.size));
  const nav = (extra: Record<string, string | number | undefined>) => go(`${base}/students?${gstQuery(f, extra)}`);
  const scope = [OFFICE_WORD[o], data.session, data.semester ? `Semester ${data.semester}` : "Whole session", f.fac, f.dept, f.prog, f.level ? `${f.level} Level` : null,
    f.payment ? `Payment: ${f.payment.replace("_", " ").toLowerCase()}` : null, f.registration ? `${word} ${f.registration.replace("_", " ").toLowerCase()}` : null, f.course ? `Course ${f.course}` : null,
    f.eligibility ? ELIGIBILITY_WORD[f.eligibility] ?? f.eligibility : null, filters.q ? `search “${filters.q}”` : null]
    .filter(Boolean).join(" · ");

  const HEAD = ["S/N", "Matric Number", "Name", "Gender", "Faculty", "Department", "Programme", "Level", "Session", `${word} Required`, "Reason", `${word} Courses Owed`, "GST Fee (₦)", "GST Payment", "Paid (₦)", "Payment Date", "Reference", "GST Registration", "EPS Registration", `${word} Courses`, "Result Status"];
  const resultWord = (r: GstStudentRow) => {
    if (!r.result_stages) return r.gst_registered || r.eps_registered ? "Pending" : "—";
    const stages = r.result_stages.split(", ");
    return stages.every((s) => s === "PUBLISHED") ? "Published" : stages.some((s) => s !== "ENTRY") ? "Submitted" : "Pending";
  };
  const line = (r: GstStudentRow, i: number) => [i + 1, r.number, `${r.surname}, ${r.other_names}`, r.sex ?? "", r.faculty, r.department, r.programme, r.level, data.session,
    r.office_required ? (r.office_carryover ? "Yes (carryover)" : "Yes") : "No", r.office_reason ?? "", r.office_owed ?? "",
    Number(r.fee), (PAY_WORD[r.pay_state]?.[0] ?? r.pay_state), Number(r.paid), r.paid_at ? dayOf(r.paid_at) : "", r.reference ?? "",
    r.gst_registered ? "Registered" : "Not registered", r.eps_registered ? "Registered" : "Not registered", r.registered_courses ?? "", resultWord(r)];

  async function allRows(): Promise<GstStudentRow[]> {
    const out: GstStudentRow[] = [];
    for (let page = 0; page * 500 < data.total && page < 200; page++) {
      const r = await fetch(`/api/bff/api/v1/gst/${o}/students?${gstQuery(f, { page, size: 500 })}`, { cache: "no-store" });
      if (!r.ok) throw (await r.json().catch(() => ({ status: r.status, title: r.statusText })));
      const j = (await r.json()) as GstStudentPage;
      out.push(...j.rows);
      if (j.rows.length < 500) break;
    }
    return out;
  }
  async function exportAs(kind: "xlsx" | "pdf") {
    setBusy(true);
    try {
      const rows = await allRows();
      const title = `${word} Students`;
      const body = rows.map(line);
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, HEAD, body, { sheetName: "Students", serial: docSerial(word), sub: scope }), `${word.toLowerCase()}-students-${data.session.replace("/", "-")}.xlsx`);
      else brandedPrint(title, scope, HEAD, body);
    } catch (e) {
      notifyProblem((e as { status?: number; title?: string }).status ? (e as { status: number; title: string }) : { status: 500, title: "The export could not be built" });
    } finally { setBusy(false); }
  }

  return (
    <>
      <PageHead title={`${word} students`} description={scope}
        actions={<span className="row row--inline row--tight"><LinkBtn kind="ghost" size="sm" href={`${base}/dashboard?${gstQuery(f)}`}>Dashboard</LinkBtn><Btn kind="secondary" size="sm" disabled={busy || !data.total} onClick={() => void exportAs("xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" disabled={busy || !data.total} onClick={() => void exportAs("pdf")}>PDF</Btn></span>} />
      <Panel title={`${num(data.total)} STUDENT${data.total === 1 ? "" : "S"} FOUND`} right={<span className="sub2">page {data.page + 1} of {pages}</span>}>
        <PBody>
          <form className="row row--inline row--tight" onSubmit={(e) => { e.preventDefault(); nav({ q, page: 0 }); }}>
            <Field id="gs-q" label="Search"><input id="gs-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Matric number, name, programme" /></Field>
            <Btn kind="secondary" size="sm" type="submit">Search</Btn>
            {filters.q ? <Btn kind="ghost" size="sm" onClick={() => { setQ(""); nav({ q: "", page: 0 }); }}>Clear</Btn> : null}
            <Field id="gs-elig" label="Students">
              <select id="gs-elig" className="ctl" value={f.eligibility ?? ""} onChange={(e) => nav({ eligibility: e.target.value, page: 0 })}>
                <option value="">Concerned: required, registered or paid</option>
                {(["REQUIRED", "CARRYOVER", "COMPLETED", "NOT_APPLICABLE", ...(eps ? [] : ["REVIEW"]), "ALL"] as const).map((k) => <option key={k} value={k}>{ELIGIBILITY_WORD[k]}</option>)}
              </select>
            </Field>
            <span className="grow" />
            <Btn kind="ghost" size="sm" disabled={data.page === 0} onClick={() => nav({ page: data.page - 1 })}>Previous</Btn>
            <Btn kind="ghost" size="sm" disabled={data.page + 1 >= pages} onClick={() => nav({ page: data.page + 1 })}>Next</Btn>
          </form>
        </PBody>
        {data.rows.length ? <DTable pageSize={50} cols={["S/N|num", "Student", "Programme", "Level|num", `${word} requirement`, "GST payment|mid", "GST|mid", "EPS|mid", `${word} courses`, "Result|mid", "|mid"]} rows={data.rows.map((r, i) => [
          <span key="n" className="tnum sub2">{data.page * data.size + i + 1}</span>,
          <span key="s"><b>{r.surname}, {r.other_names}</b><div className="sub2 tnum">{r.number}{r.sex ? ` · ${r.sex}` : ""} · {r.status.toLowerCase()}</div></span>,
          <span key="p">{r.programme}<div className="sub2">{r.faculty} · {r.department}</div></span>,
          <span key="l" className="tnum">{r.level}</span>,
          <span key="q"><Pil kind={r.office_required ? (r.office_carryover ? "warn" : "info") : "grey"}>{r.office_required ? (r.office_carryover ? "Carryover" : "Required") : r.review ? "Paid, not required" : "Not applicable"}</Pil>
            <div className="sub2">{r.office_owed ? `${r.office_owed} · ` : ""}{reasonWord(r.office_reason)}</div></span>,
          <span key="y"><Pil kind={(PAY_WORD[r.pay_state] ?? [r.pay_state, "grey"])[1]}>{(PAY_WORD[r.pay_state] ?? [r.pay_state])[0]}</Pil><div className="sub2 tnum">{r.stated ? `${naira(r.fee)}${r.paid_at ? ` · ${dayOf(r.paid_at)}` : ""}` : ""}</div></span>,
          <Pil key="g" kind={r.gst_registered ? "ok" : "grey"}>{r.gst_registered ? `Registered (${r.gst_courses})` : "Not registered"}</Pil>,
          <Pil key="e" kind={r.eps_registered ? "ok" : "grey"}>{r.eps_registered ? `Registered (${r.eps_courses})` : "Not registered"}</Pil>,
          <span key="c" className="tnum sub2">{r.registered_courses ?? "—"}</span>,
          <Pil key="r" kind={(STAGE_WORD[(r.result_stages ?? "").split(", ")[0]] ?? ["—", "grey"])[1]}>{resultWord(r)}</Pil>,
          <Btn key="w" kind="ghost" size="sm" onClick={() => void openWhy(r)}>View eligibility</Btn>,
        ])} /> : <PBody><Note kind="info" title={`No ${word} students found for the selected filters`}>Widen the filters or clear the search.</Note></PBody>}
      </Panel>
      {why ? (
        <Modal wide title={`Why ${why.row.surname}, ${why.row.other_names} ${why.row.office_required ? "owes" : "does not owe"} ${word}`} sub={`${data.session} · ${why.row.number}`} onClose={() => setWhy(null)}>
          {why.data ? <GstEligibilityView data={why.data} /> : <div className="sub2">Reading the eligibility…</div>}
        </Modal>
      ) : null}
    </>
  );
}
