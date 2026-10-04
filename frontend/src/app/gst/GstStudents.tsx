"use client";
/** The students behind a GST or EPS figure (V314): the same rows the dashboard counted, paged fifty at a time, searched on the
 *  server, and the whole set as a branded Excel workbook or PDF with S/N first and names A–Z. S/N is display only. */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { OFFICE_WORD, PAY_WORD, STAGE_WORD, dayOf, gstQuery, naira, num, type GstFilters, type GstStudentPage, type GstStudentRow } from "@/lib/gst";

export function GstStudents({ data, filters, base }: { data: GstStudentPage; filters: GstFilters; base: string }) {
  const go = useQueryNav();
  const o = data.office;
  const eps = o === "EPS";
  const word = eps ? "EPS" : "GST";
  const [q, setQ] = useState(filters.q ?? "");
  const [busy, setBusy] = useState(false);
  const f: GstFilters = { ...filters, session: data.session, semester: data.semester == null ? "" : String(data.semester) };
  const pages = Math.max(1, Math.ceil(data.total / data.size));
  const nav = (extra: Record<string, string | number | undefined>) => go(`${base}/students?${gstQuery(f, extra)}`);
  const scope = [OFFICE_WORD[o], data.session, data.semester ? `Semester ${data.semester}` : "Whole session", f.fac, f.dept, f.prog, f.level ? `${f.level} Level` : null,
    f.payment ? `Payment: ${f.payment.replace("_", " ").toLowerCase()}` : null, f.registration ? `${word} ${f.registration.replace("_", " ").toLowerCase()}` : null, f.course ? `Course ${f.course}` : null, filters.q ? `search “${filters.q}”` : null]
    .filter(Boolean).join(" · ");

  const HEAD = ["S/N", "Matric Number", "Name", "Gender", "Faculty", "Department", "Programme", "Level", "Session", "GST Fee (₦)", "GST Payment", "Paid (₦)", "Payment Date", "Reference", "GST Registration", "EPS Registration", `${word} Courses`, "Result Status"];
  const resultWord = (r: GstStudentRow) => {
    if (!r.result_stages) return r.gst_registered || r.eps_registered ? "Pending" : "—";
    const stages = r.result_stages.split(", ");
    return stages.every((s) => s === "PUBLISHED") ? "Published" : stages.some((s) => s !== "ENTRY") ? "Submitted" : "Pending";
  };
  const line = (r: GstStudentRow, i: number) => [i + 1, r.number, `${r.surname}, ${r.other_names}`, r.sex ?? "", r.faculty, r.department, r.programme, r.level, data.session,
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
      <PageHead title={`${word} Students`} description={scope}
        actions={<span className="row row--inline row--tight"><LinkBtn kind="ghost" size="sm" href={`${base}/dashboard?${gstQuery(f)}`}>Dashboard</LinkBtn><Btn kind="secondary" size="sm" disabled={busy || !data.total} onClick={() => void exportAs("xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" disabled={busy || !data.total} onClick={() => void exportAs("pdf")}>PDF</Btn></span>} />
      <Panel title={`${num(data.total)} STUDENT${data.total === 1 ? "" : "S"} FOUND`} right={<span className="sub2">page {data.page + 1} of {pages}</span>}>
        <PBody>
          <form className="row row--inline row--tight" onSubmit={(e) => { e.preventDefault(); nav({ q, page: 0 }); }}>
            <Field id="gs-q" label="Search"><input id="gs-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Matric number, name, programme" /></Field>
            <Btn kind="secondary" size="sm" type="submit">Search</Btn>
            {filters.q ? <Btn kind="ghost" size="sm" onClick={() => { setQ(""); nav({ q: "", page: 0 }); }}>Clear</Btn> : null}
            <span className="grow" />
            <Btn kind="ghost" size="sm" disabled={data.page === 0} onClick={() => nav({ page: data.page - 1 })}>Previous</Btn>
            <Btn kind="ghost" size="sm" disabled={data.page + 1 >= pages} onClick={() => nav({ page: data.page + 1 })}>Next</Btn>
          </form>
        </PBody>
        {data.rows.length ? <DTable pageSize={50} cols={["S/N|num", "Student", "Programme", "Level|num", "GST payment|mid", "GST|mid", "EPS|mid", `${word} courses`, "Result|mid"]} rows={data.rows.map((r, i) => [
          <span key="n" className="tnum sub2">{data.page * data.size + i + 1}</span>,
          <span key="s"><b>{r.surname}, {r.other_names}</b><div className="sub2 tnum">{r.number}{r.sex ? ` · ${r.sex}` : ""} · {r.status.toLowerCase()}</div></span>,
          <span key="p">{r.programme}<div className="sub2">{r.faculty} · {r.department}</div></span>,
          <span key="l" className="tnum">{r.level}</span>,
          <span key="y"><Pil kind={(PAY_WORD[r.pay_state] ?? [r.pay_state, "grey"])[1]}>{(PAY_WORD[r.pay_state] ?? [r.pay_state])[0]}</Pil><div className="sub2 tnum">{r.stated ? `${naira(r.fee)}${r.paid_at ? ` · ${dayOf(r.paid_at)}` : ""}` : ""}</div></span>,
          <Pil key="g" kind={r.gst_registered ? "ok" : "grey"}>{r.gst_registered ? `Registered (${r.gst_courses})` : "Not registered"}</Pil>,
          <Pil key="e" kind={r.eps_registered ? "ok" : "grey"}>{r.eps_registered ? `Registered (${r.eps_courses})` : "Not registered"}</Pil>,
          <span key="c" className="tnum sub2">{r.registered_courses ?? "—"}</span>,
          <Pil key="r" kind={(STAGE_WORD[(r.result_stages ?? "").split(", ")[0]] ?? ["—", "grey"])[1]}>{resultWord(r)}</Pil>,
        ])} /> : <PBody><Note kind="info" title={`No ${word} students found for the selected filters`}>Widen the filters or clear the search.</Note></PBody>}
      </Panel>
    </>
  );
}
