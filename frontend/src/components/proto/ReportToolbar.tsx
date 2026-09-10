"use client";

import { useRouter } from "next/navigation";
import { Btn } from "@/components/proto/ui";
import { buildXlsx, loadCrest } from "@/lib/xlsx";

/** The no-print controls above a return: back to the list, print (which is how a
 *  branded PDF is taken — the browser's own print-to-PDF over this document), and
 *  a formatted Excel workbook of the same rows, carrying the crest, University
 *  name, title and date. The header and rows are built by the server page. */
export function ReportToolbar({ headers, rows, filename, title }: {
  headers: string[]; rows: (string | number | null)[][]; filename: string; title?: string;
}) {
  const router = useRouter();

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

  return (
    <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
      <Btn kind="ghost" onClick={() => router.push("/reports")}>← All returns</Btn>
      <span style={{ flexGrow: 1 }} />
      <Btn kind="ghost" onClick={download}>Download Excel</Btn>
      <Btn kind="primary" onClick={() => window.print()}>Print / Save as PDF</Btn>
    </div>
  );
}
