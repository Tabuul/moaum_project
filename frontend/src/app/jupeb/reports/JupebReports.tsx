"use client";

/**
 * The JUPEB Office's reports of a session (V347), read from the record as it stands: enrolment (by state, programme,
 * combination, state of origin and class), fees (by kind and month, and the school-fee position — what the Bursary's
 * engine charged and confirmed; nothing here changes an amount), attendance and results by subject, and practice tests.
 * Each table downloads in Excel and PDF with the University's branding.
 */
import { useEffect, useState, type ReactNode } from "react";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { FEE_KIND, STATE_SHORT, jcall, naira, streamLabel } from "@/lib/jupeb";

type Num = number | string | null;
interface Report {
  session: string; sessions: string[];
  enrolment: {
    byState: { state: string; count: number }[]; byStream: { stream: string; applicants: number; admitted: number; students: number }[];
    byCombination: { code: string; name: string; students: number }[]; byState_of_origin: { state: string; students: number }[];
    byClass: { class: string; students: number; capacity: number | null }[];
    totals: { applications: number; submitted: number; admitted: number; students: number; withdrawn: number; fromOldPortal: number };
  };
  fees: {
    byKind: { kind: string; payments: number; amount: Num; oldPortal: number }[]; byMonth: { month: string; amount: Num; payments: number }[];
    schoolFees: { students: number; paidInFull: number; partly: number; unpaid: number; charged: Num; paid: Num; outstanding: Num }; total: Num;
  };
  attendance: { code: string; title: string; semester: number; students: number; averageRate: Num; belowMinimum: number; atRisk: number; classesHeld: number }[];
  results: { code: string; title: string; candidates: number; A: number; B: number; C: number; D: number; E: number; F: number; other: number; passRate: Num; averagePoints: Num }[];
  practice: { title: string; code: string; attempts: number; students: number; averagePercent: Num }[];
}
type Section = "enrolment" | "fees" | "attendance" | "results" | "practice";
type Cell = string | number | null;

const pct = (v: Num) => (v == null ? "—" : `${Number(v)}%`);
const month = (m: string) => { const d = new Date(`${m}-01T00:00:00`); return Number.isNaN(d.getTime()) ? m : d.toLocaleDateString("en-GB", { month: "long", year: "numeric" }); };

export function JupebReports() {
  const [session, setSession] = useState("");
  const [loaded, setLoaded] = useState<Report | null>(null);
  const [sessions, setSessions] = useState<string[]>([]);
  const [tab, setTab] = useState<Section>("enrolment");
  useEffect(() => {
    let live = true;
    void jcall<{ session: string; sessions: { session: string }[] }>("/api/v1/jupeb/office/dashboard").then((r) => {
      if (!live) return;
      if (r.ok) { setSessions(r.data.sessions.map((x) => x.session)); setSession((s) => s || r.data.session); } else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, []);
  useEffect(() => {
    if (!session) return;
    let live = true;
    void jcall<Report>(`/api/v1/jupeb/office/reports?session=${encodeURIComponent(session)}`).then((r) => {
      if (!live) return;
      if (r.ok) setLoaded(r.data); else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, [session]);
  /* the report shown is the session chosen: until it arrives, the one before is not passed off as it */
  const data = loaded && loaded.session === session ? loaded : null;
  const t = data?.enrolment.totals;
  return (
    <>
      <PageHead title="JUPEB reports" description="A session's enrolment, fees, attendance, results and practice, as the record stands. Each table downloads in Excel and PDF."
        actions={<select className="ctl" aria-label="Session" value={session} onChange={(e) => setSession(e.target.value)}>
          {(sessions.length ? sessions : session ? [session] : []).map((x) => <option key={x}>{x}</option>)}</select>} />
      {!data ? <Note kind="info" title="Loading the report…">One moment.</Note> : (
        <>
          <Tiles cls="grid--4" items={[
            ["Applications", t?.applications ?? 0, null, `${t?.submitted ?? 0} submitted`],
            ["Admitted", t?.admitted ?? 0, null, `${t?.withdrawn ?? 0} withdrawn`],
            ["Students", t?.students ?? 0, null, `${t?.fromOldPortal ?? 0} from the old portal`],
            ["Fees confirmed", naira(data.fees.total), null, `${naira(data.fees.schoolFees.outstanding)} school fees outstanding`],
          ]} />
          <Tabs<Section> look="line" value={tab} onChange={setTab} items={[
            { id: "enrolment", label: "Enrolment" }, { id: "fees", label: "Fees" }, { id: "attendance", label: "Attendance", count: data.attendance.length },
            { id: "results", label: "Results", count: data.results.length }, { id: "practice", label: "Practice tests", count: data.practice.length },
          ]} />
          {tab === "enrolment" ? (
            <div className="grid grid--2">
              <Table s={data.session} title="Applications by state" heads={["State", "Applications"]} rows={data.enrolment.byState.map((x) => [STATE_SHORT[x.state] ?? x.state, x.count])} />
              <Table s={data.session} title="By programme" heads={["Programme", "Applicants", "Admitted", "Students"]}
                rows={data.enrolment.byStream.map((x) => [x.stream === "UNSET" ? "Not chosen" : streamLabel(x.stream), x.applicants, x.admitted, x.students])} />
              <Table s={data.session} title="Students by subject combination" heads={["Combination", "Name", "Students"]} rows={data.enrolment.byCombination.map((x) => [x.code, x.name, x.students])} />
              <Table s={data.session} title="Students by state of origin" heads={["State of origin", "Students"]} rows={data.enrolment.byState_of_origin.map((x) => [x.state, x.students])} />
              <Table s={data.session} title="Students by class" heads={["Class", "Students", "Capacity"]} rows={data.enrolment.byClass.map((x) => [x.class, x.students, x.capacity ?? "—"])} />
            </div>
          ) : tab === "fees" ? (
            <>
              <Note kind="info" title="The Bursary's figures, read only">Amounts are those the Bursary&rsquo;s fee engine charged and the gateway (or the old portal&rsquo;s upload) confirmed; this report changes nothing.</Note>
              <div className="grid grid--2">
                <Table s={data.session} title="Confirmed payments by fee" heads={["Fee", "Payments", "Amount", "From the old portal"]}
                  rows={data.fees.byKind.map((x) => [FEE_KIND[x.kind] ?? x.kind, x.payments, naira(x.amount), x.oldPortal])} foot={["Total", data.fees.byKind.reduce((a, x) => a + x.payments, 0), naira(data.fees.total), ""]} />
                <Table s={data.session} title="Confirmed payments by month" heads={["Month", "Payments", "Amount"]} rows={data.fees.byMonth.map((x) => [month(x.month), x.payments, naira(x.amount)])} />
                <Table s={data.session} title="School fees position" heads={["Measure", "Value"]} rows={[
                  ["Admitted students", data.fees.schoolFees.students], ["Paid in full", data.fees.schoolFees.paidInFull], ["Partly paid", data.fees.schoolFees.partly],
                  ["Not paid", data.fees.schoolFees.unpaid], ["School fees due", naira(data.fees.schoolFees.charged)], ["Paid", naira(data.fees.schoolFees.paid)], ["Outstanding", naira(data.fees.schoolFees.outstanding)],
                ]} />
              </div>
            </>
          ) : tab === "attendance" ? (
            <Table s={data.session} title="Attendance by subject" heads={["Code", "Subject", "Semester", "Students", "Classes held", "Average rate", "Below the minimum", "Close to it"]}
              rows={data.attendance.map((x) => [x.code, x.title, x.semester, x.students, x.classesHeld, pct(x.averageRate), x.belowMinimum, x.atRisk])} empty="No attendance taken this session." />
          ) : tab === "results" ? (
            <Table s={data.session} title="Results by subject" heads={["Code", "Subject", "Candidates", "A", "B", "C", "D", "E", "F", "Absent / withheld", "Pass rate", "Average points"]}
              rows={data.results.map((x) => [x.code, x.title, x.candidates, x.A, x.B, x.C, x.D, x.E, x.F, x.other, pct(x.passRate), x.averagePoints == null ? "—" : Number(x.averagePoints).toFixed(2)])}
              empty="No results imported this session." />
          ) : (
            <Table s={data.session} title="Practice tests" heads={["Subject", "Test", "Students", "Attempts", "Average score"]}
              rows={data.practice.map((x) => [x.code, x.title, x.students, x.attempts, pct(x.averagePercent)])} empty="No practice attempt this session." />
          )}
        </>
      )}
    </>
  );
}

function Table({ s, title, heads, rows, foot, empty }: { s: string; title: string; heads: string[]; rows: Cell[][]; foot?: Cell[]; empty?: ReactNode }) {
  const all = foot ? [...rows, foot] : rows;
  const name = `jupeb-${title.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${s.replace("/", "-")}`;
  async function excel() {
    downloadBlob(await brandedXlsx(`JUPEB — ${title}`, heads, all, { sheetName: title.slice(0, 30), serial: docSerial("JUPEBRPT"), meta: [["Session", s]] }), `${name}.xlsx`);
  }
  return (
    <Panel title={title} right={rows.length ? <span className="row"><Btn kind="ghost" onClick={() => void excel()}>Excel</Btn>
      <Btn kind="ghost" onClick={() => brandedPrint(`JUPEB — ${title}`, `Session ${s}`, heads, all, docSerial("JUPEBRPT"), { orientation: heads.length > 6 ? "landscape" : "portrait" })}>PDF</Btn></span> : null}>
      <PBody>
        {rows.length ? <DTable noPrint pageSize={0} cols={heads.map((h, i) => (i > 0 && typeof rows[0]?.[i] === "number" ? `${h}|num` : h))} rows={all.map((r) => r.map((c) => c ?? "—"))} />
          : <p className="sub2">{empty ?? "Nothing to show."}</p>}
      </PBody>
    </Panel>
  );
}
