"use client";

/** V640: a home's kept figures read again now — the server works them out afresh, the page shows the new reading */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn } from "@/components/proto/ui";

export function RefreshFigures({ path = "/api/bff/api/v1/dbops/home?refresh=true" }: { path?: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  return (
    <Btn kind="ghost" size="sm" disabled={busy} onClick={async () => {
      setBusy(true);
      try {
        await fetch(path, { cache: "no-store" });
        router.refresh();
      } finally {
        setBusy(false);
      }
    }}>{busy ? "Reading…" : "Refresh"}</Btn>
  );
}
