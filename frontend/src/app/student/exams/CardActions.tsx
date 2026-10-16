"use client";

/** The examination card's three acts (V491): view it, download the PDF, print it — each the card the portal's own document engine
 *  draws for the approved registration (the courses, the photograph, the signed QR), each showing at once that it is under way. */
import { Btn } from "@/components/proto/ui";
import { notify } from "@/components/proto/Toast";

async function cardBlob(session: string, semester: number): Promise<Blob | null> {
  const r = await fetch(`/student/exams/card/pdf?session=${encodeURIComponent(session)}&semester=${semester}`, { cache: "no-store" });
  if (!r.ok) {
    const j = await r.json().catch(() => null) as { title?: string; detail?: string } | null;
    notify(j?.detail || j?.title || "The examination card could not be prepared.", "bad");
    return null;
  }
  return r.blob();
}

export function CardActions({ session, semester }: { session: string; semester: number }) {
  const name = `examination-card-${session.replace("/", "-")}-semester-${semester}.pdf`;
  return (
    <div className="row row--inline" style={{ gap: 8, flexWrap: "wrap" }}>
      <Btn kind="primary" busyLabel="Loading exam card..." onClick={async () => {
        const w = window.open("", "_blank");   // opened at the click, so no pop-up blocker stops it
        const b = await cardBlob(session, semester);
        if (!b) { w?.close(); return; }
        const url = URL.createObjectURL(b);
        if (w) w.location.href = url; else window.location.href = url;
      }}>VIEW EXAM CARD</Btn>
      <Btn kind="secondary" busyLabel="Preparing download..." onClick={async () => {
        const b = await cardBlob(session, semester);
        if (!b) return;
        const a = document.createElement("a");
        a.href = URL.createObjectURL(b);
        a.download = name;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(a.href), 2000);
      }}>DOWNLOAD PDF</Btn>
      <Btn kind="ghost" busyLabel="Preparing print..." onClick={async () => {
        const b = await cardBlob(session, semester);
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
      }}>PRINT EXAM CARD</Btn>
    </div>
  );
}
