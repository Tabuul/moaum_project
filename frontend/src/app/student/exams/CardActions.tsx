"use client";

/** The examination card's three acts (V491): view it, download the PDF, print it — each the card the portal's own document engine
 *  draws for the approved registration (the courses, the photograph, the signed QR), each showing at once that it is under way.
 *  V492: the GST & EPS examination permit has the same three, each counted by the API as it is issued (view, download, print). */
import { Btn } from "@/components/proto/ui";
import { notify } from "@/components/proto/Toast";

type Act = "view" | "download" | "print";

async function pdfBlob(url: string, what: string): Promise<Blob | null> {
  const r = await fetch(url, { cache: "no-store" });
  if (!r.ok) {
    const j = await r.json().catch(() => null) as { title?: string; detail?: string } | null;
    notify(j?.detail || j?.title || `The ${what} could not be prepared.`, "bad");
    return null;
  }
  return r.blob();
}

function DocumentActions({ url, what, file, labels }: {
  url: (act: Act) => string; what: string; file: string;
  labels: { view: string; viewBusy: string; download: string; downloadBusy: string; print: string; printBusy: string };
}) {
  return (
    <div className="row row--inline" style={{ gap: 8, flexWrap: "wrap" }}>
      <Btn kind="primary" busyLabel={labels.viewBusy} onClick={async () => {
        const w = window.open("", "_blank");   // opened at the click, so no pop-up blocker stops it
        const b = await pdfBlob(url("view"), what);
        if (!b) { w?.close(); return; }
        const href = URL.createObjectURL(b);
        if (w) w.location.href = href; else window.location.href = href;
      }}>{labels.view}</Btn>
      <Btn kind="secondary" busyLabel={labels.downloadBusy} onClick={async () => {
        const b = await pdfBlob(url("download"), what);
        if (!b) return;
        const a = document.createElement("a");
        a.href = URL.createObjectURL(b);
        a.download = file;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(a.href), 2000);
        notify(`The ${what} is downloaded.`, "ok");
      }}>{labels.download}</Btn>
      <Btn kind="ghost" busyLabel={labels.printBusy} onClick={async () => {
        const b = await pdfBlob(url("print"), what);
        if (!b) return;
        const frame = document.createElement("iframe");
        frame.style.position = "fixed";
        frame.style.width = "0";
        frame.style.height = "0";
        frame.style.border = "0";
        frame.src = URL.createObjectURL(b);
        frame.onload = () => { try { frame.contentWindow?.focus(); frame.contentWindow?.print(); } catch { window.open(frame.src, "_blank"); } };
        document.body.appendChild(frame);
        setTimeout(() => { frame.remove(); }, 120000);
      }}>{labels.print}</Btn>
    </div>
  );
}

export function CardActions({ session, semester }: { session: string; semester: number }) {
  return (
    <DocumentActions what="examination card" file={`examination-card-${session.replace("/", "-")}-semester-${semester}.pdf`}
      url={() => `/student/exams/card/pdf?session=${encodeURIComponent(session)}&semester=${semester}`}
      labels={{ view: "VIEW EXAM CARD", viewBusy: "Loading exam card...", download: "DOWNLOAD PDF", downloadBusy: "Preparing download...", print: "PRINT EXAM CARD", printBusy: "Preparing print..." }} />
  );
}

/** V492: the GST & EPS examination permit — the student's own, for the semester; the session is the API's */
export function PermitActions({ session, semester }: { session: string; semester: number }) {
  return (
    <DocumentActions what="GST & EPS permit" file={`gst-eps-permit-${session.replace("/", "-")}-semester-${semester}.pdf`}
      url={(act) => `/student/exams/gst-eps-permit/pdf?semester=${semester}&act=${act}`}
      labels={{ view: "VIEW PERMIT", viewBusy: "Loading permit...", download: "DOWNLOAD PDF", downloadBusy: "Preparing permit...", print: "PRINT PERMIT", printBusy: "Preparing print..." }} />
  );
}
