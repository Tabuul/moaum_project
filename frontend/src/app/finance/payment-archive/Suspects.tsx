"use client";

/**
 * Possible duplicates (V670): payment records that may be one payment recorded twice — first those that share an authoritative
 * identifier (the gateway's reference, a transaction reference, an old-portal payment number), then, marked, those that share only
 * the student, the amount, the purpose and the day, which an officer checks with the bank or the gateway before archiving anything.
 * Nothing is archived from here without the officer's own reason and note.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SIGNAL_WORDS, type Suspect } from "@/lib/payment-archive";
import { archiveGet } from "./archive-call";

export function Suspects({ session, mayArchive, onClose, onArchive }: {
  session: string; mayArchive: boolean; onClose: () => void; onArchive: (paymentReference: string, relatedReference: string) => void;
}) {
  const [rows, setRows] = useState<Suspect[] | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  useEffect(() => {
    let live = true;
    void archiveGet<Suspect[]>(`/suspects?limit=300${session ? `&session=${encodeURIComponent(session)}` : ""}`).then((r) => {
      if (!live) return;
      if (r.ok) setRows(r.data); else setErr(r.problem);
    });
    return () => { live = false; };
  }, [session]);
  return (
    <Modal wide title="Possible duplicate payments" sub={session ? `Session ${session}` : "All sessions"} onClose={onClose}>
      <Note kind="info" title="Proof first">
        A pair that shares the gateway&apos;s or a transaction reference, or an old-portal payment number, is one payment recorded twice. A pair that shares only the
        student, the amount, the purpose and the day may be two real payments: check the bank statement or the gateway before archiving either.
      </Note>
      {err ? <ProblemNotice problem={err} /> : null}
      {rows === null && !err ? <div className="sub2">Reading the payments…</div> : null}
      {rows && !rows.length ? <div className="sub2">No possible duplicate found.</div> : null}
      {rows && rows.length ? (
        <table className="tbl tbl--data">
          <thead><tr><th>S/N</th><th>Payment</th><th>Repeats</th><th>Student</th><th className="num">Amount</th><th>What they share</th><th /></tr></thead>
          <tbody>
            {rows.map((s, i) => (
              <tr key={`${s.payment_id}-${s.related_id}`}>
                <td className="tnum sub2">{i + 1}</td>
                <td className="tnum">{s.reference}<div className="sub2">{s.purpose} · {s.session} · {s.paid_on}</div></td>
                <td className="tnum">{s.related_reference}{s.related_number && s.related_number !== (s.matric_no ?? s.admission_no) ? <div className="sub2">on {s.related_number}</div> : null}</td>
                <td>{s.name}<div className="sub2 tnum">{s.matric_no ?? s.admission_no ?? ""}</div></td>
                <td className="num tnum">{money(Number(s.amount))}</td>
                <td>{s.authoritative ? <Pil kind="bad">{SIGNAL_WORDS[s.basis] ?? s.basis}</Pil> : <Pil kind="grey">{SIGNAL_WORDS[s.basis] ?? s.basis}</Pil>}
                  {!s.authoritative ? <div className="sub2">Supporting only — not proof</div> : null}</td>
                <td>{mayArchive ? <Btn kind="ghost" onClick={() => onArchive(s.reference, s.related_reference)}>Archive this record…</Btn> : null}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
    </Modal>
  );
}
