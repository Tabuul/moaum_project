"use client";

/**
 * Overload requests (V508): the students who ask for a higher maximum course load in a semester, with their reason; the Head of
 * Department of the student's department grants a ceiling (the semester's maximum for every check) or refuses, with a reason; the
 * Dean reads the faculty's, the Academic Office and the Registry everyone's, and set the rule (whether students ask, how far above
 * the maximum a grant may go). The server decides it all.
 */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { semesterWord } from "@/lib/registration-approval";
import { OVERLOAD_STATUSES, statusLabel, unitChoices, type OverloadList, type OverloadRow } from "@/lib/overloads";

const vz = (n: number | null | undefined) => Number(n ?? 0).toLocaleString("en-GB");
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export function Overloads({ o, status, q, mayDecide, maySetRule }: { o: OverloadList; status: string; q: string; mayDecide: boolean; maySetRule: boolean }) {
  const router = useRouter();
  const go = useQueryNav();
  const nav = (patch: Record<string, string | number | null>) => {
    const next: Record<string, string> = { session: o.session, semester: o.semester ? String(o.semester) : "", status, q, page: "0" };
    for (const [k, v] of Object.entries(patch)) next[k] = v == null ? "" : String(v);
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "page" && v === "0")) qs.set(k, v);
    go(`/registration/overloads?${qs.toString()}`);
  };
  const [search, setSearch] = useState(q);
  const [deciding, setDeciding] = useState<{ row: OverloadRow; decision: "GRANTED" | "REFUSED" } | null>(null);
  const [units, setUnits] = useState<number | null>(null);
  const [reason, setReason] = useState("");
  const [rule, setRule] = useState({ open: o.rule.open, extra: o.rule.max_extra, reason: "" });
  const pages = Math.max(1, Math.ceil(o.total / o.size));
  const sub = `${o.session}${o.semester ? ` · ${semesterWord(o.semester)}` : ""}`;
  const ruleChanged = rule.open !== o.rule.open || rule.extra !== o.rule.max_extra;

  const HEAD = ["S/N", "Student", "Matriculation No.", "Programme", "Department", "Level", "Semester", "Maximum", "Asked", "Granted", "Units now", "Reason", "Status", "Decision"];
  async function allRows(): Promise<(string | number)[][] | null> {
    const qs = new URLSearchParams({ session: o.session, page: "0", size: "5000" });
    if (o.semester) qs.set("semester", String(o.semester));
    if (status) qs.set("status", status);
    if (q) qs.set("q", q);
    const r = await fetch(`/api/bff/api/v1/registration/overloads?${qs.toString()}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
    return (j.rows as OverloadRow[]).map((x, i) => [i + 1, x.full_name, x.matric_no ?? "", x.programme ?? "", x.dept_code ?? "", x.level, x.semester, x.regular_max,
      x.requested_max, x.granted_max ?? "", x.units ?? "", x.reason, statusLabel(x.status), x.decision_reason ?? ""]);
  }

  async function decide() {
    if (!deciding) return;
    const { row, decision } = deciding;
    const r = await fetch(`/api/bff/api/v1/registration/overloads/${row.id}/decide`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Overload ${decision === "GRANTED" ? "granted" : "refused"}: ${reason.trim()}`) },
      body: JSON.stringify({ decision, units: decision === "GRANTED" ? units : null, reason: reason.trim() }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setDeciding(null);
    notify(decision === "GRANTED" ? `Granted: up to ${units} credit units. The student is told.` : "Refused. The student is told.");
    router.refresh();
  }

  async function saveRule() {
    const r = await fetch("/api/bff/api/v1/registration/overloads/rule", {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Overload rule set: ${rule.reason.trim()}`) },
      body: JSON.stringify({ open: rule.open, maxExtra: rule.extra, reason: rule.reason.trim() }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    notify("Saved");
    setRule({ ...rule, reason: "" });
    router.refresh();
  }

  return (
    <>
      <PageHead title="Overload requests" eyebrow="Course registration"
        description={`A student who needs more than the maximum course load in a semester asks here; the Head of Department of the student's department grants a ceiling, at most ${o.rule.max_extra} credit units above the maximum, or refuses. A grant is the semester's maximum for the submission, add and drop and every other check.`} />

      <div className="row" style={{ flexWrap: "wrap", gap: 12, alignItems: "flex-end" }}>
        <Field id="ov-session" label="Academic session"><select id="ov-session" className="ctl" value={o.session} onChange={(e) => nav({ session: e.target.value })}>
          {(o.sessions.includes(o.session) ? o.sessions : [o.session, ...o.sessions]).map((s) => <option key={s} value={s}>{s}{s === o.current ? " (current)" : ""}</option>)}
        </select></Field>
        <Field id="ov-semester" label="Semester"><select id="ov-semester" className="ctl" value={o.semester ? String(o.semester) : ""} onChange={(e) => nav({ semester: e.target.value || null })}>
          <option value="">All semesters</option><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option>
        </select></Field>
        <form className="row row--inline" style={{ gap: 8 }} onSubmit={(e) => { e.preventDefault(); nav({ q: search.trim() }); }}>
          <input className="ctl" aria-label="Search by name or matriculation number" placeholder="Name or matriculation number" value={search} onChange={(e) => setSearch(e.target.value)} />
          <Btn kind="ghost" type="submit">Search</Btn>
        </form>
        <span className="grow" />
        {o.dept ? <span className="sub2">Department <b>{o.dept}</b></span> : o.faculty ? <span className="sub2">Faculty <b>{o.faculty}</b></span> : null}
      </div>

      <div className="grid grid--4" role="group" aria-label="Overload requests, by status">
        {OVERLOAD_STATUSES.map((x) => (
          <button key={x.status} type="button" className="tile stat-tile" aria-pressed={status === x.status} onClick={() => nav({ status: status === x.status ? null : x.status })}
            style={{ textAlign: "left", font: "inherit", border: status === x.status ? "2px solid var(--chrome)" : undefined }}>
            <div className="eyebrow">{x.label}</div>
            <div className="n tnum" style={x.status === "REQUESTED" && o.counts.REQUESTED ? { color: "var(--red-ink)" } : undefined}>{vz(o.counts[x.status])}</div>
            <div className="c">{x.who}</div>
          </button>
        ))}
      </div>

      {o.noHead ? (
        <Note kind="bad" title={`${vz(o.noHead)} waiting request${o.noHead === 1 ? " is" : "s are"} in a department with no Head of Department on the portal`}>
          Only the Head of the student&rsquo;s department grants or refuses an overload, so {o.noHead === 1 ? "it waits" : "they wait"} until the Head is given the office on Users &amp; roles (the Directorate of ICT). The Academic Office is told each morning while any waits; the Head is reminded of a request waiting three days or more.
        </Note>
      ) : null}
      {!o.rule.open ? <Note kind="info" title="Overload requests are closed">Students cannot ask until the Academic Office opens them again. Requests already made can still be decided.</Note> : null}

      <Panel title={status ? statusLabel(status) : "Every request"} right={`${vz(o.total)}${pages > 1 ? ` · page ${o.page + 1} of ${pages}` : ""}`}>
        <PBody>
          <div className="row row--between" style={{ flexWrap: "wrap", gap: 8 }}>
            <span className="sub2">{mayDecide ? "Grant or refuse each waiting request; the student is told either way." : "Granted or refused by the Head of Department of the student's department."}</span>
            <span className="row row--inline row--tight">
              <Btn kind="secondary" size="sm" disabled={!o.total} onClick={async () => { const rows = await allRows(); if (rows) downloadBlob(await brandedXlsx("Overload Requests", HEAD, rows, { sheetName: "Overloads", serial: docSerial("OVL"), sub }), "overload-requests.xlsx"); }}>Excel</Btn>
              <Btn kind="ghost" size="sm" disabled={!o.total} onClick={async () => { const rows = await allRows(); if (rows) brandedPrint("Overload Requests", sub, HEAD, rows, docSerial("OVL")); }}>PDF</Btn>
            </span>
          </div>
        </PBody>
        {o.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Level|mid", "Semester|mid", "Maximum|num", "Asked|num", "Granted|num", "Units now|num", "Reason", "Status", ""]}
            rows={o.rows.map((r, i) => [
              <span key="n" className="tnum sub2">{o.page * o.size + i + 1}</span>,
              <span key="s"><Link className="lnk" href={`/students/${r.student_id}`}>{r.full_name}</Link><div className="sub2 tnum">{r.matric_no ?? ""}</div></span>,
              <span key="p" className="sub2">{r.programme ?? "—"}<div>{r.dept_code ?? ""}</div></span>,
              <span key="l" className="tnum">{r.level}</span>,
              <span key="m" className="tnum">{r.semester}</span>,
              <span key="x" className="tnum">{r.regular_max}</span>,
              <span key="a" className="tnum b600">{r.requested_max}</span>,
              <span key="g" className="tnum">{r.granted_max ?? "—"}</span>,
              <span key="u" className="tnum">{r.units ?? "—"}</span>,
              <span key="r" className="sub2" style={{ maxWidth: 320, display: "inline-block" }}>{r.reason}{r.decision_reason ? <div><b>Decision:</b> {r.decision_reason}{r.decided_by ? ` (${r.decided_by}, ${day(r.decided_at)})` : ""}</div> : null}</span>,
              <span key="t" className="stack" style={{ gap: 2 }}>
                <Pil kind={r.status === "GRANTED" ? "ok" : r.status === "REFUSED" ? "bad" : r.status === "REQUESTED" ? "warn" : "grey"}>{statusLabel(r.status)}</Pil>
                {r.status === "REQUESTED" && r.has_head === false ? <span className="sub2 ink-red">No Head on the portal</span> : null}
              </span>,
              mayDecide && r.status === "REQUESTED"
                ? <span key="d" className="row row--inline row--tight">
                    <Btn kind="ghost" size="sm" onClick={() => { setReason(""); setUnits(r.requested_max); setDeciding({ row: r, decision: "GRANTED" }); }}>Grant</Btn>
                    <Btn kind="ghost" size="sm" onClick={() => { setReason(""); setDeciding({ row: r, decision: "REFUSED" }); }}>Refuse</Btn>
                  </span>
                : <span key="d" />,
            ])} />
        ) : <PBody><div className="sub2">None.</div></PBody>}
        {pages > 1 ? (
          <PBody><div className="row row--between">
            <Btn kind="ghost" disabled={o.page === 0} onClick={() => nav({ page: o.page - 1 })}>Previous</Btn>
            <Btn kind="ghost" disabled={o.page + 1 >= pages} onClick={() => nav({ page: o.page + 1 })}>Next</Btn>
          </div></PBody>
        ) : null}
      </Panel>

      <Panel title="The rule" right={<Pil kind={o.rule.open ? "ok" : "grey"}>{o.rule.open ? "Students may ask" : "Closed"}</Pil>}>
        <PBody>
          <div className="grid grid--2">
            <div className="kv"><span className="k">Students may ask for an overload</span><span className="v">{o.rule.open ? "Yes" : "No"}</span></div>
            <div className="kv"><span className="k">Most a grant goes above the maximum</span><span className="v tnum">{o.rule.max_extra} credit units</span></div>
            <div className="kv"><span className="k">Set</span><span className="v">{o.rule.set_by ?? "—"}{o.rule.set_office ? ` (${o.rule.set_office})` : ""} · {day(o.rule.set_at)}<div className="sub2">{o.rule.reason}</div></span></div>
          </div>
          <div className="sub2 mt-2">A student on probation registers within the probation limit and does not ask; the industrial-training (SIWES) semester carries the SIWES course alone.</div>
          {maySetRule ? (
            <div className="stack mt-2" style={{ maxWidth: 560 }}>
              <label className="row row--inline row--tight"><input type="checkbox" className="chk" checked={rule.open} onChange={(e) => setRule({ ...rule, open: e.target.checked })} /> Students may ask for an overload</label>
              <Field id="ov-extra" label="Most a grant goes above the maximum (credit units)">
                <select id="ov-extra" className="ctl" value={rule.extra} onChange={(e) => setRule({ ...rule, extra: Number(e.target.value) })}>
                  {Array.from({ length: 12 }, (_, i) => i + 1).map((n) => <option key={n} value={n}>{n}</option>)}
                </select>
              </Field>
              <Field id="ov-rule-reason" label="Reason" required hint="Ten characters or more; kept on the audit trail">
                <input id="ov-rule-reason" className="ctl" value={rule.reason} maxLength={500} onChange={(e) => setRule({ ...rule, reason: e.target.value })} placeholder="e.g. Senate allows final-year students up to six units more" />
              </Field>
              <div><Btn kind="primary" disabled={!ruleChanged || rule.reason.trim().length < 10} busyLabel="Saving…" onClick={() => saveRule()}>Save the rule</Btn></div>
            </div>
          ) : null}
        </PBody>
      </Panel>

      {deciding ? (
        <Modal title={deciding.decision === "GRANTED" ? "GRANT THE OVERLOAD" : "REFUSE THE OVERLOAD"} onClose={() => setDeciding(null)}
          foot={<><Btn kind="ghost" onClick={() => setDeciding(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={reason.trim().length < 10 || (deciding.decision === "GRANTED" && !units)} busyLabel="Saving…" onClick={() => decide()}>{deciding.decision === "GRANTED" ? "Grant" : "Refuse"}</Btn></>}>
          <div className="stack">
            <div><b>{deciding.row.full_name}</b> · {deciding.row.matric_no ?? ""} · {deciding.row.level} Level, {semesterWord(deciding.row.semester).toLowerCase()} {deciding.row.session}</div>
            <div className="sub2">Asks for {deciding.row.requested_max} credit units; the maximum is {deciding.row.regular_max}. &ldquo;{deciding.row.reason}&rdquo;</div>
            {deciding.decision === "GRANTED" ? (
              <Field id="ov-units" label="Ceiling granted (credit units)" hint="The most the student may register this semester; it may be less than asked">
                <select id="ov-units" className="ctl" value={units ?? ""} onChange={(e) => setUnits(Number(e.target.value))}>
                  {unitChoices(deciding.row.regular_max, deciding.row.regular_max + o.rule.max_extra).map((n) => <option key={n} value={n}>{n}</option>)}
                </select>
              </Field>
            ) : null}
            <Field id="ov-reason" label="Reason" required hint="Ten characters or more; the student reads it">
              <input id="ov-reason" className="ctl" value={reason} maxLength={1000} autoFocus onChange={(e) => setReason(e.target.value)}
                placeholder={deciding.decision === "GRANTED" ? "e.g. final year: the project and two carry-overs" : "e.g. register the carry-overs first; the load is heavy enough"} />
            </Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
