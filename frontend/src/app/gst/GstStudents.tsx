"use client";
/** The students behind a GST or EPS figure (V314): the same rows the dashboard counted, paged fifty at a time, searched on the
 *  server, and the whole set as a branded Excel workbook or PDF with S/N first and names A–Z. S/N is display only.
 *  V366: each student with the office's own answer — whether its courses concern them and why — the lists of carryovers, of the
 *  students no course concerns, of payments no course requires, and "View eligibility" for the whole answer.
 *  V691: and the students with a GST/EPS course registered while the GST fee is unpaid — what each owes, what the list comes to, and
 *  a reminder to pay, sent to every student of the list (each told at most once a day). */
import { useState } from "react";
import { KeptAt } from "./KeptAt";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { GstEligibilityView } from "@/components/gst/GstEligibilityView";
import { reasonHeader } from "@/lib/reason";
import { ELIGIBILITY_WORD, OFFICE_WORD, PAY_WORD, STAGE_WORD, dayOf, gstQuery, mayRemind, naira, num, reasonWord, remindWords, type GstEpsExplain, type GstFilters, type GstStudentPage, type GstStudentRow, type RemindAnswer } from "@/lib/gst";

export function GstStudents({ data, filters, base, path = "students", actingOffice = null }: {
  data: GstStudentPage; filters: GstFilters; base: string;
  /** V691: the page the list lives on under base ("students", or "unpaid" for the GST fee unpaid list) */
  path?: string;
  /** V691: the acting office: the GST or EPS office, the Bursary or super may remind the unpaid list */
  actingOffice?: string | null;
}) {
  const go = useQueryNav();
  const o = data.office;
  const eps = o === "EPS";
  const word = eps ? "EPS" : "GST";
  const [q, setQ] = useState(filters.q ?? "");
  const [busy, setBusy] = useState(false);
  const [why, setWhy] = useState<{ row: GstStudentRow; data: GstEpsExplain | null } | null>(null);
  const [asking, setAsking] = useState(false);
  const [reminded, setReminded] = useState<ReturnType<typeof remindWords> | null>(null);
  const f: GstFilters = { ...filters, session: data.session, semester: data.semester == null ? "" : String(data.semester) };
  async function openWhy(row: GstStudentRow) {
    setWhy({ row, data: null });
    const r = await fetch(`/api/bff/api/v1/gst/${o}/students/${row.student_id}?session=${encodeURIComponent(data.session)}`, { cache: "no-store" }).catch(() => null);
    const j = r ? await r.json().catch(() => null) : null;
    if (!r || !r.ok || !j?.explain) { notifyProblem((j as { status: number; title: string }) ?? { status: 503, title: "The eligibility could not be read just now." }); setWhy(null); return; }
    setWhy({ row, data: j.explain as GstEpsExplain });
  }
  const pages = Math.max(1, Math.ceil(data.total / data.size));
  const nav = (extra: Record<string, string | number | undefined>) => go(`${base}/${path}?${gstQuery(f, extra)}`);
  const unpaidList = f.eligibility === "UNPAID_REGISTERED";
  const scope = [OFFICE_WORD[o], data.session, data.semester ? `Semester ${data.semester}` : "Whole session", f.fac, f.dept, f.prog, f.level ? `${f.level} Level` : null,
    f.payment ? `Payment: ${f.payment.replace("_", " ").toLowerCase()}` : null, f.registration ? `${word} ${f.registration.replace("_", " ").toLowerCase()}` : null, f.course ? `Course ${f.course}` : null,
    f.eligibility ? ELIGIBILITY_WORD[f.eligibility] ?? f.eligibility : null, filters.q ? `search “${filters.q}”` : null]
    .filter(Boolean).join(" · ");

  const HEAD = ["S/N", "Matric Number", "Name", "Gender", "Faculty", "Department", "Programme", "Level", "Session", `${word} Required`, "Reason", `${word} Courses Owed`, "GST Fee (₦)", "GST Payment", "Paid (₦)", "Owed (₦)", "Payment Date", "Reference", "GST Registration", "EPS Registration", `${word} Courses`, "Result Status"];
  const resultWord = (r: GstStudentRow) => {
    if (!r.result_stages) return r.gst_registered || r.eps_registered ? "Pending" : "—";
    const stages = r.result_stages.split(", ");
    return stages.every((s) => s === "PUBLISHED") ? "Published" : stages.some((s) => s !== "ENTRY") ? "Submitted" : "Pending";
  };
  const line = (r: GstStudentRow, i: number) => [i + 1, r.number, `${r.surname}, ${r.other_names}`, r.sex ?? "", r.faculty, r.department, r.programme, r.level, data.session,
    r.office_required ? (r.office_carryover ? "Yes (carryover)" : "Yes") : "No", r.office_reason ?? "", r.office_owed ?? "",
    Number(r.fee), (PAY_WORD[r.pay_state]?.[0] ?? r.pay_state), Number(r.paid), Number(r.owed ?? 0), r.paid_at ? dayOf(r.paid_at) : "", r.reference ?? "",
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
      const title = unpaidList ? `${word} Students — Registered, GST Fee Unpaid` : `${word} Students`;
      const body = rows.map(line);
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, HEAD, body, { sheetName: "Students", serial: docSerial(word), sub: scope }), `${word.toLowerCase()}-${unpaidList ? "fee-unpaid" : "students"}-${data.session.replace("/", "-")}.xlsx`);
      else brandedPrint(title, scope, HEAD, body);
    } catch (e) {
      notifyProblem((e as { status?: number; title?: string }).status ? (e as { status: number; title: string }) : { status: 500, title: "The export could not be built" });
    } finally { setBusy(false); }
  }
  /** V691: every student of the list reminded to pay the GST fee, up to 5,000 a call; each is checked again and told at most once a day */
  async function remind() {
    setBusy(true);
    try {
      const ids = (await allRows()).map((r) => r.student_id);
      const answers: RemindAnswer[] = [];
      for (let i = 0; i < ids.length; i += 5000) {
        const chunk = ids.slice(i, i + 5000);
        const r = await fetch(`/api/bff/api/v1/gst/${o}/students/remind`, {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`GST fee reminder to ${chunk.length} student${chunk.length === 1 ? "" : "s"} registered without paying (${data.session})`) },
          body: JSON.stringify({ session: data.session, students: chunk }),
        });
        const j = await r.json().catch(() => null);
        if (!r.ok) throw (j ?? { status: r.status, title: "The reminder could not be sent" });
        answers.push(j as RemindAnswer);
      }
      const w = remindWords(answers);
      setReminded(w);
      notify(w.title, w.kind === "bad" ? "bad" : undefined);
      setAsking(false);
    } catch (e) {
      notifyProblem((e as { status?: number; title?: string }).status ? (e as { status: number; title: string }) : { status: 500, title: "The reminder could not be sent" });
    } finally { setBusy(false); }
  }

  return (
    <>
      <PageHead title={unpaidList ? `${word} fee unpaid` : `${word} students`} description={scope}
        actions={<span className="row row--inline row--tight"><LinkBtn kind="ghost" size="sm" href={`${base}/dashboard?${gstQuery(f)}`}>Dashboard</LinkBtn><Btn kind="secondary" size="sm" disabled={busy || !data.total} onClick={() => void exportAs("xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" disabled={busy || !data.total} onClick={() => void exportAs("pdf")}>PDF</Btn></span>} />
      {unpaidList ? (
        <Note kind={data.total ? "bad" : "ok"} title={data.total
          ? `${num(data.total)} student${data.total === 1 ? " has" : "s have"} ${eps ? "an EPS" : "a GST or EPS"} course registered without the GST fee paid${Number(data.owedTotal) ? ` — ${naira(Number(data.owedTotal))} in all` : ""}`
          : `Every student with ${eps ? "an EPS" : "a GST or EPS"} course registered has paid the GST fee`}
          action={data.total && mayRemind(actingOffice, o) ? <Btn kind="primary" size="sm" disabled={busy} onClick={() => { setReminded(null); setAsking(true); }}>Send reminder</Btn> : undefined}>
          {data.total ? "The registration makes the fee owed: their examination card and GST & EPS permit wait for it. One payment covers GST and EPS. Excel lists each student with the amount." : "Nothing to remind."}
          {reminded ? <div className="mt-1 b600">Last reminder: {reminded.title}.</div> : null}
        </Note>
      ) : null}
      <Panel title={`${num(data.total)} STUDENT${data.total === 1 ? "" : "S"} FOUND`} right={<span className="row row--inline row--tight"><KeptAt at={data.keptAt} /><span className="sub2">page {data.page + 1} of {pages}</span></span>}>
        <PBody>
          <form className="row row--inline row--tight" onSubmit={(e) => { e.preventDefault(); nav({ q, page: 0 }); }}>
            <Field id="gs-q" label="Search"><input id="gs-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Matric number, name, programme" /></Field>
            <Btn kind="secondary" size="sm" type="submit">Search</Btn>
            {filters.q ? <Btn kind="ghost" size="sm" onClick={() => { setQ(""); nav({ q: "", page: 0 }); }}>Clear</Btn> : null}
            <Field id="gs-elig" label="Students">
              <select id="gs-elig" className="ctl" value={f.eligibility ?? ""} onChange={(e) => nav({ eligibility: e.target.value, page: 0 })}>
                <option value="">Concerned: required, registered or paid</option>
                {(["REQUIRED", "CARRYOVER", "COMPLETED", "NOT_APPLICABLE", ...(eps ? [] : ["REVIEW"]), "UNPAID_REGISTERED", "ALL"] as const).map((k) => <option key={k} value={k}>{ELIGIBILITY_WORD[k]}</option>)}
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
          <span key="y"><Pil kind={(PAY_WORD[r.pay_state] ?? [r.pay_state, "grey"])[1]}>{(PAY_WORD[r.pay_state] ?? [r.pay_state])[0]}</Pil><div className="sub2 tnum">{r.stated ? `${naira(r.fee)}${r.paid_at ? ` · ${dayOf(r.paid_at)}` : ""}` : ""}</div>
            {Number(r.owed) > 0 ? <div className="sub2 tnum b600" style={{ color: "var(--red-deep)" }}>{naira(Number(r.owed))} owed</div> : null}</span>,
          <Pil key="g" kind={r.gst_registered ? "ok" : "grey"}>{r.gst_registered ? `Registered (${r.gst_courses})` : "Not registered"}</Pil>,
          <Pil key="e" kind={r.eps_registered ? "ok" : "grey"}>{r.eps_registered ? `Registered (${r.eps_courses})` : "Not registered"}</Pil>,
          <span key="c" className="tnum sub2">{r.registered_courses ?? "—"}</span>,
          <Pil key="r" kind={(STAGE_WORD[(r.result_stages ?? "").split(", ")[0]] ?? ["—", "grey"])[1]}>{resultWord(r)}</Pil>,
          <Btn key="w" kind="ghost" size="sm" onClick={() => void openWhy(r)}>View eligibility</Btn>,
        ])} /> : <PBody><Note kind="info" title={`No ${word} students found for the selected filters`}>Widen the filters or clear the search.</Note></PBody>}
      </Panel>
      {asking ? (
        <Modal title="Send the GST fee reminder" sub={`${data.session} · ${scope}`} onClose={() => { if (!busy) setAsking(false); }}
          foot={<><Btn kind="ghost" disabled={busy} onClick={() => setAsking(false)}>Cancel</Btn><Btn kind="primary" busy={busy} busyLabel="Sending..." onClick={() => void remind()}>Remind {num(data.total)} student{data.total === 1 ? "" : "s"}</Btn></>}>
          <p>Each student on this list is told by email, SMS and on their portal which GST or EPS course is on their registration and the GST fee to pay{Number(data.owedTotal) ? ` (${naira(Number(data.owedTotal))} across the list)` : ""}.</p>
          <p className="sub2">Each is checked again first: a student who has paid since, has no such course registered now, or was reminded today is passed over. Every reminder is written down.</p>
        </Modal>
      ) : null}
      {why ? (
        <Modal wide title={`Why ${why.row.surname}, ${why.row.other_names} ${why.row.office_required ? "owes" : "does not owe"} ${word}`} sub={`${data.session} · ${why.row.number}`} onClose={() => setWhy(null)}>
          {why.data ? <GstEligibilityView data={why.data} /> : <div className="sub2">Reading the eligibility…</div>}
        </Modal>
      ) : null}
    </>
  );
}
