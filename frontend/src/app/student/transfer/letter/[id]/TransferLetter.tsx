"use client";

/** A branded, printable inter-departmental transfer approval letter. It renders as a
 *  standalone document (the .rpt paper styling used by the returns) so it prints clean.
 *  V727: the fee is the server's — the fee the transfer was completed against, or the one stated now, and what is paid — never a
 *  figure written here; the approval is worded for the route the application took (the four desks, or the committee and Senate). */
import { Btn } from "@/components/proto/ui";
import { letterRoute, naira, num, type Money } from "@/lib/transfer-fee";

export interface LetterApp {
  id: string; from_programme: string; from_level: number; to_programme: string; recommended_level: number | null;
  state: string; session: string; fee_reference: string | null; fee_confirmed_at: string | null;
  // V727: people.transfer_list's columns — the fee (for an effected transfer, the one it was completed against), what is paid, the balance
  fee_due?: Money | null; paid_total?: Money | null; old_portal_paid?: Money | null; balance?: Money | null; band?: string | null;
  acad_at?: string | null;
}

/** the fee in the letter's words: paid in full (and how much of it on the old portal), or what remains before the transfer takes effect */
function feeWords(app: LetterApp): string | null {
  if (app.fee_due == null) return app.state === "EFFECTED" ? null : "The non-refundable processing fee is paid on your transfer page once the Bursary states it.";
  const fee = num(app.fee_due);
  if (fee <= 0) return null;
  const owed = num(app.balance);
  if (owed > 0) {
    return `The transfer is given effect on the register once the non-refundable processing fee of ${naira(fee)} is paid in full; ${naira(owed)} of it remains, paid on your transfer page.`;
  }
  const old = num(app.old_portal_paid);
  return `The non-refundable processing fee of ${naira(fee)} is paid in full${old > 0 ? `, ${naira(old)} of it on the old portal` : ""}.`;
}

export function TransferLetter({ student, app }: { student: { name: string; matric_no: string | null; programme: string }; app: LetterApp }) {
  const today = new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
  const desks = letterRoute(app) === "DESKS";
  const effected = app.state === "EFFECTED";
  const level = app.recommended_level ? <> at <strong>{app.recommended_level} Level</strong></> : null;
  const fee = feeWords(app);
  return (
    <div className="rpt">
      <div className="rpt__toolbar no-print row">
        <Btn kind="primary" size="md" onClick={() => window.print()}>Print / Save as PDF</Btn>
      </div>
      <div className="rpt__paper">
        <header className="rpt__head">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="rpt__crest" src="/crest.png" alt="University crest" />
          <div>
            <div className="rpt__uni">Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div className="rpt__place">Office of the Registrar · Unified University Portal</div>
          </div>
        </header>

        <div className="rpt__banner">
          <h1 className="rpt__title">Inter-Departmental Transfer — Approval</h1>
          <div className="rpt__meta">Session {app.session}</div>
        </div>

        <div style={{ padding: "var(--s-2) var(--s-1)", lineHeight: 1.7, fontSize: "var(--t-base)" }}>
          <p style={{ textAlign: "right" }}>{today}</p>
          <p><strong>{student.name}</strong><br />{student.matric_no ?? ""}</p>
          <p>Dear Student,</p>
          <p className="b700">APPROVAL OF INTER-DEPARTMENTAL TRANSFER</p>
          {desks ? (
            <p>
              I am directed to inform you that your application to transfer from <strong>{app.from_programme}</strong> to{" "}
              <strong>{app.to_programme}</strong>, approved by the Head of your department, accepted by the Head of the department you
              applied to and approved by the Registry, has received the final approval of the Academic Office. You are transferred
              to <strong>{app.to_programme}</strong>{level} for the {app.session} session.
            </p>
          ) : (
            <p>
              I am directed to inform you that the Senate, on the recommendation of the Special Admissions and Admission
              Irregularities Committee, has approved your transfer from <strong>{app.from_programme}</strong> to{" "}
              <strong>{app.to_programme}</strong>{level} for the {app.session} session.
            </p>
          )}
          <p>
            {fee ? <>{fee} </> : null}
            {effected
              ? "Proceed to your new department to register your courses for the session."
              : "Once the Registry gives the transfer effect on the register, proceed to your new department to register your courses for the session."}
            {" "}Your matriculation number remains unchanged.
          </p>
          <p>Please accept the congratulations of the University.</p>
          <p style={{ marginTop: "var(--s-8)" }}>
            ____________________________<br />
            <strong>Deputy Registrar, Academic Office</strong><br />
            for: Registrar
          </p>
        </div>

        <footer className="rpt__foot">
          This letter is generated from the Unified University Portal and is valid with the University&rsquo;s record of the approved transfer. {effected ? "The transfer has been effected on the register." : "The transfer is effected on the register once the fee is paid in full."}
        </footer>
      </div>
    </div>
  );
}
