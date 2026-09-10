"use client";

import { useRouter } from "next/navigation";
import { Btn } from "@/components/proto/ui";

/** The no-print controls above a transfer memo: back to the queue, and print. */
export function MemoBar() {
  const router = useRouter();
  return (
    <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
      <Btn kind="ghost" onClick={() => router.push("/transfers")}>← Transfer queue</Btn>
      <span style={{ flexGrow: 1 }} />
      <Btn kind="primary" onClick={() => window.print()}>Print / Save as PDF</Btn>
    </div>
  );
}
