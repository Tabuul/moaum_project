"use client";

/** V393: the postgraduate students on the Bursary's fee page, read only — those with no fee line stated for the session (they
 *  cannot register until one is), and those whose school-fee payments exceed what they owe under the School's lines since V391,
 *  with the references paid. Nothing is refunded or changed here; the Bursary decides each case by its own refund process. */
import { useEffect, useState } from "react";
import { Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

/** V653: by PG stage too — the stage the Bursary states next (800 B — Year 2), and fresh or returning */
interface Unstated { level: number; programme_code: string; programme: string; stage_code?: string | null; stage_label?: string | null; category?: string | null; students: number }
interface Payment { reference: string; amount: number; purpose: string; confirmedAt: string; channel: string | null; receiptNo: string | null }
interface Review {
  student_id: string; admission_no: string | null; matric_no: string | null; surname: string; other_names: string; status: string;
  programme_code: string; programme: string; level: number; due: number; paid: number; excess: number; payments: string | null;
}

const naira = (n: number) => "₦" + Number(n).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 });

export function PgFees({ session }: { session: string }) {
  const [unstated, setUnstated] = useState<Unstated[] | null>(null);
  const [review, setReview] = useState<Review[] | null>(null);
  const [mayReview, setMayReview] = useState(true);

  useEffect(() => {
    let alive = true;
    void (async () => {
      const [u, r] = await Promise.all([
        fetch(`/api/bff/api/v1/finance/sessions/${session}/postgraduate/unstated`, { cache: "no-store" }),
        fetch(`/api/bff/api/v1/finance/sessions/${session}/postgraduate/review`, { cache: "no-store" }),
      ]);
      if (!alive) return;
      setUnstated(u.ok ? ((await u.json()) as Unstated[]) : []);
      if (r.status === 403) { setMayReview(false); setReview([]); return; }
      setReview(r.ok ? ((await r.json()) as Review[]) : []);
    })();
    return () => { alive = false; };
  }, [session]);

  if (!unstated || !review) return null;
  const waiting = unstated.reduce((n, u) => n + Number(u.students), 0);
  const excess = review.reduce((n, r) => n + Number(r.excess), 0);
  return (
    <Panel title="Postgraduate students · school fees" right={session}>
      <PBody>
        {waiting ? (
          <Note kind="bad" title={`${waiting} postgraduate student${waiting === 1 ? " has" : "s have"} no fee line stated for ${session}`}>
            They cannot register until a line reaches them: name a postgraduate level (700, 800, 900), a PG stage (800 B — Year 2) or fresh or returning, the
            Postgraduate entry mode or group, or the programme. The stage below is each student&rsquo;s in {session}: state it with the Postgraduate fee structure.
          </Note>
        ) : <Note kind="ok" title={`Every live postgraduate student has a fee line stated for ${session}`}>Registration is not held on the School&rsquo;s fees.</Note>}
      </PBody>
      {waiting ? (
        <DTable cols={["Level|num", "Programme", "Stage", "Students|num"]} texts={unstated.map((u) => `${u.level} ${u.programme_code} ${u.programme} ${u.stage_label ?? ""}`)}
          rows={unstated.map((u) => [<span key="l" className="tnum">{u.level}</span>, <span key="p"><b className="tnum">{u.programme_code}</b> {u.programme}</span>,
            <span key="g">{u.stage_label ?? <span className="sub2">Past the maximum period or not read</span>}{u.category ? <span className="sub2"> · {u.category === "FRESH" ? "fresh" : "returning"}</span> : null}</span>,
            <span key="n" className="tnum">{u.students}</span>])} />
      ) : null}
      {mayReview ? (
        <>
          <PBody>
            {review.length ? (
              <Note kind="info" title={`${review.length} postgraduate student${review.length === 1 ? "" : "s"} paid ${naira(excess)} more than they owe for ${session}`}>
                Paid before full-time lines stopped reaching postgraduate students (V391). The payments and references stand; decide each case through the Bursary&rsquo;s refund process. Nothing is refunded from this page.
              </Note>
            ) : <div className="sub2">No postgraduate student has paid more than they owe for {session}.</div>}
          </PBody>
          {review.length ? (
            <DTable cols={["Student", "Programme", "Owes|num", "Paid|num", "More than owed|num", "References"]}
              texts={review.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.admission_no ?? ""} ${r.programme_code}`)}
              rows={review.map((r) => {
                const pays: Payment[] = r.payments ? (JSON.parse(r.payments) as Payment[]) : [];
                return [
                  <span key="s"><b>{r.surname}</b>, {r.other_names}<div className="sub2 tnum">{r.matric_no ?? r.admission_no}</div></span>,
                  <span key="p"><b className="tnum">{r.programme_code}</b> {r.programme}<div className="sub2">{r.level} level · <Pil kind="grey">{r.status.toLowerCase()}</Pil></div></span>,
                  <span key="d" className="tnum">{naira(r.due)}</span>, <span key="pd" className="tnum">{naira(r.paid)}</span>,
                  <b key="x" className="tnum">{naira(r.excess)}</b>,
                  <span key="r">{pays.map((x) => <span key={x.reference} className="blk sub2 tnum">{x.reference} · {naira(x.amount)}{x.receiptNo ? ` · ${x.receiptNo}` : ""}</span>)}</span>,
                ];
              })} />
          ) : null}
        </>
      ) : null}
    </Panel>
  );
}
