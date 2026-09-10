"use client";

import { useRouter } from "next/navigation";
import { Btn } from "@/components/proto/ui";
import { buildXlsx } from "@/lib/xlsx";

/** The no-print controls above a return: back to the list, print (which is how a
 *  branded PDF is taken — the browser's own print-to-PDF over this document), and
 *  a formatted Excel workbook of the same rows. The header and rows are built by
 *  the server page and passed in, so what downloads is exactly what prints. */
export function ReportToolbar({ headers, rows, filename }: {
  headers: string[]; rows: (string | number | null)[][]; filename: string;
}) {
  const router = useRouter();

  function download() {
    const base = filename.replace(/\.(csv|xlsx)$/i, "");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(buildXlsx(headers, rows, base.replace(/[\\/?*[\]:]/g, "-").slice(0, 31) || "Return"));
    a.download = base + ".xlsx";
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
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
