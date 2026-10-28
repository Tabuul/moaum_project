"use client";

/**
 * V654: the Student Full Record's Finance tab — the historical school fees (each session and semester assessed at the fees of the
 * period, paid, owed), the assessments, and where the graduate stands for financial clearance; the desk opens the rest. Read when
 * shown; an office that does not read historical fees sees nothing. V683: the graduate's payment evidence, and where each verified one's
 * payment stands — never counted by itself.
 */
import { useEffect, useState } from "react";
import { LinkBtn, Panel, PBody, Pil, Spinner } from "@/components/proto/ui";
import { HistoricalAccount, HistoricalTotals } from "@/components/finance/HistoricalAccount";
import { EVIDENCE_WORDS, naira, PAYMENT_STATE_WORDS, semesterWords, STATE_WORDS, type StudentAccount } from "@/lib/historical-fees";

export function HistoricalFeesPanel({ studentId }: { studentId: string }) {
  const [a, setA] = useState<StudentAccount | null | "none">(null);
  useEffect(() => {
    let alive = true;
    fetch(`/api/bff/api/v1/finance/historical/students/${studentId}`, { cache: "no-store" })
      .then(async (r) => { if (alive) setA(r.ok ? ((await r.json()) as StudentAccount) : "none"); })
      .catch(() => { if (alive) setA("none"); });
    return () => { alive = false; };
  }, [studentId]);
  if (a === "none") return null;
  return (
    <Panel title="Historical school fees" right={<LinkBtn kind="ghost" href={`/finance/historical?q=${encodeURIComponent(studentId)}`}>Open in Historical Fees &amp; Clearance</LinkBtn>}>
      <PBody>
        {!a ? <div className="row row--tight sub2" role="status"><Spinner /> Reading the historical account…</div> : (
          <>
            <HistoricalTotals periods={a.periods} />
            <div className="mt-2"><HistoricalAccount periods={a.periods} /></div>
            {a.assessments.length ? (
              <div className="mt-2">
                <strong>Historical fee assessments</strong>
                <ul className="m-0">{a.assessments.map((x) => (
                  <li key={x.id}><span className="tnum">{x.reference}</span> · {x.session} {semesterWords(x.semester).toLowerCase()} · {naira(x.amount)} ·{" "}
                    <Pil kind={STATE_WORDS[x.state]?.[1] ?? "grey"}>{STATE_WORDS[x.state]?.[0] ?? x.state}</Pil></li>
                ))}</ul>
              </div>
            ) : null}
            {a.evidence?.length ? (
              <div className="mt-2">
                <strong>Payment evidence from the graduate</strong>
                <ul className="m-0">{a.evidence.map((e) => (
                  <li key={e.id}><span className="tnum">{e.reference}</span> · {e.session} {semesterWords(e.semester).toLowerCase()} · {naira(e.amount)} · No. <span className="tnum">{e.payment_reference}</span> ·{" "}
                    <Pil kind={EVIDENCE_WORDS[e.state]?.[1] ?? "grey"}>{EVIDENCE_WORDS[e.state]?.[0] ?? e.state}</Pil>
                    {e.payment ? <span className="sub2"> · payment {e.payment}{e.payment_state ? ` — ${PAYMENT_STATE_WORDS[e.payment_state][0].toLowerCase()}` : ""}</span> : null}</li>
                ))}</ul>
              </div>
            ) : null}
            <div className="sub2 mt-2">
              Financial clearance: {a.clearance ? `${a.clearance.reference} · Bursary stage ${a.clearance.bursary ? a.clearance.bursary.replace(/_/g, " ").toLowerCase() : "pending"}` : "no final clearance started"} ·
              academic status {a.student.status}.
            </div>
          </>
        )}
      </PBody>
    </Panel>
  );
}
