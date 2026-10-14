"use client";

/**
 * An applicant's receipt checked by QR, on screen: the code the API signed over the reference (read from the receipt the
 * applicant may open), the QR to the public verification page drawn from it, and the receipt's PDF to download or open for
 * printing — the PDF carries the same QR. The Post-UTME and CCE fee screens and the postgraduate portal draw it alike.
 */
import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { applicantReceiptVerifyPath } from "@/lib/applicant-receipt";

export function ReceiptCheck({ reference, source, pdf }: {
  reference: string;
  /** the API address (through the BFF) of the receipt, which carries check_code */
  source: string;
  /** the receipt's PDF route; "&download=1" asks for it as a file */
  pdf: string;
}) {
  const [check, setCheck] = useState<{ code: string; qr: string } | null>(null);
  useEffect(() => {
    let live = true;
    fetch(source, { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .then(async (x: { check_code?: string | null } | null) => {
        if (!x?.check_code) return;
        const qr = await QRCode.toDataURL(`${window.location.origin}${applicantReceiptVerifyPath(reference, x.check_code)}`, { errorCorrectionLevel: "M", margin: 1, width: 220 });
        if (live) setCheck({ code: x.check_code, qr });
      })
      .catch(() => undefined);
    return () => { live = false; };
  }, [reference, source]);
  return (
    <div className="row row--top" style={{ gap: "var(--s-4)" }}>
      {check
        // eslint-disable-next-line @next/next/no-img-element
        ? <img src={check.qr} alt={`QR code that verifies receipt ${reference}`} width={132} height={132} style={{ flexShrink: 0 }} />
        : <div className="sub2" style={{ width: 132, height: 132, display: "grid", placeItems: "center", border: "1px dashed var(--line)", flexShrink: 0 }}>QR code…</div>}
      <div style={{ minWidth: 200, flex: 1 }}>
        <div className="eyebrow">Scan to verify</div>
        <div className="sub2 mt-1">The QR opens the University&rsquo;s verification page, which shows the Bursary&rsquo;s record of this payment: the payer, the fee and the amount there prevail over any copy.</div>
        {check ? <div className="mt-1">Check code <b className="tnum">{check.code}</b></div> : null}
        <div className="row row--inline row--tight mt-2">
          <a className="btn btn--primary btn--sm" href={`${pdf}${pdf.includes("?") ? "&" : "?"}download=1`}>Download receipt (PDF)</a>
          <a className="btn btn--ghost btn--sm" href={pdf} target="_blank" rel="noopener">Open to print</a>
        </div>
      </div>
    </div>
  );
}
