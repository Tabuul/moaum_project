"use client";

/**
 * The JUPEB identity cards chosen, front and back side by side at the card's own size (85.6 × 54 mm), five students to an A4
 * page, ready to print, cut and laminate. Each back carries the QR of the card's code, which opens /verify/jupeb/{code}.
 */
import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { IdCardBack, IdCardFront, type IdCardData } from "@/components/proto/idcard";
import { jcall, streamLabel } from "@/lib/jupeb";
import type { CardsData } from "../JupebIdCards";

export function CardSheet({ session, ids, autoPrint }: { session: string; ids: string[]; autoPrint: boolean }) {
  const [cards, setCards] = useState<IdCardData[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    void (async () => {
      const r = await jcall<CardsData>(`/api/v1/jupeb/office/id-cards?session=${encodeURIComponent(session)}`);
      if (!r.ok) { if (live) setError(r.problem.title ?? "The cards could not be read."); return; }
      const rows = r.data.students.filter((s) => ids.includes(s.id) && s.card_code);
      const out: IdCardData[] = [];
      for (const s of rows) {
        const code = s.card_code as string;
        const qr = await QRCode.toDataURL(`${window.location.origin}/verify/jupeb/${code}`, { errorCorrectionLevel: "M", margin: 1, width: 220 });
        out.push({
          name: `${s.surname.toUpperCase()} ${s.first_name}${s.middle_name ? ` ${s.middle_name}` : ""}`, matric: s.application_no, barcode: s.application_no.replace(/[^A-Za-z0-9]/g, ""),
          serial: code, faculty: "", prog: streamLabel(s.stream), level: "", session: s.session, admitted: "", graduates: "", blood: "", expiresShort: "",
          kinPhone: s.next_of_kin_phone ?? "—", photoSrc: `/api/bff/api/v1/jupeb/office/applications/${s.id}/documents/PASSPORT/content?format=jpeg`, tag: "JUPEB",
          rows: [["Programme", streamLabel(s.stream)], ["Combination", s.combination_code ?? "—", true], ["Class", s.class_name ?? "—"], ["Exam No.", s.exam_no ?? "—", true],
            ["Session", s.session, true], ["Status", "Student"]],
          validity: "valid for the session", qrSrc: qr, verifyText: `${window.location.host}/verify/jupeb`, signatory: "JUPEB Office",
        });
      }
      if (live) setCards(out);
    })();
    return () => { live = false; };
  }, [session, ids]);
  useEffect(() => {
    if (!autoPrint || !cards || !cards.length) return;
    /* the photographs load first, then the print dialog opens (not with ?print=0, a look before printing) */
    const t = setTimeout(() => window.print(), 1200);
    return () => clearTimeout(t);
  }, [cards, autoPrint]);
  if (error) return <p style={{ padding: 24 }}>{error}</p>;
  if (!cards) return <p style={{ padding: 24 }}>Preparing the cards…</p>;
  if (!cards.length) return <p style={{ padding: 24 }}>None of the chosen students has a card issued yet.</p>;
  return (
    <div className="jcards">
      <style>{`
        .jcards { padding: 10mm; background: #fff; }
        .jcards__bar { display: flex; gap: 12px; align-items: center; margin-bottom: 8mm; font-family: var(--sans); }
        .jcards__row { display: flex; gap: 8mm; margin-bottom: 6mm; break-inside: avoid; page-break-inside: avoid; }
        .jcards .idc { box-shadow: none; }
        @page { size: A4 portrait; margin: 8mm; }
        @media print { .jcards { padding: 0; } .jcards__bar { display: none; } .jcards__row:nth-child(5n + 1) { break-before: page; } .jcards__row:first-of-type { break-before: auto; } }
      `}</style>
      <div className="jcards__bar">
        <b>{cards.length} JUPEB identity card{cards.length === 1 ? "" : "s"} · {session}</b>
        <button type="button" className="btn btn--primary btn--sm" onClick={() => window.print()}>Print</button>
        <span style={{ color: "#5b6670" }}>Front and back side by side, at the card&rsquo;s own size; print at 100% (no fit to page), cut along the edges and laminate.</span>
      </div>
      {cards.map((c) => (
        <div key={c.serial} className="jcards__row"><IdCardFront c={c} /><IdCardBack c={c} /></div>
      ))}
    </div>
  );
}
