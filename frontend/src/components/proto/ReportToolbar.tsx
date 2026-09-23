"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn } from "@/components/proto/ui";
import { buildXlsx, loadCrest } from "@/lib/xlsx";

/** what a kept copy of this return records (V229): which return, the period it answers, the due date
 *  it is filed against, and the footing note — the rows come from the toolbar's own headers/rows */
export interface KeepSpec {
  report: string;
  period: string;
  subtitle?: string;
  totals?: Record<string, string | number | null> | null;
  note?: string;
  dueOn?: string | null;
}

/** The no-print controls above a return: back to the list, print (which is how a
 *  branded PDF is taken — the browser's own print-to-PDF over this document), a
 *  formatted Excel workbook of the same rows, carrying the crest, University
 *  name, title and date, and — when the page says which return this is — "Keep a
 *  copy", which files the rows as they are with a verification code (V229).
 *  The header and rows are built by the server page. */
export function ReportToolbar({ headers, rows, filename, title, keep }: {
  headers: string[]; rows: (string | number | null)[][]; filename: string; title?: string; keep?: KeepSpec;
}) {
  const router = useRouter();
  const [keeping, setKeeping] = useState(false);
  const [kept, setKept] = useState<{ id: string; verification_code: string } | null>(null);
  const [err, setErr] = useState<string | null>(null);

  function download() {
    const base = filename.replace(/\.(csv|xlsx)$/i, "");
    const date = "Generated " + new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
    void loadCrest().then((logo) => {
      const blob = buildXlsx(headers, rows, base.replace(/[\\/?*[\]:]/g, "-").slice(0, 31) || "Return", {
        school: "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI",
        title: title ?? base.replace(/[-_]+/g, " ").trim(),
        date,
        logo: logo ?? undefined,
      });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = base + ".xlsx";
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    });
  }

  async function keepCopy() {
    if (!keep) return;
    setKeeping(true); setErr(null);
    try {
      const parameters: Record<string, string> = {};
      new URLSearchParams(window.location.search).forEach((v, k) => { parameters[k] = v; });
      const dueOn = keep.dueOn ?? parameters.due ?? null;
      const r = await fetch("/api/bff/api/v1/reports/snapshots", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": `Kept a copy of ${keep.report} for ${keep.period}` },
        body: JSON.stringify({
          report: keep.report, title: title ?? keep.report, subtitle: keep.subtitle ?? null, period: keep.period,
          parameters, dueOn, headers, rows, totals: keep.totals ?? null, note: keep.note ?? null,
        }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr((j && (j.detail || j.title)) || `Could not keep the copy (${r.status})`); return; }
      setKept(j);
    } finally {
      setKeeping(false);
    }
  }

  return (
    <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
      <Btn kind="ghost" onClick={() => router.push("/reports")}>← All returns</Btn>
      {kept ? (
        <span className="sub2">Copy kept · verification code <b className="tnum">{kept.verification_code}</b> · <a href={`/reports/snapshots/${kept.id}`}>open the kept copy</a></span>
      ) : err ? <span className="sub2" style={{ color: "var(--red-ink)" }}>{err}</span> : null}
      <span style={{ flexGrow: 1 }} />
      {keep && !kept ? <Btn kind="go" onClick={() => void keepCopy()} disabled={keeping || !rows.length}>{keeping ? "Keeping…" : "Keep a copy"}</Btn> : null}
      <Btn kind="ghost" onClick={download}>Download Excel</Btn>
      <Btn kind="primary" onClick={() => window.print()}>Print / Save as PDF</Btn>
    </div>
  );
}
