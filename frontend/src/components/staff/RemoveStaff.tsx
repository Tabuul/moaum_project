"use client";
/**
 * V656: the delete dialog for staff, teaching and non-academic alike. The server previews what happens to each person first —
 * tied to no record, deleted permanently; tied to records, deactivated and kept; or left as they are, with why — then, with a
 * reason, does it. Nothing is decided here: the database reads what each person is tied to.
 */
import { useEffect, useMemo, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import {
  MODES, OUTCOME, REMOVE_REASONS, confirmLabel, outcomeWord, reasonProblem, summaryLine, tally, tiesText,
  type RemovalMode, type RemovalResult, type RemovalRow, type StaffPick,
} from "@/lib/staff-removal";

export function RemoveStaff({ people, what, onClose, onDone }: {
  people: StaffPick[]; what: string; onClose: () => void; onDone: (message: string) => void;
}) {
  const [mode, setMode] = useState<RemovalMode>("AUTO");
  // the preview as last read, and the mode and people it was read for: it is "reading" until it matches what is asked
  const [read, setRead] = useState<{ for: string; rows: RemovalRow[] | null; problem: Problem | null } | null>(null);
  const [code, setCode] = useState("");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const key = people.map((p) => p.id).join(",");
  const asked = `${mode}|${key}`;
  const reading = !read || read.for !== asked;
  const rows = reading ? null : read.rows;

  // the server's preview: what happens to each person in this mode; nothing written
  useEffect(() => {
    let live = true;
    const [m, ids] = asked.split("|");
    fetch("/api/bff/api/v1/iam/staff/remove/preview", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ids: ids.split(","), mode: m }),
    })
      .then(async (r) => {
        const j = await r.json().catch(() => null);
        if (!live) return;
        if (!r.ok) setRead({ for: asked, rows: null, problem: j ?? { status: r.status, title: r.statusText } });
        else setRead({ for: asked, rows: j as RemovalRow[], problem: null });
      })
      .catch(() => { if (live) setRead({ for: asked, rows: null, problem: { status: 0, title: "The preview could not be read. Try again." } }); });
    return () => { live = false; };
  }, [asked]);

  const t = useMemo(() => tally(rows ?? []), [rows]);
  const why = reasonProblem(code, text);
  const nothing = t.remove + t.deactivate === 0;

  async function confirm() {
    if (why || nothing) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/iam/staff/remove", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${what}: ${confirmLabel(t).toLowerCase()} (${REMOVE_REASONS.find(([c]) => c === code)?.[1] ?? code})`) },
        body: JSON.stringify({ ids: key.split(","), mode, reasonCode: code, reason: text.trim() || null }),
      });
      const j = (await r.json().catch(() => null)) as RemovalResult | Problem | null;
      if (!r.ok || !j || !("rows" in j)) {
        const p = (j as Problem) ?? { status: r.status, title: r.statusText };
        setProblem(p); notifyProblem(p); return;
      }
      const parts = [j.removed ? `${j.removed} deleted` : "", j.deactivated ? `${j.deactivated} deactivated` : "", j.refused ? `${j.refused} left as they were` : ""].filter(Boolean);
      notify(parts.join(" · ") || "Nothing changed");
      onDone(parts.join(" · ") + ".");
    } finally { setBusy(false); }
  }

  return (
    <Modal wide title={people.length === 1 ? `Delete ${people[0].name}` : `Delete ${people.length} staff members`}
      sub={reading ? "Checking what each person is tied to…" : summaryLine(t)} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" />
        <Btn kind="urgent" disabled={busy || reading || nothing || !!why} onClick={() => void confirm()}>{busy ? "Working…" : confirmLabel(t)}</Btn>
      </>}>
      {problem ? <ProblemNotice problem={problem} /> : !reading && read?.problem ? <ProblemNotice problem={read.problem} /> : null}
      <Note kind="info" title="Records are never lost">
        A person tied to no record (added by mistake, never used) is deleted permanently. A person tied to anything (a class taught, a
        score sheet, a decision, a sign-in) is <b>deactivated</b>: taken off every list, unable to sign in, their offices ended, and
        everything they did kept. A deactivated person can be restored from <b>Removed staff</b>.
      </Note>
      <div className="grid grid--2 mt-2">
        <Field id="rs-mode" label="What to do" hint={MODES.find(([m]) => m === mode)?.[2]}>
          <select id="rs-mode" className="ctl" value={mode} onChange={(e) => setMode(e.target.value as RemovalMode)}>
            {MODES.map(([m, label]) => <option key={m} value={m}>{label}</option>)}
          </select>
        </Field>
        <Field id="rs-reason" label="Reason" hint="Kept with the record of the change">
          <select id="rs-reason" className="ctl" value={code} onChange={(e) => setCode(e.target.value)}>
            <option value="">Choose…</option>
            {REMOVE_REASONS.map(([c, label]) => <option key={c} value={c}>{label}</option>)}
          </select>
        </Field>
      </div>
      <Field id="rs-text" label={code === "OTHER" ? "Describe the reason" : "Note (optional)"}>
        <input id="rs-text" className="ctl" value={text} maxLength={500} onChange={(e) => setText(e.target.value)}
          placeholder={code === "OTHER" ? "At least a few words" : "e.g. the letter or memo it follows"} />
      </Field>
      {rows ? (
        <DTable cols={["Staff id", "Name", "Tied to", "What happens"]} rows={rows.map((r) => [
          <span className="tnum b700" key="i">{r.staff_number ?? "—"}</span>,
          <span key="n">{r.name ?? people.find((p) => p.id === r.person_id)?.name ?? "—"}</span>,
          <span key="t" className="sub2">{tiesText(r.ties ?? [])}</span>,
          <span key="o"><Pil kind={OUTCOME[r.outcome]?.kind ?? "grey"}>{outcomeWord(r.outcome)}</Pil>{r.detail && !["REMOVE", "DEACTIVATE"].includes(r.outcome) ? <div className="sub2">{r.detail}</div> : null}</span>,
        ])} />
      ) : null}
      {code && why && !reading ? <div className="sub2 ink-red mt-2">{why}</div> : null}
    </Modal>
  );
}
