"use client";

/**
 * Student 360° — the full record (Oct 2026). Beneath the record's header, the student's whole record in tabs, each read from the
 * module that holds it when the tab is first opened (/api/v1/student/students/{id}/full/{section}): the overview, the biodata, the
 * admission, the level held session by session and every recorded change, every course registration and reset, every result as
 * published, every payment with its official receipt, the hostel, the clearance, the documents, ICT support, the notifications and
 * the activity on the record. Nothing here is stored or worked out afresh; a tab the office does not read is not offered, and the
 * server refuses it all the same. Print full record prints the chosen sections under the University's header.
 */
import { useEffect, useRef, useState, type ReactNode } from "react";
import type { Problem } from "@/lib/api";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tabs, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { MessagesPanel } from "@/components/MessagesPanel";
import { PaymentCorrections, type PaymentCorrection } from "@/components/finance/PaymentCorrections";
import { ReceiptScreen } from "@/app/student/Screens2";
import { ProgrammeHistory } from "@/app/programme-swap/ProgrammeHistory";
import type { Receipt } from "@/lib/student-portal";
import { printDocument } from "@/lib/document/html";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { logExport } from "@/lib/export-log";
import {
  PAYMENT_WORDS, TAB_LABELS, day, levelHistory, naira, printBody, purposeOnly, resultWord, sectionTables, semesterOf, tabOf, tabsFor, timeline, words,
  type Payment, type Progression, type ResultRow, type Section, type Tab, type Table,
} from "@/lib/full-record";

type Row = Record<string, unknown>;
type Data = Record<string, unknown>;
export interface Overview extends Data { sections: string[]; identity: Row; contact: Row | null; position: Row | null; lifecycle: Row | null; graduand: Row | null;
  /** V638: graduated by status reconciliation, outside the maximum academic period */
  reconciliation?: Row | null;
  standing: Row | null; fees?: Row | null; session: string | null; semester: number | null; registrations: number; hostel: Row | null }

const s = (v: unknown) => (v == null ? "" : String(v));
const dash = (v: unknown) => (v == null || v === "" ? "—" : String(v));
const semWord = (n: unknown) => (n === 1 ? "First semester" : n === 2 ? "Second semester" : n === 3 ? "Third semester" : "");
const pillOf = (v: unknown): "ok" | "bad" | "warn" | "grey" | "info" => {
  const x = s(v).toUpperCase();
  if (/^(PAID|FULLY_PAID|APPROVED|LOCKED|CLEARED|COMPLETED|PUBLISHED|ISSUED|ACTIVE|RESOLVED|CLOSED|CONFIRMED|SETTLED)$/.test(x)) return "ok";
  if (/^(EXPIRED|REFUSED|REJECTED|NOT_PAID|CANCELLED|REVOKED|WITHDRAWN|FAILED)$/.test(x)) return "bad";
  if (/^(PENDING|PART_PAYMENT|SUBMITTED|DRAFT|RETURNED|OPEN|IN_PROGRESS|AWAITING|PROBATION)$/.test(x)) return "warn";
  return "grey";
};

/** one section's tables as Excel, branded, S/N first */
function ExcelBtn({ table, name, file }: { table: Table | undefined; name: string; file: string }) {
  const [busy, setBusy] = useState(false);
  if (!table) return null;
  return (
    <Btn kind="ghost" size="sm" busy={busy} busyLabel="Preparing…" disabled={!table.rows.length} onClick={async () => {
      setBusy(true);
      try {
        const blob = await brandedXlsx(table.title, table.headers, table.rows, { sheetName: table.title, sub: name, serial: docSerial("S360") });
        downloadBlob(blob, `${file}-${table.title.toLowerCase().replace(/[^a-z0-9]+/g, "-")}.xlsx`);
      } finally { setBusy(false); }
    }}>Excel</Btn>
  );
}

function Empty({ children }: { children: ReactNode }) {
  return <PBody><div className="sub2">{children}</div></PBody>;
}

export function FullRecord({ studentId, name, number, overview, overviewBody, biodata, swaps, messages, initialTab }: {
  studentId: string; name: string; number: string; overview: Overview;
  /** the record's own panels (classification, matriculation, finance, standing, clearances, registration, history), first on the overview */
  overviewBody: ReactNode; biodata: ReactNode; swaps: PaymentCorrection[] | null; messages: boolean; initialTab?: string | null;
}) {
  const tabs = tabsFor(overview.sections ?? ["overview"], messages);
  const [tab, setTab] = useState<Tab>(tabOf(initialTab, tabs));
  const [data, setData] = useState<Partial<Record<Section, Data>>>({ overview });
  const [problems, setProblems] = useState<Partial<Record<Section, Problem>>>({});
  const [printing, setPrinting] = useState(false);
  const [receipt, setReceipt] = useState<string | null>(null);
  const file = (number || name).replace(/[^A-Za-z0-9]+/g, "-");
  const strip = useRef<HTMLDivElement>(null);

  // on a narrow screen the tabs scroll sideways: the chosen one is brought into the strip (never the page scrolled)
  useEffect(() => {
    const list = strip.current?.querySelector<HTMLElement>("[role=tablist]");
    const on = list?.querySelector<HTMLElement>("[aria-selected=true]");
    if (list && on && list.scrollWidth > list.clientWidth) list.scrollLeft = Math.max(0, on.offsetLeft - list.offsetLeft - 24);
  }, [tab]);

  async function read(section: Section): Promise<Data | null> {
    const r = await fetch(`/api/bff/api/v1/student/students/${studentId}/full/${section}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      setProblems((p) => ({ ...p, [section]: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText } }));
      return null;
    }
    setData((d) => ({ ...d, [section]: j as Data }));
    return j as Data;
  }

  // a tab is read the first time it is opened, and kept
  const isSection = tab !== "biodata" && tab !== "notifications";
  useEffect(() => {
    if (!isSection || tab === "overview") return;
    let live = true;
    (async () => {
      const r = await fetch(`/api/bff/api/v1/student/students/${studentId}/full/${tab}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (!r.ok) setProblems((p) => ({ ...p, [tab]: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText } }));
      else setData((d) => (d[tab as Section] ? d : { ...d, [tab]: j as Data }));
    })();
    return () => { live = false; };
  }, [tab, isSection, studentId]);

  function choose(t: Tab) {
    setTab(t);
    setProblems((p) => { const q = { ...p }; delete q[t as Section]; return q; });
    try {
      const u = new URL(window.location.href);
      if (t === "overview") u.searchParams.delete("tab"); else u.searchParams.set("tab", t);
      window.history.replaceState(window.history.state, "", u.toString());
    } catch { /* the address stays */ }
  }

  const d = isSection ? data[tab as Section] : null;
  const problem = isSection ? problems[tab as Section] : null;

  return (
    <>
      <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "center" }}>
        <div ref={strip} style={{ maxWidth: "100%", minWidth: 0 }} className="grow">
          <Tabs look="line" label="The student's record" value={tab} onChange={choose} items={tabs.map((t) => ({ id: t, label: TAB_LABELS[t] }))} />
        </div>
        <Btn kind="ghost" onClick={() => setPrinting(true)}>Print full record</Btn>
      </div>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {tab === "overview" ? <OverviewTab o={overview} body={overviewBody} /> : null}
      {tab === "biodata" ? biodata : null}
      {tab === "notifications" ? <MessagesPanel path={`/api/v1/students/${studentId}/messages`} /> : null}
      {isSection && tab !== "overview" && !d && !problem ? <Panel title={TAB_LABELS[tab]}><Empty>Reading the record…</Empty></Panel> : null}
      {d && tab === "admission" ? <AdmissionTab d={d} name={name} file={file} /> : null}
      {d && tab === "progression" ? <ProgressionTab d={d as unknown as Progression} name={name} file={file} /> : null}
      {d && tab === "registrations" ? <RegistrationsTab d={d} name={name} file={file} /> : null}
      {d && tab === "results" ? <ResultsTab d={d} name={name} file={file} /> : null}
      {d && tab === "finance" ? <FinanceTab d={d} name={name} file={file} swaps={swaps} onReceipt={setReceipt} /> : null}
      {d && tab === "hostel" ? <HostelTab d={d} name={name} file={file} /> : null}
      {d && tab === "clearance" ? <ClearanceTab d={d} name={name} file={file} /> : null}
      {d && tab === "documents" ? <DocumentsTab d={d} name={name} file={file} /> : null}
      {d && tab === "support" ? <SupportTab d={d} name={name} file={file} /> : null}
      {d && tab === "audit" ? <AuditTab d={d} name={name} file={file} /> : null}

      {receipt ? <ReceiptWindow studentId={studentId} reference={receipt} onClose={() => setReceipt(null)} /> : null}
      {printing ? <PrintRecord tabs={tabs} overview={overview} name={name} number={number} data={data} read={read} onClose={() => setPrinting(false)} /> : null}
    </>
  );
}

/* ── overview ── */

function OverviewTab({ o, body }: { o: Overview; body: ReactNode }) {
  const id = o.identity, pos = o.position, lc = o.lifecycle, fees = o.fees, st = o.standing, g = o.graduand, rc = o.reconciliation ?? null;
  const spill = pos && Number(pos.spillover_years ?? 0) > 0 ? `${pos.spillover_years} spillover year${Number(pos.spillover_years) === 1 ? "" : "s"}` : null;
  const tiles: [ReactNode, ReactNode, string | null, ReactNode?][] = [
    ["Current level", id.current_level ? `${id.current_level} Level` : "—", null, spill ?? (pos?.final_level ? `Final level ${pos.final_level}` : "")],
    ["CGPA", st?.cgpa != null ? Number(st.cgpa).toFixed(2) : "—", null, st?.cgpa != null ? words(st.standing) : "No result published yet"],
    ["Course registrations", String(o.registrations ?? 0), null, "Every session and semester on record"],
  ];
  if (fees !== undefined) {
    tiles.push(["School fees " + (o.session ?? ""), fees ? words(fees.status) : "—", fees && Number(fees.outstanding) > 0 ? "var(--red-ink)" : null,
      fees ? (Number(fees.outstanding) > 0 ? `${naira(fees.outstanding)} outstanding` : `${naira(fees.paid)} paid`) : "Not read"]);
  }
  return (
    <>
      <Tiles items={tiles} />
      <Panel title="Identity and numbers" right={<Pil kind={pillOf(id.status)}>{words(id.status)}</Pil>}>
        <PBody>
          <KvGrid pairs={[
            ["Matriculation number", dash(id.matric_no)], ["Admission number", dash(id.admission_no)], ["JAMB registration", dash(id.jamb_reg_no)],
            ["Application number", dash(id.application_no)], ["Programme", `${dash(id.programme)} (${dash(id.programme_code)})`],
            ...(id.admitted_programme ? [["Original admission programme", s(id.admitted_programme)] as [string, string]] : []), ["Department", dash(id.department)],
            ["Faculty", dash(id.faculty)], ["Entry", `${words(id.entry_mode)} · ${dash(id.entry_session)} · ${dash(id.entry_level)} Level`],
            ["Study mode", words(id.study_mode) || "—"], ["Matriculated", day(id.matriculated_at) || "—"],
            ...(o.contact ? [["E-mail", dash(o.contact.email)], ["Phone", dash(o.contact.phone)]] as [string, string][] : []),
            ["Current session", `${dash(o.session)}${o.semester ? ` · ${semWord(o.semester)}` : ""}`],
            ["Hostel", o.hostel ? `${dash(o.hostel.session)} · ${words(o.hostel.state)}` : "None on record"],
          ]} />
        </PBody>
      </Panel>
      {pos || lc || g ? (
        <Panel title="Lifecycle" right="As the cohort engine reads the record">
          <PBody>
            <KvGrid pairs={[
              ["Effective cohort", `${dash(pos?.effective_cohort)}${pos?.cohort_source ? ` (${words(pos.cohort_source)})` : ""}`],
              ["Programme length", pos?.duration_years ? `${pos.duration_years} years · final level ${dash(pos.final_level)}` : "—"],
              ["Expected completion", dash(pos?.expected_completion)], ["Spillover", spill ? `${spill} · ${words(pos?.spillover_state)}` : "None"],
              ["Classification", words(pos?.classification) || "—"], ["Registered this session", pos?.registered_current ? "Yes" : "No"],
              ["Graduation", g ? `${dash(g.session)} · ${words(g.senate_state)}${g.award ? ` · ${g.award}` : ""}${g.batch_ref ? ` · batch ${g.batch_ref}` : ""}${g.final_level ? ` · final level ${g.final_level}${g.duration_years ? ` (${g.duration_years} years)` : ""}` : ""}${g.spillover_state && String(g.spillover_state).startsWith("SPILLOVER") ? ` · graduated from ${String(g.spillover_state).replace("SPILLOVER_YEAR_", "SP")}` : ""}` : words(pos?.graduation_state) || "Not on a graduation list"],
              ["Recommendation", lc ? `${words(lc.recommendation)} · ${words(lc.confidence)} confidence · ${words(lc.review_state)}` : "—"],
              ...(rc ? [["Status reconciliation", `Graduated ${day(rc.reconciled_at)} by ${s(rc.mode) === "AUTOMATIC" ? "the nightly reconciliation" : "the Academic Office"} (${dash(rc.batch_ref)}): `
                + `outside the maximum academic period, ${dash(rc.spillover_years)} sessions beyond the expected completion with ${dash(rc.max_spillover_years)} allowed · `
                + `graduation session ${dash(rc.graduation_session)} · official date ${rc.date_confirmed && rc.graduation_date ? day(rc.graduation_date) : "awaiting the Academic Office"} · `
                + `${words(rc.confidence)} confidence · status before ${words(rc.previous_status)}`]] as [string, string][] : []),
            ]} />
            {lc?.explanation ? <div className="sub2 mt-2">{s(lc.explanation)}</div> : null}
          </PBody>
        </Panel>
      ) : null}
      {body}
    </>
  );
}

/* ── admission ── */

function AdmissionTab({ d, name, file }: { d: Data; name: string; file: string }) {
  const t = sectionTables("admission", d);
  const st = (d.student ?? {}) as Row, c = d.candidate as Row | null;
  const apps = (d.applications ?? []) as Row[], fees = (d.fees ?? []) as Row[], changes = (d.programmeChanges ?? []) as Row[], transfers = (d.transfers ?? []) as Row[];
  const docs = (d.documents ?? []) as Row[];
  return (
    <>
      <Panel title="Admission" right={c ? `JAMB ${dash(c.session)}` : "No JAMB candidate linked"}>
        <PBody>
          <KvGrid pairs={[
            ["Mode of entry", words(st.entry_mode) || "—"], ["Entry session", dash(st.entry_session)], ["Entry level", st.entry_level ? `${st.entry_level} Level` : "—"],
            ["JAMB registration", dash(st.jamb_reg_no ?? c?.jamb_reg_no)], ["UTME score", dash(c?.utme_aggregate)], ["CAPS aggregate", dash(c?.caps_aggregate)],
            ["Offer", words(c?.offer_state) || "—"], ["State, LGA (CAPS)", c ? [c.caps_state, c.caps_lga].filter(Boolean).join(", ") || "—" : "—"],
            ["Admission number", dash(st.admission_no ?? c?.admission_no)], ["Matriculated", day(st.matriculated_at) || "Not yet"],
          ]} />
        </PBody>
      </Panel>
      <Panel title="Applications" right={<ExcelBtn table={t[0]} name={name} file={file} />}>
        {apps.length ? <DTable pageSize={0} cols={["Application", "Session", "Submitted", "Screening|num", "Decision", "Accepted", "Cleared"]}
          rows={apps.map((a) => [<span key="n" className="tnum">{s(a.application_no)}</span>, s(a.session), day(a.submitted_at), a.screening_score == null ? "—" : s(a.screening_score),
            a.decision ? <Pil key="d" kind={pillOf(a.decision)}>{words(a.decision)}</Pil> : "—", day(a.accepted_at) || "—", day(a.cleared_at) || "—"])} />
          : <Empty>No portal application on record (admitted before the portal, or through the old portal).</Empty>}
      </Panel>
      {fees.length ? (
        <Panel title="Admission fees" right={<ExcelBtn table={t[1]} name={name} file={file} />}>
          <DTable pageSize={0} cols={["Fee", "Reference", "Amount|num", "Confirmed", "Receipt"]}
            rows={fees.map((f) => [words(f.kind), <span key="r" className="tnum">{s(f.reference)}</span>, <span key="a" className="tnum">{naira(f.amount)}</span>,
              f.confirmed_at ? day(f.confirmed_at) : <Pil key="p" kind="warn">Not paid</Pil>, s(f.receipt_no) || "—"])} />
        </Panel>
      ) : null}
      <Panel title="Change of programme and transfers" right={<ExcelBtn table={t[2]} name={name} file={file} />}>
        {changes.length || transfers.length ? (
          <DTable pageSize={0} cols={["Session", "From", "To", "State", "Requested", "Decided", "Note"]}
            rows={[...changes.map((r) => [s(r.session), s(r.from_programme ?? r.from_programme_code), s(r.to_programme ?? r.to_programme_code),
              <Pil key="s" kind={pillOf(r.state)}>{words(r.state)}</Pil>, day(r.requested_at), day(r.decided_at) || "—", s(r.decision_note)]),
            ...transfers.map((x) => [s(x.session), `${s(x.from_programme ?? x.from_programme_code)}${x.from_level ? ` · ${x.from_level}` : ""}`,
              `${s(x.to_programme ?? x.to_programme_code)}${x.recommended_level ? ` · ${x.recommended_level}` : ""}`, <Pil key="s" kind={pillOf(x.state)}>Transfer: {words(x.state)}</Pil>,
              day(x.applied_at), day(x.effected_at ?? x.senate_at) || "—", s(x.senate_note)])]} />
        ) : <Empty>No change of programme or transfer on record.</Empty>}
      </Panel>
      <Panel title="Admission documents">
        {docs.length ? <DTable pageSize={0} cols={["Document", "Detail", "Received", "Status"]}
          rows={docs.map((x) => [words(x.kind), s(x.detail), day(x.received_on) || "—", <Pil key="s" kind={pillOf(x.status)}>{words(x.status)}</Pil>])} />
          : <Empty>No admission document recorded on the student&rsquo;s file.</Empty>}
      </Panel>
      {/* V578: every placement the record has had — the original admission, transfers, record moves, programme swaps */}
      <Panel title="Programme history" right="Original admission first; the current placement marked">
        <ProgrammeHistory rows={(d.programmeHistory ?? []) as Row[]} />
      </Panel>
    </>
  );
}

/* ── level progression ── */

function ProgressionTab({ d, name, file }: { d: Progression; name: string; file: string }) {
  const t = sectionTables("progression", d as unknown as Data);
  const h = levelHistory(d);
  const events = timeline(d);
  const pos = d.position;
  return (
    <>
      <Panel title="Level by session" right={<ExcelBtn table={t[0]} name={name} file={file} />}>
        {h.length ? <DTable pageSize={0} cols={["Session", "Level|mid", "Semesters registered", "Recorded by"]}
          rows={h.map((x) => [<span key="s" className="tnum">{x.session}</span>,
            x.conflict ? <Pil key="l" kind="warn" title="The enrolment and the course registrations of this session name different levels">{x.levels.join(" / ")}</Pil> : <span key="l" className="tnum">{x.level ?? "—"}</span>,
            x.semesters || "None", x.source])} />
          : <Empty>No enrolment or course registration is on record, so no level is shown for any session.</Empty>}
        <PBody><div className="sub2">Only the sessions the record holds are listed: the level of the session&rsquo;s enrolment, or of its course registrations. A session with neither is not filled in.</div></PBody>
      </Panel>
      <Panel title="Timeline of changes" right={<ExcelBtn table={t[1]} name={name} file={file} />}>
        {events.length ? (
          <PBody>
            <ol className="tl" style={{ listStyle: "none", margin: 0, padding: 0, display: "grid", gap: "var(--s-3)" }}>
              {events.map((e, i) => (
                <li key={i} className="row row--top" style={{ gap: "var(--s-4)", borderLeft: "2px solid var(--line-2)", paddingLeft: "var(--s-4)" }}>
                  <span className="sub2 tnum" style={{ minWidth: 92 }}>{day(e.at)}</span>
                  <div className="grow">
                    <div><Pil kind={e.kind === "LEVEL" ? "info" : e.kind === "STATUS" ? "warn" : "grey"}>{words(e.kind)}</Pil> {e.text}</div>
                    {e.by || e.reason ? <div className="sub2">{[e.by, e.reason].filter(Boolean).join(" · ")}</div> : null}
                  </div>
                </li>
              ))}
            </ol>
          </PBody>
        ) : <Empty>No change of level, programme, status or cohort is recorded. (The audit trail on this copy begins on the day it was switched on; earlier changes are not invented.)</Empty>}
      </Panel>
      {pos ? (
        <Panel title="Where the cohort engine places the student">
          <PBody>
            <KvGrid pairs={[["Entry", `${dash(pos.entry_session)} · ${dash(pos.entry_level)} Level`], ["Effective cohort", `${dash(pos.effective_cohort)} (${words(pos.cohort_source)})`],
              ["Programme length", `${dash(pos.duration_years)} years · final level ${dash(pos.final_level)}`], ["Expected completion", dash(pos.expected_completion)],
              ["Level on the record", dash(pos.current_level)], ["Level the engine reads", dash(pos.computed_level)],
              ["Spillover", Number(pos.spillover_years ?? 0) > 0 ? `${pos.spillover_years} · ${words(pos.spillover_state)}` : "None"], ["Sessions deferred", dash(pos.deferred_sessions)]]} />
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}

/* ── course registration ── */

export function RegistrationsTab({ d, name, file }: { d: Data; name: string; file: string }) {
  const t = sectionTables("registrations", d);
  const regs = (d.registrations ?? []) as Row[], resets = (d.resets ?? []) as Row[];
  return (
    <>
      <Panel title="Course registrations" right={<ExcelBtn table={t[0]} name={name} file={file} />}>
        {regs.length ? regs.map((r) => {
          const courses = (r.courses ?? []) as Row[];
          return (
            <PBody key={s(r.id)}>
              <div className="row row--between" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
                <b className="tnum">{s(r.session)} · {semWord(r.semester)} · {s(r.level)} Level</b>
                <span className="row" style={{ gap: "var(--s-3)" }}>
                  <span className="sub2 tnum">{s(r.units)} units{r.submitted_at ? ` · submitted ${day(r.submitted_at)}` : ""}{r.approved_at ? ` · approved ${day(r.approved_at)}${r.approved_by ? ` by ${r.approved_by}` : ""}` : ""}</span>
                  <Pil kind={pillOf(r.status)}>{words(r.status)}</Pil>
                </span>
              </div>
              {r.returned_comment ? <div className="sub2 ink-red">Returned: {s(r.returned_comment)}</div> : null}
              {courses.length ? <DTable pageSize={0} cols={["Course", "Title", "Units|num", "Type", "Status"]}
                rows={courses.map((c) => [<span key="c" className="tnum">{s(c.course_code)}</span>, s(c.title), s(c.units), words(c.added_as ?? c.entry_type), words(c.status)])} />
                : <div className="sub2">No course on this registration.</div>}
            </PBody>
          );
        }) : <Empty>No course registration on record.</Empty>}
      </Panel>
      <Panel title="Registrations reset" right={<ExcelBtn table={t[1]} name={name} file={file} />}>
        {resets.length ? <DTable pageSize={0} cols={["Session", "Semester", "Level|mid", "Was", "Courses|num", "Units|num", "Reset on", "By", "Reason"]}
          rows={resets.map((z) => [s(z.session), semWord(z.semester), s(z.level), words(z.previous_status), s(z.course_count), s(z.units), day(z.reset_at),
            s(z.reset_by ?? z.reset_office), s(z.reason)])} />
          : <Empty>No registration has been reset. Each reset keeps the version it replaced.</Empty>}
      </Panel>
    </>
  );
}

/* ── results ── */

function ResultsTab({ d, name, file }: { d: Data; name: string; file: string }) {
  const t = sectionTables("results", d);
  const results = (d.results ?? []) as unknown as ResultRow[], gpas = (d.semesters ?? []) as Row[], owed = (d.owed ?? []) as Row[];
  const standing = d.standing as Row | null;
  const groups = Array.from(new Map(results.map((r) => [`${r.session}|${r.semester}`, [] as ResultRow[]])).keys()).map((k) => ({ k, rows: results.filter((r) => `${r.session}|${r.semester}` === k) }));
  return (
    <>
      <Panel title="Results" right={<span className="row" style={{ gap: "var(--s-3)" }}>{standing?.cgpa != null ? <span className="tnum">CGPA {Number(standing.cgpa).toFixed(2)} · {words(standing.standing)}</span> : <span className="sub2">No CGPA yet</span>}<ExcelBtn table={t[0]} name={name} file={file} /></span>}>
        {groups.length ? groups.map(({ k, rows }) => {
          const [ses, sem] = k.split("|");
          const g = gpas.find((x) => s(x.session) === ses && s(x.semester) === sem);
          return (
            <PBody key={k}>
              <div className="row row--between"><b className="tnum">{ses} · {semWord(Number(sem))}</b>
                <span className="sub2 tnum">{g ? `GPA ${g.gpa == null ? "—" : Number(g.gpa).toFixed(2)} · CGPA ${g.cgpa == null ? "—" : Number(g.cgpa).toFixed(2)} · ${s(g.published_count)} of ${s(g.registered_count)} published` : "Not yet published"}</span></div>
              <DTable pageSize={0} cols={["Course", "Title", "Units|num", "CA|num", "Exam|num", "Total|num", "Grade or state"]}
                rows={rows.map((r) => [<span key="c" className="tnum">{r.course_code}</span>, r.title, String(r.units), r.published && r.ca != null ? String(r.ca) : "—",
                  r.published && r.exam != null ? String(r.exam) : "—", r.published && r.total != null ? String(r.total) : "—",
                  <Pil key="g" kind={r.published ? (r.grade === "F" || r.outcome === "ABSENT" ? "bad" : "ok") : "grey"}>{resultWord(r)}</Pil>])} />
            </PBody>
          );
        }) : <Empty>No approved course registration, so no result is expected yet.</Empty>}
        <PBody><div className="sub2">A course whose sheet is not yet published reads &ldquo;Not yet submitted&rdquo; or &ldquo;Awaiting approval&rdquo;, and a published sheet without the student reads &ldquo;No result&rdquo; — never a zero or a fail.</div></PBody>
      </Panel>
      <Panel title="Courses still owed" right={<ExcelBtn table={t[2]} name={name} file={file} />}>
        {owed.length ? <DTable pageSize={0} cols={["Course", "Title", "Units|num", "Failed in"]} rows={owed.map((c) => [s(c.course_code), s(c.title), s(c.units), s(c.failed_in)])} />
          : <Empty>No course is owed on the published results.</Empty>}
      </Panel>
    </>
  );
}

/* ── fees and payments ── */

export function FinanceTab({ d, name, file, swaps, onReceipt }: { d: Data; name: string; file: string; swaps: PaymentCorrection[] | null; onReceipt: (ref: string) => void }) {
  const t = sectionTables("finance", d);
  const payments = (d.payments ?? []) as unknown as Payment[];
  const sum = (d.summary ?? {}) as Row;
  const fees = (d.schoolFees ?? []) as Row[], refunds = (d.refunds ?? []) as Row[], over = (d.overpayments ?? []) as Row[], withdrawn = (d.withdrawn ?? []) as Row[];
  const wallet = (d.wallet ?? []) as Row[];
  // V583: the old portal's e-wallet — what it held, what is posted, applied and left
  const lw = (d.legacyWallet ?? null) as Row | null;
  // V625: the legacy credit requests — overpaid school fees on their way to the wallet, and credited
  const lcr = (d.legacyCredits ?? []) as Row[];
  const [kind, setKind] = useState<"ALL" | "SCHOOL" | "OTHER">("ALL");
  const [ses, setSes] = useState("");
  const sessions = Array.from(new Set(payments.map((p) => p.session).filter((x): x is string => !!x))).sort().reverse();
  const shown = payments.filter((p) => (kind === "ALL" || (kind === "SCHOOL") === p.school_fees) && (!ses || p.session === ses));
  return (
    <>
      <Tiles items={[
        ["Payments on record", s(sum.count ?? 0), null, `${s(sum.paid ?? 0)} paid · ${s(sum.pending ?? 0)} pending · ${s(sum.expired ?? 0)} expired`],
        ["Amount paid", naira(sum.amountPaid), null, "Every confirmed payment, all purposes"],
        ["School fees paid", naira(sum.schoolFeesPaid), null, "Confirmed school-fees payments, every session"],
        ["Refunds", s(refunds.length), refunds.length ? "var(--amber-ink)" : null, refunds.length ? naira(refunds.reduce((a, f) => a + Number(f.amount ?? 0), 0)) : "None"],
      ]} />
      {swaps && swaps.length ? <PaymentCorrections items={swaps} staff /> : null}
      <Panel title="School fees by session" right={<ExcelBtn table={t[1]} name={name} file={file} />}>
        {fees.length ? <DTable pageSize={0} cols={["Session", "Due|num", "Paid|num", "Outstanding|num", "Position"]}
          rows={fees.map((f) => [<span key="s" className="tnum">{s(f.session)}</span>, <span key="d" className="tnum">{naira(f.payable)}</span>, <span key="p" className="tnum">{naira(f.paid)}</span>,
            <span key="o" className={`tnum${Number(f.outstanding) > 0 ? " ink-red" : ""}`}>{naira(f.outstanding)}</span>, <Pil key="x" kind={pillOf(f.status)}>{words(f.status)}</Pil>])} />
          : <Empty>No session with school fees on record.</Empty>}
        <PBody><div className="sub2">Each session&rsquo;s position as the student&rsquo;s fees page and the Bursary read it: due by the fee setup, paid from the session&rsquo;s confirmed school-fees payments.</div></PBody>
      </Panel>
      <Panel title="Payments" right={<ExcelBtn table={t[0]} name={name} file={file} />}>
        <PBody>
          <div className="row" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}>
            <Tabs value={kind} onChange={setKind} label="Payments shown" items={[{ id: "ALL", label: "All" }, { id: "SCHOOL", label: "School fees" }, { id: "OTHER", label: "Other payments" }]} />
            <select className="ctl" aria-label="Session" style={{ maxWidth: 170 }} value={ses} onChange={(e) => setSes(e.target.value)}>
              <option value="">Every session</option>
              {sessions.map((x) => <option key={x} value={x}>{x}</option>)}
            </select>
          </div>
        </PBody>
        {/* Oct 2026: the semester its own column, out of the purpose; the reference is on the receipt (still found by the search) */}
        {shown.length ? <DTable cols={["Date", "Session", "Semester", "Purpose", "Amount|num", "Status", "Channel", "Receipt"]}
          texts={shown.map((p) => `${p.reference} ${p.purpose ?? ""} ${p.session ?? ""} ${semesterOf(p.term, p.purpose)} ${p.receipt_no ?? ""} ${p.gateway_ref ?? ""} ${p.original_identifier ?? ""}`)}
          rows={shown.map((p) => [day(p.confirmed_at ?? p.generated_at), s(p.session), semesterOf(p.term, p.purpose) || "—",
            // V647: paid under another number before matriculation — the number as paid, kept with the payment
            p.original_identifier ? <Two key="pu" a={purposeOnly(p.purpose) || "—"} b={`Paid as ${p.original_identifier_type === "JAMB_NUMBER" ? "JAMB number" : p.original_identifier_type === "ADMISSION_NUMBER" ? "admission number" : p.original_identifier_type === "APPLICATION_NUMBER" ? "application number" : "number"} ${p.original_identifier}`} /> : purposeOnly(p.purpose) || "—",
            <span key="a" className="tnum">{naira(p.amount)}</span>,
            <Pil key="s" kind={pillOf(p.status)}>{PAYMENT_WORDS[p.status] ?? p.status}</Pil>, s(p.channel) || "—",
            p.status === "PAID" && p.receipt_no ? <Btn key="v" kind="ghost" size="sm" onClick={() => onReceipt(p.reference)}>View receipt</Btn> : <span key="v" className="sub2">—</span>])} />
          : <Empty>No payment of this kind on record.</Empty>}
      </Panel>
      {refunds.length ? (
        <Panel title="Refunds" right={<ExcelBtn table={t[2]} name={name} file={file} />}>
          <DTable pageSize={0} cols={["Reference", "Amount|num", "State", "Raised", "Approved", "Paid", "Account", "Reason"]}
            rows={refunds.map((f) => [s(f.reference), naira(f.amount), <Pil key="s" kind={pillOf(f.state)}>{words(f.state)}</Pil>, day(f.created_at), day(f.approved_at) || "—",
              day(f.paid_at) || "—", f.account_last4 ? `${s(f.bank_name)} ••••${s(f.account_last4)}` : "—", s(f.reason ?? f.rejected_why)])} />
        </Panel>
      ) : null}
      {over.length ? (
        <Panel title="Overpayments decided">
          <DTable pageSize={0} cols={["Session", "Due|num", "Paid|num", "Over|num", "Decision", "To session", "Reference", "Decided"]}
            rows={over.map((o) => [s(o.session), naira(o.due), naira(o.paid), naira(o.amount), <span key="d">{words(o.decision)}{o.superseded_at ? <div className="sub2">Superseded {day(o.superseded_at)}</div> : null}</span>,
              s(o.to_session) || "—", s(o.reference) || "—", day(o.decided_at)])} />
        </Panel>
      ) : null}
      {withdrawn.length ? (
        <Panel title="Payments withdrawn" right="Kept on record, never deleted">
          <DTable pageSize={0} cols={["Reference", "Kind", "Session", "Purpose", "Amount|num", "Withdrawn", "Reason"]}
            rows={withdrawn.map((w) => [s(w.reference), words(w.double_kind), s(w.session), s(w.purpose), naira(w.amount), day(w.withdrawn_at), s(w.reason)])} />
        </Panel>
      ) : null}
      {lcr.length ? (
        <Panel title="Legacy financial reconciliation" right="Overpaid school fees credited to the wallet by the Bursar (V625)">
          <DTable pageSize={0} cols={["Request", "Session", "Fees due|num", "Paid|num", "Excess|num", "Confirmed|num", "Status", "Officer", "Bursar", "Wallet"]}
            rows={lcr.map((q) => [<span key="r" className="tnum">{s(q.ref)}</span>, <span key="s" className="tnum">{s(q.session)}</span>, <span key="d" className="tnum">{naira(q.due)}</span>,
              <span key="p" className="tnum">{naira(q.paid)}</span>, <span key="e" className="tnum">{naira(q.legacyAmount)}</span>,
              <span key="c" className="tnum">{naira(q.confirmedAmount)}{q.adjusted ? <div className="sub2">amount adjusted</div> : null}</span>,
              <Pil key="x" kind={q.status === "CREDITED" ? "ok" : q.status === "PENDING_BURSAR_APPROVAL" ? "warn" : q.status === "WITHDRAWN" ? "grey" : "bad"}>{words(String(q.status))}</Pil>,
              <span key="o" className="sub2">{s(q.initiatedBy)} · {day(q.initiatedAt)}</span>, <span key="b" className="sub2">{q.decidedAt ? `${s(q.decidedBy)} · ${day(q.decidedAt)}` : "—"}</span>,
              <span key="w" className="tnum sub2">{q.walletReference ? `${s(q.walletReference)} · ${day(q.creditedAt)}` : "—"}</span>])} />
        </Panel>
      ) : null}
      {lw ? (
        <Panel title="Old-portal e-wallet" right={<Pil kind={lw.status === "POSTED" ? "ok" : lw.status === "REQUIRES_REVIEW" ? "bad" : "info"}>{words(lw.status)}</Pil>}>
          <PBody>
            <KvGrid cls="grid--3" pairs={[["Topped up on the old portal", naira(lw.topups)], ["Paid from it", naira(lw.used)],
              [lw.statedBalance != null ? "Balance the old portal states" : "Balance left", naira(lw.statedBalance ?? lw.available)],
              ["Posted to the wallet", lw.status === "POSTED" ? `${naira(lw.posted)} · ${day(lw.postedAt)} · ${s(lw.batchRef)}` : "Not yet"],
              ["Applied to fees", naira(lw.applied)], ["Still on the wallet", lw.status === "POSTED" ? naira(Number(lw.posted) - Number(lw.applied) - Number(lw.refunded)) : "—"]]} />
          </PBody>
        </Panel>
      ) : null}
      {wallet.length ? (
        <Panel title="Wallet (NELFUND, old e-wallet and carried credit)">
          <DTable pageSize={0} cols={["Date", "Kind", "Session", "Amount|num", "Reference", "Source", "Note"]}
            rows={wallet.map((w) => [day(w.at), words(w.kind), s(w.session), naira(w.amount), s(w.reference), s(w.source_code), s(w.note)])} />
        </Panel>
      ) : null}
    </>
  );
}

/** print the receipt's PDF itself (the University's document, not a picture of the window): loaded in a hidden frame and printed
 *  from there, or opened in a tab of its own where the browser will not print a frame */
function printPdf(href: string) {
  const f = document.createElement("iframe");
  f.style.position = "fixed"; f.style.right = "0"; f.style.bottom = "0"; f.style.width = "0"; f.style.height = "0"; f.style.border = "0";
  f.onload = () => {
    try { f.contentWindow?.focus(); f.contentWindow?.print(); } catch { window.open(href, "_blank", "noopener"); }
    window.setTimeout(() => { try { document.body.removeChild(f); } catch { /* already gone */ } }, 60000);
  };
  f.src = href;
  document.body.appendChild(f);
}

/** the official receipt for one confirmed payment, in a window: the student's own receipt (the same screen and PDF), with the QR
 *  to the public verification page */
export function ReceiptWindow({ studentId, reference, onClose }: { studentId: string; reference: string; onClose: () => void }) {
  const [got, setGot] = useState<{ receipt: Receipt; qr: string | null; verifyUrl: string | null; token: string | null } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch(`/students/${studentId}/receipt/${encodeURIComponent(reference)}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (!r.ok) setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText });
      else setGot(j);
    })();
    return () => { live = false; };
  }, [studentId, reference]);
  const pdf = `/students/${studentId}/receipt/${encodeURIComponent(reference)}/pdf`;
  return (
    <Modal wide title="Official payment receipt" sub={reference} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Close</Btn>
        <Btn kind="ghost" disabled={!got} onClick={() => printPdf(pdf)}>Print</Btn>
        {got ? <a className="btn btn--primary" href={pdf} target="_blank" rel="noopener">Download PDF</a> : <Btn kind="primary" disabled>Download PDF</Btn>}
      </>}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!got && !problem ? <div className="sub2">Reading the receipt…</div> : null}
      {got ? (
        <div>
          <ReceiptScreen staff r={got.receipt} qr={got.qr} verifyUrl={got.verifyUrl} token={got.token} photoSrc={`/api/bff/api/v1/student/students/${studentId}/passport`} />
        </div>
      ) : null}
    </Modal>
  );
}

/* ── hostel, clearance, documents, support, activity ── */

function HostelTab({ d, name, file }: { d: Data; name: string; file: string }) {
  const t = sectionTables("hostel", d);
  const h = (d.history ?? []) as Row[], ev = (d.events ?? []) as Row[];
  return (
    <>
      <Panel title="Hostel" right={<ExcelBtn table={t[0]} name={name} file={file} />}>
        {h.length ? <DTable pageSize={0} cols={["Session", "Application", "Allocation", "Hall", "Room", "Bed", "Allocated", "Checked in", "Checked out"]}
          rows={h.map((x) => [s(x.session), `${s(x.application_ref)} ${words(x.application_state)}`.trim() || "—", `${s(x.allocation_ref)} ${words(x.allocation_state)}`.trim() || "—",
            s(x.hall_name) || "—", [x.block, x.room_no].filter(Boolean).join(" ") || "—", s(x.bed_label ?? x.bed) || "—", day(x.allocated_at) || "—", day(x.checked_in_at) || "—", day(x.checked_out_at) || "—"])} />
          : <Empty>No hostel application or allocation on record.</Empty>}
      </Panel>
      {ev.length ? (
        <Panel title="Hostel events">
          <DTable cols={["Date", "Event", "From", "To", "Office", "Note"]} rows={ev.map((e) => [day(e.at), words(e.action), s(e.from_value), s(e.to_value), s(e.actor_office), s(e.note)])} />
        </Panel>
      ) : null}
    </>
  );
}

function ClearanceTab({ d, name, file }: { d: Data; name: string; file: string }) {
  const t = sectionTables("clearance", d);
  const ps = (d.processes ?? []) as Row[], items = (d.items ?? []) as Row[];
  return (
    <Panel title="Clearance" right={<ExcelBtn table={t[0]} name={name} file={file} />}>
      {ps.map((p) => (
        <PBody key={s(p.id)}>
          <div className="row row--between"><b>{s(p.workflow_label ?? p.workflow)} <span className="tnum sub2">{s(p.reference)}</span></b>
            <Pil kind={p.completed_at ? "ok" : p.cancelled_at ? "bad" : "warn"}>{p.completed_at ? `Completed ${day(p.completed_at)}` : p.cancelled_at ? "Cancelled" : `Started ${day(p.started_at)}`}</Pil></div>
          <DTable pageSize={0} cols={["Unit", "State", "Decided", "Note"]} rows={((p.items ?? []) as Row[]).map((i) => [s(i.unit), <Pil key="s" kind={pillOf(i.state)}>{words(i.state)}</Pil>, day(i.decided_at) || "—", s(i.note ?? i.item)])} />
        </PBody>
      ))}
      {items.length ? (
        <PBody>
          <b>Clearance by purpose</b>
          <DTable pageSize={0} cols={["Purpose", "Unit", "State", "Decided", "Note"]} rows={items.map((i) => [words(i.purpose), s(i.unit), <Pil key="s" kind={pillOf(i.state)}>{words(i.state)}</Pil>, day(i.decided_at) || "—", s(i.note ?? i.item)])} />
        </PBody>
      ) : null}
      {!ps.length && !items.length ? <Empty>No clearance on record.</Empty> : null}
    </Panel>
  );
}

function DocumentsTab({ d, name, file }: { d: Data; name: string; file: string }) {
  const t = sectionTables("documents", d);
  const adm = (d.admission ?? []) as Row[], issued = (d.issued ?? []) as Row[], tr = (d.transcripts ?? []) as Row[], cards = (d.cards ?? []) as Row[];
  return (
    <>
      <Panel title="Documents issued" right={<ExcelBtn table={t[1]} name={name} file={file} />}>
        {issued.length ? <DTable pageSize={0} cols={["Document", "Verification code", "Issued", "Office", "State"]}
          rows={issued.map((x) => [words(x.kind), <span key="c" className="tnum">{s(x.verification_code)}</span>, day(x.issued_on), s(x.issued_office),
            <Pil key="s" kind={x.revoked ? "bad" : "ok"}>{x.revoked ? "Revoked" : x.reissue ? "Reissue" : "Issued"}</Pil>])} />
          : <Empty>No certificate, statement or letter issued yet.</Empty>}
      </Panel>
      {tr.length ? (
        <Panel title="Transcript requests">
          <DTable pageSize={0} cols={["Request", "Kind", "Destination", "Copies|num", "Requested", "Paid", "Stage", "Released"]}
            rows={tr.map((x) => [s(x.ref), words(x.kind), s(x.destination_name) || words(x.mode), s(x.copies), day(x.requested_at), day(x.paid_at) || "—", words(x.stage), day(x.released_at) || "—"])} />
        </Panel>
      ) : null}
      {cards.length ? (
        <Panel title="Identity cards">
          {/* V605: printed and issued (handed over) apart, the version and the reason a replacement was made */}
          <DTable pageSize={0} cols={["Card", "Version|num", "Printed", "Issued", "Valid to", "State", "Ended"]}
            rows={cards.map((c) => [s(c.card_no), s(c.version) || "1", day(c.printed_at) || day(c.issued_at), day(c.collected_at) || "—", day(c.valid_to) || "—",
              `${words(c.state)}${c.replacement_reason ? ` · replacement: ${words(c.replacement_reason)}` : ""}`, c.ended_at ? `${day(c.ended_at)} · ${s(c.ended_reason)}` : "—"])} />
        </Panel>
      ) : null}
      <Panel title="Admission documents" right={<ExcelBtn table={t[0]} name={name} file={file} />}>
        {adm.length ? <DTable pageSize={0} cols={["Document", "Detail", "Received", "Status"]} rows={adm.map((x) => [words(x.kind), s(x.detail), day(x.received_on) || "—", words(x.status)])} />
          : <Empty>No admission document recorded on the student&rsquo;s file.</Empty>}
      </Panel>
    </>
  );
}

function SupportTab({ d, name, file }: { d: Data; name: string; file: string }) {
  const t = sectionTables("support", d);
  const tickets = (d.tickets ?? []) as Row[], actions = (d.actions ?? []) as Row[];
  return (
    <>
      <Panel title="Support tickets" right={<ExcelBtn table={t[0]} name={name} file={file} />}>
        {tickets.length ? <DTable pageSize={0} cols={["Ticket", "Category", "Subject", "Status", "Assigned", "Raised", "Resolved"]}
          rows={tickets.map((x) => [<span key="n" className="tnum">{s(x.number)}</span>, s(x.category), s(x.subject), <Pil key="s" kind={pillOf(x.status)}>{words(x.status)}</Pil>,
            s(x.assigned_to) || "—", day(x.created_at), day(x.resolved_at) || "—"])} />
          : <Empty>The student has raised no support ticket.</Empty>}
      </Panel>
      <Panel title="What ICT Support did on the record" right={<ExcelBtn table={t[1]} name={name} file={file} />}>
        {actions.length ? <DTable cols={["Date", "Action", "Summary", "Agent", "Reason"]}
          rows={actions.map((x) => [day(x.at), <span key="a">{words(x.action)}{x.override ? <div className="sub2 ink-red">Override</div> : null}</span>, s(x.summary), `${s(x.agent)}${x.agent_office ? ` (${x.agent_office})` : ""}`, s(x.reason)])} />
          : <Empty>No support action on the record.</Empty>}
      </Panel>
    </>
  );
}

function AuditTab({ d, name, file }: { d: Data; name: string; file: string }) {
  const [t] = sectionTables("audit", d);
  const rows = (d.activity ?? []) as Row[];
  return (
    <Panel title="Activity on the record" right={<ExcelBtn table={t} name={name} file={file} />}>
      {rows.length ? <DTable cols={["Date", "Activity", "By", "Changed", "Reason"]} texts={t.rows.map((r) => r.join(" "))}
        rows={t.rows.map((r) => [<span key="d" className="tnum">{s(r[1])}</span>, s(r[2]), s(r[3]), <span key="c" className="sub2">{s(r[4])}</span>, s(r[5])])} />
        : <Empty>No activity on the audit trail for this record yet.</Empty>}
      <PBody><div className="sub2">From the University&rsquo;s audit trail: every change to the record, its contact details and its course registrations, every ICT support action, matriculation numbers and documents issued and payment reallocations — newest first, 500 at most. Passwords are never on it.</div></PBody>
    </Panel>
  );
}

/* ── print full record ── */

function PrintRecord({ tabs, overview, name, number, data, read, onClose }: {
  tabs: Tab[]; overview: Overview; name: string; number: string; data: Partial<Record<Section, Data>>; read: (s: Section) => Promise<Data | null>; onClose: () => void;
}) {
  const printable = tabs.filter((t): t is Section => t !== "biodata" && t !== "notifications");
  const [chosen, setChosen] = useState<Section[]>(printable);
  const [busy, setBusy] = useState(false);
  const [missing, setMissing] = useState<string[]>([]);
  async function go() {
    setBusy(true);
    try {
      const got: Partial<Record<Section, Data | null>> = { ...data };
      await Promise.all(chosen.filter((c) => !got[c]).map(async (c) => { got[c] = await read(c); }));
      const lost = chosen.filter((c) => !got[c]).map((c) => TAB_LABELS[c]);
      setMissing(lost);
      const id = overview.identity;
      const parts = chosen.filter((c) => got[c]).map((c) => c === "overview"
        ? { label: TAB_LABELS.overview, tables: [], facts: [["Name", name], ["Matriculation number", s(id.matric_no) || "—"], ["Programme", s(id.programme)], ["Department", s(id.department)],
          ["Faculty", s(id.faculty)], ["Level", `${s(id.current_level)} Level`], ["Status", words(id.status)], ["Entry", `${words(id.entry_mode)} · ${s(id.entry_session)}`],
          ["CGPA", overview.standing?.cgpa != null ? Number(overview.standing.cgpa).toFixed(2) : "No result published"]] as [string, string][] }
        : { label: TAB_LABELS[c], tables: sectionTables(c, got[c]) });
      const serial = docSerial("S360");
      logExport({ report: "Student full record", format: "PRINT", rows: parts.length, meta: [["Student", number || name], ["Sections", chosen.map((c) => TAB_LABELS[c]).join(", ")]], sub: name, serial });
      await printDocument("STANDARD_REPORT", { title: "Student record", subtitle: `${name}${number ? ` · ${number}` : ""}`, reference: serial, bodyHtml: printBody(parts),
        meta: [["Student", name], ["Number", number || "—"], ["Sections", chosen.map((c) => TAB_LABELS[c]).join(", ")]], confidentiality: "Confidential: for official use", orientation: "landscape" });
      if (!lost.length) onClose();
    } finally { setBusy(false); }
  }
  return (
    <Modal title="Print full record" sub={name} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><Btn kind="primary" busy={busy} busyLabel="Reading the record…" disabled={!chosen.length} onClick={() => void go()}>Print</Btn></>}>
      <Note kind="info" title="The record as it stands">Each section is read from the module that holds it and printed under the University&rsquo;s header; the browser&rsquo;s Save as PDF keeps a copy. Only the sections this office reads are offered.</Note>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(190px, 1fr))", gap: "var(--s-2)", marginTop: "var(--s-3)" }}>
        {printable.map((c) => (
          <label key={c} className="row row--tight" style={{ gap: 6 }}>
            <input type="checkbox" className="pchk" checked={chosen.includes(c)} onChange={(e) => setChosen((x) => (e.target.checked ? printable.filter((y) => x.includes(y) || y === c) : x.filter((y) => y !== c)))} />
            {TAB_LABELS[c]}
          </label>
        ))}
      </div>
      {missing.length ? <Note kind="bad" title="Not printed">{missing.join(", ")} could not be read just now; the rest was printed.</Note> : null}
    </Modal>
  );
}
