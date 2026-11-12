"use client";

/**
 * V654: a graduate's historical financial position — the account by session and semester (the totals first), every assessment, the
 * school-fee payments with the number each was made under, the payment corrections, and the final clearance's Bursary stage. From a
 * period the officer creates an assessment (or one for a fee that was different), opens one pending, or corrects an approved one;
 * the statement prints with the official header; once the Bursary stage is cleared the financial clearance certificate prints with
 * the clearance's check code. V665: a waiver or adjustment proposed from an owing period, the waivers of the record, the payments outside
 * school fees in an owing session, and whether the award is approved with the final clearance to complete.
 */
import { useEffect, useState } from "react";
import { Btn, LinkBtn, Note, Pil, Spinner } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { printDocument } from "@/lib/document/html";
import { docSerial } from "@/lib/exportbrand";
import { logExport } from "@/lib/export-log";
import { HistoricalAccount, HistoricalTotals } from "@/components/finance/HistoricalAccount";
import { beforeFirstYear, can, EVIDENCE_WORDS, KIND_WORDS, naira, num, PAYMENT_STATE_WORDS, semesterWords, STATE_WORDS, STATEMENT_HEAD, statementRows, totals, WAIVER_WORDS, type Assessment, type Desk, type Period, type StudentAccount as Account } from "@/lib/historical-fees";
import { AssessmentForm } from "./AssessmentForm";
import { AssessmentView } from "./AssessmentView";
import { WaiverForm, WaiverView } from "./Waivers";
import { EvidenceView } from "./Evidence";
import { hfCall } from "./hf-call";

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "Africa/Lagos" }) : "—");

export function StudentAccount({ studentId, desk, onClose, onChanged }: { studentId: string; desk: Desk; onClose: () => void; onChanged: () => void }) {
  const [a, setA] = useState<Account | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tick, setTick] = useState(0);
  const [making, setMaking] = useState<Period | null>(null);
  const [viewing, setViewing] = useState<string | null>(null);
  const [waiving, setWaiving] = useState<Period | null>(null);
  const [waiver, setWaiver] = useState<string | null>(null);
  const [evidence, setEvidence] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    void hfCall<Account>(`/students/${studentId}`).then((r) => { if (!alive) return; if (r.ok) setA(r.data); else setProblem(r.problem); });
    return () => { alive = false; };
  }, [studentId, tick]);
  const changed = () => { setTick((n) => n + 1); onChanged(); };

  if (making && a) {
    return <AssessmentForm studentId={studentId} studentName={`${a.student.surname}, ${a.student.other_names}`} period={making} sources={desk.sources}
      onClose={() => setMaking(null)} onSaved={(id) => { setMaking(null); setViewing(id); changed(); }} />;
  }
  if (viewing) return <AssessmentView id={viewing} desk={desk} onClose={() => setViewing(null)} onChanged={changed} />;
  if (waiving && a) {
    return <WaiverForm studentId={studentId} studentName={`${a.student.surname}, ${a.student.other_names}`} period={waiving}
      onClose={() => setWaiving(null)} onSaved={(id) => { setWaiving(null); setWaiver(id); changed(); }} />;
  }
  if (waiver) return <WaiverView id={waiver} desk={desk} onClose={() => setWaiver(null)} onChanged={changed} />;
  if (evidence) return <EvidenceView id={evidence} desk={desk} onClose={() => setEvidence(null)} onChanged={changed} />;
  if (!a) return <Modal wide title="Historical school fees" onClose={onClose}>{problem ? <ProblemNotice problem={problem} /> : <div className="row row--tight sub2"><Spinner /> Reading the account…</div>}</Modal>;

  const s = a.student;
  const name = `${s.surname}, ${s.other_names}`;
  const t = totals(a.periods);
  const mayCreate = can(desk, "CREATE_HISTORICAL_FEE_ASSESSMENT");
  const facts: [string, string][] = [["Student", name], ["Matric No.", s.matric_no ?? "—"], ["JAMB No.", s.jamb_reg_no ?? "—"], ["Faculty", s.faculty ?? "—"],
    ["Department", s.department ?? "—"], ["Programme", s.programme], ["Graduation session", s.graduation_session ?? "—"], ["Academic status", s.status]];

  function printStatement() {
    const serial = docSerial("HFS");
    logExport({ report: "Historical school fees statement", format: "PRINT", rows: a!.periods.length, meta: facts, sub: name, serial });
    void printDocument("STATEMENT", {
      title: "HISTORICAL SCHOOL FEES STATEMENT", subtitle: name, meta: facts, headers: STATEMENT_HEAD, rows: statementRows(a!.periods), reference: serial,
      footnote: `Total assessed ${naira(t.assessed)}${t.waived ? ` · approved waivers and adjustments ${naira(t.waived)}` : ""} · total paid ${naira(t.paid)} · TOTAL HISTORICAL SCHOOL FEES OUTSTANDING ${naira(t.outstanding)}${t.review ? ` · ${t.review} semester(s) still being assessed and not owed` : ""}. Amounts are the University's historical fees for each session and level, or an assessment approved by the Bursar; payments are the confirmed school-fee payments of each session.`,
    });
  }

  return (
    <Modal wide title={name} sub={`${s.matric_no ?? s.admission_no ?? "—"} · ${s.programme} · graduation ${s.graduation_session ?? "—"} · ${s.status}`} onClose={onClose}
      foot={<>
        <Btn kind="secondary" onClick={printStatement}>Print statement</Btn>
        {a.clearance?.bursary === "CLEARED" && can(desk, "VIEW_FINANCIAL_CLEARANCE") ? (
          <a className="btn btn--secondary btn--sm" href={`/finance/historical/certificate?student=${studentId}`} target="_blank" rel="noreferrer">Print financial clearance certificate</a>
        ) : null}
        <span className="grow" />
        <Btn kind="ghost" onClick={onClose}>Close</Btn>
      </>}>
      <Note kind={t.outstanding > 0 ? "bad" : t.review ? "info" : "ok"} title={`Academic status: ${s.status} · ${t.outstanding > 0 ? `Financial status: outstanding ${naira(t.outstanding)}` : t.review ? "Financial status: historical fee review required" : "Financial status: no outstanding historical school fees"}`}>
        Assessed from {a.start ?? "the first session the fee setup holds"} to {s.graduation_session ?? "the graduation session"}, each session at the student&rsquo;s level in it
        (admitted {s.entry_session ?? "—"} at {s.entry_level ?? "—"} Level). An outstanding balance never changes the academic status.
      </Note>
      {a.awaitingFinalClearance ? (
        <Note kind="info" title="Award approved — awaiting final clearance">
          The record reads GRADUATED once every office has cleared the student and the Bursar confirms the final clearance, last, with nothing owed.
        </Note>
      ) : null}
      <HistoricalTotals periods={a.periods} />
      <div className="mt-3"><strong>Historical school fees</strong></div>
      <HistoricalAccount periods={a.periods} actions={(p) => (
        p.pending_id ? <Btn kind="ghost" onClick={() => setViewing(p.pending_id!)}>View pending</Btn>
          : p.source === "ASSESSMENT" && p.assessment_id ? <Btn kind="ghost" onClick={() => setViewing(p.assessment_id!)}>View</Btn>
          : p.source === "NONE" && mayCreate ? <Btn kind="primary" onClick={() => setMaking(p)}>Create historical assessment</Btn>
          : p.source === "STRUCTURE" && mayCreate && !beforeFirstYear(p) ? (
            <span className="row row--tight">
              <Btn kind="ghost" onClick={() => setMaking(p)}>Assess a different fee</Btn>
              {num(p.outstanding) > 0 ? <Btn kind="ghost" onClick={() => setWaiving(p)}>Waive or adjust</Btn> : null}
            </span>
          ) : null
      )} />
      {a.waivers?.length ? (
        <>
          <div className="mt-3"><strong>Waivers and adjustments</strong></div>
          <DTable cols={["Reference", "Period", "Kind", "Amount|num", "Approval it rests on", "State", "Proposed by", "|num"]} rows={a.waivers.map((w) => [
            <span key="r" className="tnum">{w.reference}</span>, <span key="p">{w.session} · {semesterWords(w.semester)}</span>, <span key="k">{KIND_WORDS[w.kind]}</span>,
            <span key="a" className="tnum">{naira(w.amount)}</span>, <span key="au" className="sub2">{w.authority}</span>,
            <Pil key="st" kind={WAIVER_WORDS[w.state]?.[1] ?? "grey"}>{WAIVER_WORDS[w.state]?.[0] ?? w.state}</Pil>,
            <span key="m" className="sub2">{w.created_by_name ?? "—"} · {day(w.created_at)}</span>,
            <Btn key="v" kind="ghost" onClick={() => setWaiver(w.id)}>View</Btn>,
          ])} />
        </>
      ) : null}
      <div className="mt-3"><strong>Historical fee assessments</strong></div>
      {a.assessments.length ? (
        <DTable cols={["Reference", "Period", "Amount|num", "Source", "State", "Made by", "|num"]} rows={a.assessments.map((x: Assessment) => [
          <span key="r" className="tnum">{x.reference}</span>, <span key="p">{x.session} · {semesterWords(x.semester)}</span>,
          <span key="a" className="tnum">{naira(x.amount)}</span>, <span key="s" className="sub2">{x.source_reference ?? x.source}</span>,
          <Pil key="st" kind={STATE_WORDS[x.state]?.[1] ?? "grey"}>{STATE_WORDS[x.state]?.[0] ?? x.state}</Pil>,
          <span key="m" className="sub2">{x.created_by_name ?? "—"} · {day(x.created_at)}</span>,
          <Btn key="v" kind="ghost" onClick={() => setViewing(x.id)}>View</Btn>,
        ])} />
      ) : <div className="sub2">None — every amount above is the session&rsquo;s fee structure.</div>}
      {a.payments ? (
        <>
          <div className="mt-3"><strong>Historical payments</strong></div>
          {a.payments.length ? (
            <DTable cols={["Reference", "Session", "Purpose", "Amount|num", "Confirmed", "Channel", "Receipt"]} rows={a.payments.map((p) => [
              <span key="r" className="tnum">{p.reference}{p.paid_as ? <span className="blk sub2">Paid as {p.paid_as}</span> : null}</span>, <span key="s" className="tnum">{p.session}</span>,
              <span key="p" className="sub2">{p.purpose}</span>, <span key="a" className="tnum">{naira(p.amount)}</span>,
              <span key="c" className="sub2">{p.confirmed_at ? day(p.confirmed_at) : "Not paid"}</span>, <span key="ch" className="sub2">{p.channel ?? "—"}</span>,
              <span key="x" className="tnum sub2">{p.receipt_no ?? "—"}</span>,
            ])} />
          ) : <div className="sub2">No school-fee payment on record.</div>}
          {a.otherPayments?.length ? (
            <>
              <div className="mt-2"><strong>Payments outside school fees in an owing session</strong></div>
              <div className="sub2 mb-1">Not counted as school fees. An old-portal outstanding-fees payment is verified and credited on its own desk; one credited to the wrong student is swapped.</div>
              <DTable cols={["Reference", "Session", "Purpose", "Amount|num", "Confirmed", "Desk"]} rows={a.otherPayments.map((o) => [
                <span key="r" className="tnum">{o.reference}</span>, <span key="s" className="tnum">{o.session}</span>, <span key="p" className="sub2">{o.purpose}</span>,
                <span key="a" className="tnum">{naira(o.amount)}</span>, <span key="c" className="sub2">{day(o.confirmed_at)}</span>,
                <span key="d" className="sub2">{o.kind === "OUTSTANDING_FEES" ? (o.desk_status ? o.desk_status.toLowerCase() : "waiting on the Outstanding fees payments desk") : "—"}</span>,
              ])} />
            </>
          ) : null}
          {/* V683: what the graduate says they paid, and where each verified one's payment stands */}
          {a.evidence?.length ? (
            <>
              <div className="mt-2"><strong>Payment evidence from the graduate</strong></div>
              <div className="sub2 mb-1">Never counted by itself: a verified evidence names the payment on record, which counts once it is the session&rsquo;s school fees.</div>
              <DTable cols={["Evidence", "Semester", "Amount|num", "Number", "State", "Payment", "|num"]} rows={a.evidence.map((e) => [
                <span key="r" className="tnum">{e.reference}<span className="blk sub2">{day(e.submitted_at)}</span></span>, <span key="s" className="tnum">{e.session} · S{e.semester}</span>,
                <span key="a" className="tnum">{naira(e.amount)}</span>, <span key="n" className="tnum sub2">{e.payment_reference}</span>,
                <Pil key="st" kind={EVIDENCE_WORDS[e.state]?.[1] ?? "grey"}>{EVIDENCE_WORDS[e.state]?.[0] ?? e.state}</Pil>,
                <span key="p" className="sub2">{e.payment ? <>{e.payment}{e.payment_state ? <span className="blk">{PAYMENT_STATE_WORDS[e.payment_state][0]}</span> : null}</> : "—"}</span>,
                <Btn key="v" kind="ghost" onClick={() => setEvidence(e.id)}>View</Btn>,
              ])} />
            </>
          ) : null}
          {a.reallocations?.length ? (
            <>
              <div className="mt-2"><strong>Payment reallocations</strong></div>
              <DTable cols={["Correction", "Payment", "Amount|num", "From", "To", "Done"]} rows={a.reallocations.map((r) => [
                <span key="c" className="tnum">{r.realloc_ref}</span>, <span key="p" className="tnum">{r.reference}</span>, <span key="a" className="tnum">{naira(r.amount)}</span>,
                <span key="f" className="sub2">{r.from_purpose} ({r.from_session})</span>, <span key="t" className="sub2">{r.to_purpose} ({r.to_session})</span>,
                <span key="d" className="sub2">{day(r.executed_at)} · {r.status.toLowerCase()}</span>,
              ])} />
            </>
          ) : null}
        </>
      ) : null}
      <div className="mt-3"><strong>Financial clearance</strong></div>
      {a.clearance ? (
        <div className="row row--tight" style={{ flexWrap: "wrap" }}>
          <span>Final clearance {a.clearance.reference} ({a.clearance.session}) · Bursary stage:</span>
          <Pil kind={a.clearance.bursary === "CLEARED" ? "ok" : a.clearance.bursary ? "warn" : "grey"}>{a.clearance.bursary ? a.clearance.bursary.replace(/_/g, " ").toLowerCase() : "pending"}</Pil>
          <span className="sub2">Overall: {a.clearance.overall ?? "—"}</span>
          {can(desk, "PROCESS_FINANCIAL_CLEARANCE") ? <LinkBtn kind="ghost" href={`/clearance?q=${encodeURIComponent(s.matric_no ?? s.admission_no ?? "")}`}>Open the clearance desk</LinkBtn> : null}
        </div>
      ) : <div className="sub2">No final clearance started for this student. The Bursary stage, once started, reads this account and is not cleared while anything is outstanding or being assessed.</div>}
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}
