"use client";

/** The kept copy's own controls: back, Excel of the kept rows, print, and — until it is done —
 *  "Mark as filed": with whom the return went (NUC, JAMB, Council, the State treasury …). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { buildXlsx, loadCrest } from "@/lib/xlsx";

export function FileReturn({ id, title, headers, rows, filedTo }: {
  id: string; title: string; headers: string[]; rows: (string | number | null)[][]; filedTo: string | null;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [to, setTo] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function file() {
    setBusy(true); setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/reports/snapshots/${id}/file`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": `Filed ${title} with ${to}` },
        body: JSON.stringify({ filedTo: to.trim(), note: note.trim() || null }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr((j && (j.detail || j.title)) || `Could not record the filing (${r.status})`); return; }
      setOpen(false); router.refresh();
    } finally { setBusy(false); }
  }

  function download() {
    void loadCrest().then((logo) => {
      const blob = buildXlsx(headers, rows, "Kept copy", {
        school: "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", title,
        date: "Kept copy · exported " + new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }), logo: logo ?? undefined,
      });
      const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `${title.replace(/[^\w]+/g, "-").toLowerCase()}-kept.xlsx`;
      document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    });
  }

  return (
    <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
      <Btn kind="ghost" onClick={() => router.push("/reports")}>← All returns</Btn>
      <span className="sub2">{filedTo ? `Filed with ${filedTo}` : "Kept, not yet filed"}</span>
      <span style={{ flexGrow: 1 }} />
      {!filedTo ? <Btn kind="go" onClick={() => { setErr(null); setOpen(true); }}>Mark as filed</Btn> : null}
      <Btn kind="ghost" onClick={download}>Download Excel</Btn>
      <Btn kind="primary" onClick={() => window.print()}>Print / Save as PDF</Btn>
      {open ? (
        <Modal title="Record the filing" sub={title} onClose={() => setOpen(false)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="primary" disabled={busy || !to.trim()} onClick={() => void file()}>{busy ? "Recording…" : "Filed"}</Btn></>}>
          {err ? <div className="sub2" style={{ color: "var(--red-ink)", marginBottom: 8 }}>{err}</div> : null}
          <Field id="fr-to" label="Filed with" hint="The body the return went to — NUC, JAMB, Council, the State treasury, Senate, management">
            <input id="fr-to" className="ctl" value={to} onChange={(e) => setTo(e.target.value)} autoComplete="off" list="fr-to-list" />
            <datalist id="fr-to-list">{["NUC", "JAMB", "Council", "State treasury", "Senate", "Management", "School Board"].map((x) => <option key={x} value={x} />)}</datalist>
          </Field>
          <Field id="fr-note" label="Note" hint="Reference, covering letter number, or how it was sent — optional">
            <input id="fr-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} autoComplete="off" />
          </Field>
        </Modal>
      ) : null}
    </div>
  );
}
