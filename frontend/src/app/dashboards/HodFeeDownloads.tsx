"use client";

/** The figures on the Head of Department's fees tile are the downloads: press the number of students
 *  cleared for registration, or the number still owing, and the list behind it comes down as a
 *  formatted Excel workbook read from the register at that moment — matric number, name, programme,
 *  level, charged, paid, balance. No separate link: the number is the link. */
import { useState } from "react";
import { buildXlsx, loadCrest } from "@/lib/xlsx";

interface Row { matric_no: string | null; surname: string; other_names: string; programme: string; level: number; status: string; charged: number; paid: number }

async function downloadList(which: "cleared" | "owing", session: string, deptName: string): Promise<string | null> {
  const r = await fetch(`/api/bff/api/v1/hod/fees?session=${encodeURIComponent(session)}&which=${which}`, { cache: "no-store" });
  if (!r.ok) return `Could not read the list (${r.status})`;
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
  return null;
}

/** a count that downloads its list when pressed; drawn as the number it stands in for */
export function FeeCount({ which, count, session, deptName, size, colour }: {
  which: "cleared" | "owing"; count: number; session: string; deptName: string; size?: number; colour?: string;
}) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  async function go() {
    setBusy(true); setErr(null);
    try { setErr(await downloadList(which, session, deptName)); } finally { setBusy(false); }
  }
  return (
    <>
      <button type="button" onClick={() => void go()} disabled={busy} title={`Download the ${count.toLocaleString()} ${which === "cleared" ? "cleared for registration" : "still owing"} as Excel`}
        style={{ background: "none", border: "none", padding: 0, margin: 0, font: "inherit", fontWeight: 700, color: colour ?? "inherit", cursor: busy ? "wait" : "pointer",
          fontSize: size, lineHeight: 1.1, borderBottom: "2px dotted currentColor", opacity: busy ? 0.6 : 1 }}>
        {count.toLocaleString()}
      </button>
      {err ? <span className="t-sm ink-red" style={{ display: "block", fontWeight: 400 }}>{err}</span> : null}
    </>
  );
}
