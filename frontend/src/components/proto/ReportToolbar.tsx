"use client";

import { useRouter } from "next/navigation";
import { Btn } from "@/components/proto/ui";

/** The no-print controls above a return: back to the list, print (which is how a
 *  branded PDF is taken — the browser's own print-to-PDF over this document), and
 *  a CSV of the same rows for a spreadsheet. The CSV is built by the server page
 *  and passed in, so what downloads is exactly what prints. */
export function ReportToolbar({ csv, filename }: { csv: string; filename: string }) {
  const router = useRouter();

  function download() {
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  return (
    <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
      <Btn kind="ghost" onClick={() => router.push("/reports")}>← All returns</Btn>
      <span style={{ flexGrow: 1 }} />
      <Btn kind="ghost" onClick={download}>Download CSV</Btn>
      <Btn kind="primary" onClick={() => window.print()}>Print / Save as PDF</Btn>
    </div>
  );
}
