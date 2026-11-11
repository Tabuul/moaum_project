"use client";

/** V721: the School of Postgraduate Studies' report of programme changes — every programme swap of a postgraduate student, whichever
 *  office made it: the student, the programme before and after, the level, the reason, who, when; filtered by state, session, dates
 *  and a search; Excel and print. The swap itself is made on the student edit page (V719). */
import { useRouter } from "next/navigation";
import { useState } from "react";
import Link from "next/link";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { day } from "@/lib/format";

const when = (iso: string | null | undefined) => (iso ? `${day(iso)} ${new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}` : "—");
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { KIND_WORDS, REPORT_HEADERS, STATUS_WORDS, reportRows, type Swap, type SwapStatus } from "@/lib/programme-swap";

interface Filters { status: string; session: string; q: string; fromDate: string; toDate: string }

const PIL: Record<SwapStatus, "ok" | "bad" | "warn" | "grey" | "info"> = { COMPLETED: "ok", FAILED: "bad", REJECTED: "bad", CANCELLED: "grey", PENDING_APPROVAL: "warn" };

export function PgProgrammeChanges({ rows, filters, generatedBy }: { rows: Swap[]; filters: Filters; generatedBy: string | null }) {
  const router = useRouter();
  const [f, setF] = useState(filters);
  const completed = rows.filter((r) => r.status === "COMPLETED");
  const bySchool = completed.filter((r) => r.prepared_office === "pgschool" || r.prepared_office === "pgsecretary");
  const sessions = [...new Set(rows.map((r) => r.effective_session))].sort().reverse();
  const title = "Postgraduate programme changes";
  const scope = [f.session ? `session ${f.session}` : "every session", f.status ? STATUS_WORDS[f.status as SwapStatus] ?? f.status : "every state", f.q ? `"${f.q}"` : ""].filter(Boolean).join(" · ");
  const apply = () => {
    const u = new URLSearchParams();
    for (const [k, v] of Object.entries(f)) if (v) u.set(k, v);
    router.push(`/admissions/postgraduate/programme-changes${u.toString() ? `?${u.toString()}` : ""}`);
  };
  return (
    <>
      <Note kind="info" title="Postgraduate students' programme changes">
        Every programme swap of a postgraduate student, whichever office made it — the School on the student edit page (V719), the Academic Office, the Registry or
        the Director of ICT. A completed swap moved the student and carried the admission record with it; the reason, the officer and the time are the swap&rsquo;s own.
      </Note>
      <Tiles cls="grid--4" items={[
        ["Changes listed", String(rows.length), null, scope],
        ["Completed", String(completed.length), "var(--green-ink)", "The student moved"],
        ["Made by the School", String(bySchool.length), null, "On the student edit page"],
        ["Not completed", String(rows.length - completed.length), rows.length - completed.length ? "var(--red-ink)" : null, "Failed, rejected or cancelled"],
      ]} />
      <Panel title="Find" right={<span className="sub2">The filters are in the address, so the list can be shared</span>}>
        <PBody>
          <div className="grid grid--4">
            <Field id="pc-q" label="Student, number or programme"><input id="pc-q" className="ctl" value={f.q} onChange={(e) => setF({ ...f, q: e.target.value })} onKeyDown={(e) => { if (e.key === "Enter") apply(); }} /></Field>
            <Field id="pc-session" label="Effective session">
              <select id="pc-session" className="ctl" value={f.session} onChange={(e) => setF({ ...f, session: e.target.value })}>
                <option value="">Every session</option>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </Field>
            <Field id="pc-status" label="State">
              <select id="pc-status" className="ctl" value={f.status} onChange={(e) => setF({ ...f, status: e.target.value })}>
                <option value="">Every state</option>{(Object.keys(STATUS_WORDS) as SwapStatus[]).map((s) => <option key={s} value={s}>{STATUS_WORDS[s]}</option>)}
              </select>
            </Field>
            <div className="grid grid--2">
              <Field id="pc-from" label="From"><input id="pc-from" type="date" className="ctl" value={f.fromDate} onChange={(e) => setF({ ...f, fromDate: e.target.value })} /></Field>
              <Field id="pc-to" label="To"><input id="pc-to" type="date" className="ctl" value={f.toDate} onChange={(e) => setF({ ...f, toDate: e.target.value })} /></Field>
            </div>
          </div>
          <div className="row mt-2">
            <Btn kind="primary" onClick={apply}>Show</Btn>
            <Btn kind="ghost" onClick={() => { setF({ status: "", session: "", q: "", fromDate: "", toDate: "" }); router.push("/admissions/postgraduate/programme-changes"); }}>Clear</Btn>
          </div>
        </PBody>
      </Panel>
      <Panel title="Programme changes" right={<span className="sub2">{rows.length} listed, newest first · read from the latest 5,000 swaps of the University</span>}>
        {!rows.length ? <PBody><Note kind="info" title="No programme change listed">No postgraduate student&rsquo;s programme has been changed by a swap under these filters.</Note></PBody> : (
          <>
            <DTable pageSize={50} cols={["Date|mid", "Reference|mid", "Student", "From", "To", "Level|mid", "Session|mid", "Reason", "Made by", "State|mid"]} rows={rows.map((r) => [
              <span key="d" className="tnum">{when(r.executed_at ?? r.decided_at ?? r.prepared_at)}</span>,
              <span key="ref" className="tnum">{r.swap_ref}</span>,
              <span key="s"><Link href={`/students/${r.student_id}/edit?section=placement`}><b>{r.student}</b></Link><div className="sub2 tnum">{r.matric_no ?? r.jamb_reg_no ?? "—"}</div></span>,
              <span key="f">{r.from_programme_name ?? r.from_programme}<div className="sub2">{r.from_department ?? r.from_dept ?? ""}</div></span>,
              <span key="t">{r.to_programme_name ?? r.to_programme}<div className="sub2">{r.to_department ?? r.to_dept ?? ""}</div></span>,
              <span key="l" className="tnum">{r.from_level ?? "—"} → {r.to_level}</span>,
              <span key="ses" className="tnum">{r.effective_session}</span>,
              <span key="w" className="sub2">{r.reason}<div className="sub2">{KIND_WORDS[r.kind] ?? r.kind}</div></span>,
              <span key="by">{r.prepared_by ?? "—"}<div className="sub2">{r.prepared_office}</div></span>,
              <Pil key="st" kind={PIL[r.status] ?? "grey"}>{STATUS_WORDS[r.status] ?? r.status}</Pil>,
            ])} texts={rows.map((r) => `${r.swap_ref} ${r.student} ${r.matric_no ?? ""} ${r.from_programme_name ?? ""} ${r.to_programme_name ?? ""} ${r.reason} ${r.prepared_by ?? ""}`)} />
            <PBody>
              <div className="row row--inline row--tight">
                <Btn kind="ghost" onClick={async () => {
                  const meta = [["Scope", scope], ["Generated by", generatedBy ?? "—"]] as [string, string][];
                  downloadBlob(await brandedXlsx(title, REPORT_HEADERS, reportRows(rows), { sheetName: "Programme changes", serial: docSerial("PGC"), sub: scope, meta }), "postgraduate-programme-changes.xlsx");
                }}>Excel</Btn>
                <Btn kind="ghost" onClick={() => brandedPrint(title, scope, REPORT_HEADERS, reportRows(rows), docSerial("PGC"), { meta: [["Scope", scope], ["Generated by", generatedBy ?? "—"]], generatedBy, orientation: "landscape" })}>Print</Btn>
              </div>
            </PBody>
          </>
        )}
      </Panel>
    </>
  );
}
