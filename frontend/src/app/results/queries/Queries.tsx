"use client";

/**
 * The department's result-query desk (V027): what each student said about
 * one mark in one course, the mark as the sheet holds it, and the answer on
 * the record — upheld, corrected through the chain, or closed as not a
 * query. The student reads the answer on their own screen.
 */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";

export interface QueryRow {
  id: string; ref: string; part: string; said: string; routed_dept: string; dept_name: string; raised_at: string; state: string; answer: string | null; answered_at: string | null;
  matric_no: string | null; surname: string; other_names: string; course_code: string; title: string; session: string; semester: number;
  ca: number | null; exam: number | null; total: number | null; grade: string | null; outcome: string | null;
}

const PART: Record<string, string> = { EXAM: "The examination mark", CA: "The continuous assessment mark", ABSENT: "Recorded absent, sat the paper" };

export function Queries({ rows, state, dept, actingOffice }: { rows: QueryRow[]; state: string; dept: string; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["hod", "lecturer", "exams", "dean", "records", "academic", "registrar", "super"].includes(actingOffice ?? "");
  const [answering, setAnswering] = useState<QueryRow | null>(null);
  const [verdict, setVerdict] = useState("UPHELD");
  const [answer, setAnswer] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function send() {
    if (!answering) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/results/queries/${answering.id}/answer`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Query ${answering.ref} answered: ${verdict}`) }, body: JSON.stringify({ state: verdict, answer }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(`Query ${answering.ref} answered`);
      setAnswering(null);
      setAnswer("");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const open = rows.filter((r) => r.state === "RAISED");
  return (
    <>
      <Tiles items={[
        ["Open", String(open.length), open.length ? "var(--red-ink)" : null, "With the department"],
        ["Shown", String(rows.length), null, state === "open" ? "Open queries" : state === "answered" ? "Answered" : "All"],
        ["Corrected", String(rows.filter((r) => r.state === "CORRECTED").length), "var(--chrome)", "Sent back through the chain"],
        ["Upheld", String(rows.filter((r) => r.state === "UPHELD").length), "var(--green-ink)", "The mark stood"],
      ]} />
      <div className="row">
        {["open", "answered", "all"].map((s) => <Link key={s} href={`/results/queries?state=${s}${dept ? `&dept=${encodeURIComponent(dept)}` : ""}`} className={`btn btn--sm ${state === s ? "btn--primary" : "btn--ghost"}`}>{s === "open" ? "Open" : s === "answered" ? "Answered" : "All"}</Link>)}
      </div>
      <Note kind="info" title="A query is against one mark, and the answer says what was checked">
        Upheld: the script was re-totalled and the entry matched it. Corrected: the mark is amended on the sheet and the set goes back through the department, the faculty and Senate for an amendment minute; the published result changes when that finishes. Closed: not a query &mdash; &ldquo;I expected a better grade&rdquo;.
      </Note>
      {problem && !answering ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Queries" right={`${rows.length}`}>
        <DTable cols={["Reference", "Student", "Course", "Mark on the sheet|mid", "What they said", "State|mid", "|num"]} rows={rows.map((r) => [
          <span className="tnum sub2" key="r">{r.ref}</span>,
          <Two key="s" a={`${r.surname}, ${r.other_names}`} b={r.matric_no ?? ""} />,
          <Two key="c" a={<span className="tnum">{r.course_code}</span>} b={`${r.title} · ${r.session} · sem ${r.semester}`} />,
          <span className="tnum" key="m">{r.outcome === "GRADED" ? `CA ${r.ca} + exam ${r.exam} = ${r.total} (${r.grade})` : r.outcome ?? "—"}</span>,
          <Two key="w" a={PART[r.part] ?? r.part} b={r.said} />,
          r.state === "RAISED" ? <Pil kind="bad" key="t">Open</Pil> : r.state === "UPHELD" ? <Pil kind="ok" key="t">Upheld</Pil> : r.state === "CORRECTED" ? <Pil kind="info" key="t">Corrected</Pil> : <Pil kind="grey" key="t">Closed</Pil>,
          r.state === "RAISED" ? <Btn kind="primary" key="a" disabled={!may} onClick={() => { setAnswering(r); setVerdict("UPHELD"); setAnswer(""); }}>Answer</Btn> : <span className="sub2" key="a">{r.answer}</span>,
        ])} texts={rows.map((r) => `${r.ref} ${r.surname} ${r.other_names} ${r.matric_no} ${r.course_code} ${r.title}`)} />
        {!rows.length ? <div className="card__body"><div className="sub2">Nothing here.</div></div> : null}
      </Panel>
      {answering ? (
        <Modal title={`Answer ${answering.ref}`} sub={`${answering.surname}, ${answering.other_names} · ${answering.course_code} · ${PART[answering.part] ?? answering.part}`} onClose={() => setAnswering(null)}
          foot={<><Btn kind="ghost" onClick={() => setAnswering(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={!answer.trim() || busy} onClick={() => void send()}>{busy ? "Answering…" : "Answer on the record"}</Btn></>}>
          <div className="sub2">They said: {answering.said}</div>
          <Field id="qv" label="Finding"><select id="qv" className="ctl" value={verdict} onChange={(e) => setVerdict(e.target.value)}><option value="UPHELD">Upheld — the mark stands</option><option value="CORRECTED">Corrected — the mark is amended through the chain</option><option value="CLOSED">Closed — not a query</option></select></Field>
          <Field id="qa" label="Answer" hint="What was checked and what was found. The student reads this."><textarea id="qa" className="ctl" rows={3} value={answer} onChange={(e) => setAnswer(e.target.value)} /></Field>
          {verdict === "CORRECTED" ? <Note kind="info" title="Correcting the mark is a separate act">Amend it on the sheet from the approval chain and return the set; this answer records that the correction is under way.</Note> : null}
          {problem ? <ProblemNotice problem={problem} /> : null}
        </Modal>
      ) : null}
    </>
  );
}
