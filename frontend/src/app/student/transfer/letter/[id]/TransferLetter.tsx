"use client";

/** A branded, printable inter-departmental transfer approval letter. It renders as a
 *  standalone document (the .rpt paper styling used by the returns) so it prints clean. */
import { naira } from "../../../common";

export interface LetterApp {
  id: string; from_programme: string; from_level: number; to_programme: string; recommended_level: number | null;
  state: string; session: string; fee_reference: string | null; fee_confirmed_at: string | null;
}

export function TransferLetter({ student, app }: { student: { name: string; matric_no: string | null; programme: string }; app: LetterApp }) {
  const today = new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
  return (
    <div className="rpt">
      <div className="rpt__toolbar no-print" style={{ display: "flex", gap: 8 }}>
        <button className="btn btn--primary" onClick={() => window.print()}>Print / Save as PDF</button>
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

        <div style={{ padding: "8px 4px", lineHeight: 1.7, fontSize: 14 }}>
          <p style={{ textAlign: "right" }}>{today}</p>
          <p><strong>{student.name}</strong><br />{student.matric_no ?? ""}</p>
          <p>Dear Student,</p>
          <p className="b700">APPROVAL OF INTER-DEPARTMENTAL TRANSFER</p>
          <p>
            I am directed to inform you that the Senate, on the recommendation of the Special Admissions and Admission
            Irregularities Committee, has approved your transfer from <strong>{app.from_programme}</strong> to{" "}
            <strong>{app.to_programme}</strong>{app.recommended_level ? <> at <strong>{app.recommended_level} Level</strong></> : null} for the {app.session} session.
          </p>
          <p>
            To complete the process you are to pay the non-refundable processing fee of <strong>{naira(10000)}</strong> against the
            reference {app.fee_reference ? <span className="tnum">{app.fee_reference}</span> : "generated on your transfer page"},
            {app.fee_confirmed_at ? " which the University has received," : " print this letter,"} and proceed to your new
            department to register your courses for the session. Your matriculation number remains unchanged.
          </p>
          <p>Please accept the congratulations of the University.</p>
          <p style={{ marginTop: 36 }}>
            ____________________________<br />
            <strong>Deputy Registrar, Academic Office</strong><br />
            for: Registrar
          </p>
        </div>

        <footer className="rpt__foot">
          This letter is generated from the Unified University Portal and is valid with the University&rsquo;s record of the approved transfer. {app.state === "EFFECTED" ? "The transfer has been effected on the register." : "The transfer is effected once the fee is confirmed."}
        </footer>
      </div>
    </div>
  );
}
