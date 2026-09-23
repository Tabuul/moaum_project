"use client";

/** The two lists behind the Head of Department's fees tile — the students cleared for registration this
 *  session and the students still owing — each as a formatted Excel workbook, read from the register the
 *  moment it is pressed: matric number, name, programme, level, charged, paid, balance. */
import { useState } from "react";
import { buildXlsx, loadCrest } from "@/lib/xlsx";

interface Row { matric_no: string | null; surname: string; other_names: string; programme: string; level: number; status: string; charged: number; paid: number }

export function HodFeeDownloads({ session, cleared, owing, deptName }: { session: string; cleared: number; owing: number; deptName: string }) {
  const [busy, setBusy] = useState<"cleared" | "owing" | null>(null);
  const [err, setErr] = useState<string | null>(null);

  async function download(which: "cleared" | "owing") {
    setBusy(which); setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/hod/fees?session=${encodeURIComponent(session)}&which=${which}`, { cache: "no-store" });
      if (!r.ok) { setErr(`Could not read the list (${r.status})`); return; }
      const rows = (await r.json()) as Row[];
      const logo = await loadCrest();
      const title = which === "cleared" ? `Cleared for registration · ${session}` : `Still owing for ${session}`;
      const blob = buildXlsx(
        ["Matric no.", "Surname", "Other names", "Programme", "Level", "Status", "Charged (NGN)", "Paid (NGN)", "Balance (NGN)"],
        rows.map((x) => [x.matric_no, x.surname, x.other_names, x.programme, Number(x.level), x.status, Number(x.charged), Number(x.paid), Number(x.charged) - Number(x.paid)]),
        which === "cleared" ? "Cleared" : "Owing",
        { school: "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", title: `${deptName} — ${title} (${rows.length.toLocaleString()} students)`,
          date: "Read from the register " + new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }), logo: logo ?? undefined },
      );
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = `${which}-${session.replace(/[^0-9]/g, "-")}-${deptName.replace(/[^A-Za-z0-9]+/g, "-").toLowerCase()}.xlsx`;
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    } finally { setBusy(null); }
  }

  const link = (which: "cleared" | "owing", label: string) => (
    <button type="button" onClick={() => void download(which)} disabled={busy !== null}
      style={{ background: "none", border: "none", padding: 0, font: "inherit", color: "var(--chrome)", cursor: "pointer", textDecoration: "underline", textUnderlineOffset: 2 }}>
      {busy === which ? "Preparing…" : label}
    </button>
  );

  return (
    <span style={{ display: "block" }}>
      {owing.toLocaleString()} still owing for {session}
      <span style={{ display: "block", marginTop: 4 }}>
        {link("cleared", `Download the ${cleared.toLocaleString()} cleared`)} · {link("owing", `Download the ${owing.toLocaleString()} owing`)}
      </span>
      {err ? <span style={{ display: "block", color: "var(--red-ink)" }}>{err}</span> : null}
    </span>
  );
}
