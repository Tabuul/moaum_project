"use client";
/** V735 · Summer Semester fees — the Bursary states the programme fee (once a student a Summer) and the fee a course for a session, for
 *  every programme or one programme; a statement is a DRAFT, never charged, until the Bursar publishes it; a published one is never
 *  changed — a new one is stated and the old withdrawn with the reason — and a charge keeps the figure it was made at. The collections
 *  show the programme fees and the course fees apart. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { day } from "@/lib/format";
import { FEE_STATE_WORD, naira, num, type Money } from "@/lib/summer";

export interface SummerFeeRow {
  id: string; session: string; programme_code: string | null; programme_name: string | null; programme_fee: Money; course_fee: Money;
  effective_from: string; state: "DRAFT" | "PUBLISHED" | "WITHDRAWN"; reason: string | null; stated_at: string; stated_office: string;
  published_at: string | null; withdrawn_at: string | null; withdrawn_reason: string | null; charges: number;
}
export interface SummerCollection {
  session: string; programme_fees_paid: Money; programme_fees_paid_count: number; course_fees_paid: Money; course_fees_paid_count: number;
  programme_fees_due: Money; course_fees_due: Money;
}
export interface SummerFeesView { fees: SummerFeeRow[]; collections: SummerCollection[]; programmes: { code: string; name: string }[] }

const STATERS = ["bursar", "studentaccounts", "super"];
const APPROVERS = ["bursar", "super"];

async function call(method: "POST" | "DELETE", path: string, body: unknown, reason: string): Promise<Problem | null> {
  const r = await fetch(`/api/bff/api/v1${path}`, {
    method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: method === "DELETE" ? undefined : JSON.stringify(body ?? {}),
  });
  if (r.ok) return null;
  const j = await r.json().catch(() => null);
  return j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText };
}

export function SummerFees({ view, sessions, initialSession, actingOffice }: { view: SummerFeesView; sessions: string[]; initialSession?: string | null; actingOffice: string | null }) {
  const router = useRouter();
  const mayState = STATERS.includes(actingOffice ?? "");
  const mayApprove = APPROVERS.includes(actingOffice ?? "");
  const [session, setSession] = useState(initialSession && sessions.includes(initialSession) ? initialSession : sessions[0] ?? "");
  const [programme, setProgramme] = useState("");
  const [pf, setPf] = useState("50000");
  const [cf, setCf] = useState("5000");
  const [from, setFrom] = useState("");
  const [why, setWhy] = useState("");
  const [withdrawing, setWithdrawing] = useState<string | null>(null);
  const [wreason, setWreason] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function run(key: string, method: "POST" | "DELETE", path: string, body: unknown, reason: string, done: string) {
    setBusy(key);
    setProblem(null);
    try {
      const p = await call(method, path, body, reason);
      if (p) { setProblem(p); notifyProblem(p); return false; }
      notify(done);
      router.refresh();
      return true;
    } finally {
      setBusy(null);
    }
  }

  const c = view.collections;
  const total = (k: keyof SummerCollection) => c.reduce((s, x) => s + num(x[k] as Money), 0);
  return (
    <>
      <Tiles items={[
        ["Programme fees paid", naira(total("programme_fees_paid")), null, `${c.reduce((s, x) => s + x.programme_fees_paid_count, 0)} students`],
        ["Course fees paid", naira(total("course_fees_paid")), null, `${c.reduce((s, x) => s + x.course_fees_paid_count, 0)} course registrations`],
        ["Owed, not yet paid", naira(total("programme_fees_due") + total("course_fees_due")), null, "Selected on the portal and unpaid"],
        ["Statements", String(view.fees.length), null, `${view.fees.filter((f) => f.state === "PUBLISHED").length} published`],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      {mayState ? (
        <Panel title="State the Summer Semester fees" right="A draft until the Bursar publishes it">
          <PBody>
            <div className="grid grid--3">
              <Field id="sf-s" label="Session">
                <select id="sf-s" className="ctl" value={session} onChange={(e) => setSession(e.target.value)}>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select>
              </Field>
              <Field id="sf-p" label="Programme" hint="Every programme, or one with its own fees.">
                <select id="sf-p" className="ctl" value={programme} onChange={(e) => setProgramme(e.target.value)}>
                  <option value="">Every programme</option>
                  {view.programmes.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
                </select>
              </Field>
              <Field id="sf-f" label="Effective from" hint="Empty: today."><input id="sf-f" type="date" className="ctl" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
              <Field id="sf-pf" label="Programme fee (₦)" hint="Charged once a student a Summer, with the first course."><input id="sf-pf" className="ctl tnum" inputMode="decimal" value={pf} onChange={(e) => setPf(e.target.value.replace(/[^0-9.]/g, ""))} /></Field>
              <Field id="sf-cf" label="Fee a course (₦)" hint="Charged for each course registered."><input id="sf-cf" className="ctl tnum" inputMode="decimal" value={cf} onChange={(e) => setCf(e.target.value.replace(/[^0-9.]/g, ""))} /></Field>
              <Field id="sf-w" label="Reason" hint="Kept with the statement."><input id="sf-w" className="ctl" value={why} onChange={(e) => setWhy(e.target.value)} /></Field>
            </div>
            <div className="mt-2">
              <Btn kind="primary" size="md" busy={busy === "state"} busyLabel="Stating…" disabled={busy !== null || !session || !(Number(pf) > 0) || !(Number(cf) > 0)}
                   onClick={async () => { if (await run("state", "POST", "/finance/summer-fees", { session, programme: programme || null, programmeFee: Number(pf), courseFee: Number(cf), effectiveFrom: from || null, reason: why.trim() || null }, `Summer Semester fees stated for ${session}`, "Stated as a draft")) setWhy(""); }}>
                State as a draft
              </Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Statements" right={String(view.fees.length)}>
        {view.fees.length ? (
          <DTable cols={["Session", "Programme", "Programme fee|num", "Fee a course|num", "From", "State", "Charges|num", "Stated", "|mid"]} rows={view.fees.map((f) => {
            const [w, t] = FEE_STATE_WORD[f.state] ?? [f.state, "grey"];
            return [
              <span key="s" className="tnum">{f.session}</span>,
              <span key="p">{f.programme_name ?? "Every programme"}</span>,
              <span key="pf" className="tnum">{naira(f.programme_fee)}</span>,
              <span key="cf" className="tnum">{naira(f.course_fee)}</span>,
              <span key="ef" className="sub2">{day(f.effective_from)}</span>,
              <span key="st"><Pil kind={t}>{w.toUpperCase()}</Pil>{f.withdrawn_reason ? <span className="blk sub2">{f.withdrawn_reason}</span> : null}</span>,
              <span key="ch" className="tnum">{f.charges}</span>,
              <span key="sa" className="sub2">{day(f.stated_at)}{f.reason ? ` · ${f.reason}` : ""}</span>,
              <span key="a" className="row" style={{ gap: "var(--s-1)", flexWrap: "wrap" }}>
                {f.state === "DRAFT" && mayApprove ? <Btn kind="primary" size="sm" disabled={busy !== null} onClick={() => void run(`p${f.id}`, "POST", `/finance/summer-fees/${f.id}/publish`, {}, `Summer Semester fees for ${f.session} published`, "Published — new charges take it")}>Publish</Btn> : null}
                {f.state === "DRAFT" && mayState ? <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => void run(`d${f.id}`, "DELETE", `/finance/summer-fees/${f.id}`, null, `Summer Semester fee draft for ${f.session} deleted`, "Draft deleted")}>Delete</Btn> : null}
                {f.state === "PUBLISHED" && mayApprove ? <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => { setWithdrawing(f.id); setWreason(""); }}>Withdraw</Btn> : null}
              </span>,
            ];
          })} />
        ) : <PBody><Note kind="info" title="No Summer Semester fees are stated">{mayState ? "State them above; students select courses once the Bursar publishes them." : "The Bursary states them."}</Note></PBody>}
        {withdrawing ? (
          <PBody>
            <div className="row" style={{ flexWrap: "wrap", alignItems: "flex-end", gap: "var(--s-2)" }}>
              <Field id="sf-wr" label="Why it is withdrawn" hint="At least 10 characters. Charges already made keep their figure."><input id="sf-wr" className="ctl" value={wreason} onChange={(e) => setWreason(e.target.value)} /></Field>
              <Btn kind="primary" size="md" disabled={busy !== null || wreason.trim().length < 10} onClick={async () => { if (await run("w", "POST", `/finance/summer-fees/${withdrawing}/withdraw`, { reason: wreason.trim() }, "Summer Semester fee withdrawn", "Withdrawn")) setWithdrawing(null); }}>Withdraw it</Btn>
              <Btn kind="ghost" size="md" onClick={() => setWithdrawing(null)}>Cancel</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>

      {c.length ? (
        <Panel title="Collections by session" right="Programme fees and course fees apart">
          <DTable cols={["Session", "Programme fees paid|num", "Students|num", "Course fees paid|num", "Courses|num", "Owed, unpaid|num"]} rows={c.map((x) => [
            <span key="s" className="tnum">{x.session}</span>,
            <span key="pf" className="tnum">{naira(x.programme_fees_paid)}</span>,
            <span key="pn" className="tnum">{x.programme_fees_paid_count}</span>,
            <span key="cf" className="tnum">{naira(x.course_fees_paid)}</span>,
            <span key="cn" className="tnum">{x.course_fees_paid_count}</span>,
            <span key="o" className="tnum">{naira(num(x.programme_fees_due) + num(x.course_fees_due))}</span>,
          ])} />
        </Panel>
      ) : null}
    </>
  );
}
