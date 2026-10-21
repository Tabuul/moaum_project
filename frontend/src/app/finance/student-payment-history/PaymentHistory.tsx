"use client";

/** t/studentpaymenthistory (Oct 2026) — the Bursary's and the Students Account Officer's report of one student's payments. The matriculation
 *  number (or admission or JAMB number) is searched as the portal's search finds a student (each search on the audit trail), and the
 *  student's payments are shown as the Student 360° record shows them — every payment with its session, semester, purpose, amount,
 *  status, channel and official receipt, the school fees by session, refunds, overpayments, withdrawals and the wallet — with
 *  buttons to the student's biodata (read only) and course registrations. Nothing is worked out here: each part is the record's own
 *  section, refused by the server to an office that does not read it. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import type { StudentRecord } from "@/lib/student";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { PaymentCorrection } from "@/components/finance/PaymentCorrections";
import { FinanceTab, ReceiptWindow, RegistrationsTab } from "@/app/students/[id]/FullRecord";
import { Biodata } from "@/app/students/[id]/Biodata";

interface Hit { kind: string; identifier: string; name: string; detail: string; status: string; id: string }
interface Found { q: string; kind: string; hits: Hit[]; exact: Hit | null; total: number }
type View = "payments" | "biodata" | "registrations";
type Data = Record<string, unknown>;

const BFF = "/api/bff/api/v1";

async function read<T>(url: string): Promise<T> {
  const r = await fetch(url, { cache: "no-store" }).catch(() => null);
  const j = r ? await r.json().catch(() => null) : null;
  if (!r || !r.ok) throw (j && typeof j === "object" && "status" in j ? j : { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem;
  return j as T;
}

const statusKind = (s: string): "ok" | "bad" | "warn" | "grey" =>
  /^(ACTIVE|ADMITTED)$/i.test(s) ? "ok" : /^(WITHDRAWN|EXPELLED|RUSTICATED|DECEASED)$/i.test(s) ? "bad" : /^(PROBATION|SUSPENDED|DEFERRED|DORMANT)$/i.test(s) ? "warn" : "grey";

export function PaymentHistory({ initial }: { initial: string }) {
  const [typed, setTyped] = useState(initial);
  const [searching, setSearching] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [hits, setHits] = useState<Hit[] | null>(null);
  const [student, setStudent] = useState<Hit | null>(null);

  async function search(term: string) {
    const q = term.trim();
    if (!q) return;
    setSearching(true); setProblem(null); setHits(null); setStudent(null);
    try {
      const f = await read<Found>(`${BFF}/student/search?q=${encodeURIComponent(q)}&kind=students`);
      const students = f.hits.filter((h) => h.kind === "students" || !h.kind);
      const one = f.exact ?? (students.length === 1 ? students[0] : null);
      if (one) open(one, q);
      else setHits(students);
    } catch (e) {
      setProblem(e as Problem);
    } finally {
      setSearching(false);
    }
  }

  function open(h: Hit, q?: string) {
    setStudent(h); setHits(null);
    try {
      const u = new URL(window.location.href);
      u.searchParams.set("n", q ?? h.identifier);
      window.history.replaceState(window.history.state, "", u.toString());
    } catch { /* the address stays */ }
  }

  // a number in the address (a link, a reload) is searched at once
  useEffect(() => {
    if (!initial) return;
    const t = setTimeout(() => { void search(initial); }, 0);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <>
      <Panel title="Payment history" right="A student's payments, biodata and course registration, by matriculation number">
        <PBody>
          <form className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}
            onSubmit={(e) => { e.preventDefault(); void search(typed); }}>
            <Field id="ph-number" label="Matriculation number" style={{ flex: "1 1 260px", maxWidth: 420 }}
              hint="Or the admission or JAMB number, or a name">
              <input id="ph-number" className="ctl" value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="e.g. BSU/SS/ECO/21/12345"
                autoComplete="off" spellCheck={false} autoFocus />
            </Field>
            <Btn kind="primary" type="submit" disabled={!typed.trim()} busy={searching} busyLabel="Searching…">Search</Btn>
          </form>
        </PBody>
        {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : null}
        {hits ? (
          hits.length ? (
            <>
              <PBody><div className="sub2">{hits.length.toLocaleString()} students match &ldquo;{typed.trim()}&rdquo;: choose one.</div></PBody>
              <DTable cols={["Number", "Name", "Programme", "Status", "|num"]}
                rows={hits.map((h) => [<span key="n" className="tnum">{h.identifier}</span>, h.name, <span key="d" className="sub2">{h.detail}</span>,
                  <Pil key="s" kind={statusKind(h.status)}>{h.status}</Pil>, <Btn key="o" kind="ghost" size="sm" onClick={() => open(h)}>Payment history</Btn>])} />
            </>
          ) : <PBody><Note kind="info" title="No student found">No student has the number &ldquo;{typed.trim()}&rdquo;. Check it, or search by the admission or JAMB number.</Note></PBody>
        ) : null}
      </Panel>
      {student ? <StudentHistory key={student.id} h={student} /> : null}
    </>
  );
}

/** one student: the header, the three views, each read when first opened */
function StudentHistory({ h }: { h: Hit }) {
  const [view, setView] = useState<View>("payments");
  const [finance, setFinance] = useState<Data | null>(null);
  const [swaps, setSwaps] = useState<PaymentCorrection[] | null>(null);
  const [regs, setRegs] = useState<Data | null>(null);
  const [record, setRecord] = useState<StudentRecord | null>(null);
  const [problem, setProblem] = useState<Partial<Record<View, Problem>>>({});
  const [receipt, setReceipt] = useState<string | null>(null);
  const file = (h.identifier || h.name).replace(/[^A-Za-z0-9]+/g, "-");

  useEffect(() => {
    let live = true;
    const fail = (v: View) => (e: unknown) => { if (live) setProblem((p) => ({ ...p, [v]: e as Problem })); };
    if (view === "payments" && !finance) {
      read<Data>(`${BFF}/student/students/${h.id}/full/finance`).then((d) => { if (live) setFinance(d); }).catch(fail("payments"));
      read<PaymentCorrection[]>(`${BFF}/finance/payment-swaps/of/${h.id}`).then((d) => { if (live) setSwaps(d); }).catch(() => { /* not read by this office */ });
    }
    if (view === "registrations" && !regs) read<Data>(`${BFF}/student/students/${h.id}/full/registrations`).then((d) => { if (live) setRegs(d); }).catch(fail("registrations"));
    if (view === "biodata" && !record) read<StudentRecord>(`${BFF}/student/students/${h.id}`).then((d) => { if (live) setRecord(d); }).catch(fail("biodata"));
    return () => { live = false; };
  }, [view, h.id, finance, regs, record]);

  const reading = <Panel title={view === "payments" ? "Payments" : view === "biodata" ? "Biodata" : "Course registrations"}><PBody><div className="sub2" role="status">Reading the record…</div></PBody></Panel>;
  const tab = (v: View, label: string) => <Btn kind={view === v ? "primary" : "ghost"} onClick={() => setView(v)} title={view === v ? `${label}: shown` : undefined}>{label}</Btn>;
  return (
    <>
      <Panel title={<Two a={h.name} b={<span className="tnum">{h.identifier}</span>} />} right={<Pil kind={statusKind(h.status)}>{h.status}</Pil>}>
        <PBody>
          <div className="row row--between" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "center" }}>
            <span className="sub2">{h.detail}</span>
            <span className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
              {tab("payments", "Payment history")}
              {tab("biodata", "View biodata")}
              {tab("registrations", "Course registration")}
              <LinkBtn href={`/students/${h.id}`}>Full record (Student 360°)</LinkBtn>
            </span>
          </div>
        </PBody>
      </Panel>
      {problem[view] ? <ProblemNotice problem={problem[view] as Problem} /> : null}
      {view === "payments" && !problem.payments ? (finance ? <FinanceTab d={finance} name={h.name} file={file} swaps={swaps} onReceipt={setReceipt} /> : reading) : null}
      {view === "registrations" && !problem.registrations ? (regs ? <RegistrationsTab d={regs} name={h.name} file={file} /> : reading) : null}
      {view === "biodata" && !problem.biodata ? (record ? <Biodata record={record} may={false} /> : reading) : null}
      {receipt ? <ReceiptWindow studentId={h.id} reference={receipt} onClose={() => setReceipt(null)} /> : null}
    </>
  );
}
