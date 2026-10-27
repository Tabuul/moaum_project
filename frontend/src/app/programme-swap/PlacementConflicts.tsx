"use client";

/**
 * V669: what the old-portal uploads named against a placement this portal recorded. A student moved by a transfer, a programme swap or
 * the restoration of a transfer approved on the old portal is never moved back by an upload: the record keeps its programme and level,
 * and the file's are listed here. The Academic Office keeps the recorded placement, or applies the file's by a programme swap (made at
 * once, the history kept) — each with the reason.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal, day } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { CONFLICT_WORDS, SOURCE_WORDS, conflictWords, type PlacementConflict } from "@/lib/programme-swap";
import { swapPost } from "./swap-call";

type Decision = { row: PlacementConflict; decision: "KEEP" | "APPLY" };

export function PlacementConflicts({ rows, mayDecide }: { rows: PlacementConflict[]; mayDecide: boolean }) {
  const router = useRouter();
  const [act, setAct] = useState<Decision | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const open = rows.filter((r) => r.status === "REQUIRES_REVIEW").length;

  async function decide() {
    if (!act) return;
    setBusy(true);
    try {
      const r = await swapPost<{ status: string }>(`/placement-conflicts/${act.row.id}/decide`, { decision: act.decision, note: note.trim() },
        `Placement conflict of ${act.row.matric_no ?? act.row.name}: ${act.decision === "KEEP" ? "recorded placement kept" : "upload's placement applied"}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(act.decision === "KEEP" ? `${act.row.name}: the recorded placement is kept` : `${act.row.name}: moved to ${act.row.file_programme_name ?? act.row.file_programme} by a programme swap`);
      setAct(null); setNote("");
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <>
      <Note kind="info" title="An upload never moves a recorded placement back">
        A student whose programme this portal recorded — by an inter-departmental transfer, a programme swap or a transfer approved on the old portal and
        restored — keeps it when an old-portal file names another. The file&rsquo;s programme and level are listed here for the Academic Office: keep the record,
        or apply the file&rsquo;s (a programme swap, the history kept). The matriculation number is never the measure of either.
      </Note>
      <Panel title="Upload conflicts" right={`${open} awaiting · ${rows.length} listed`}>
        {rows.length ? (
          <DTable cols={["Student", "The upload named", "The record kept", "Status", "|num"]} rows={rows.map((r) => [
            <span key="s"><LinkBtn kind="ghost" size="sm" href={`/programme-swap/${r.student_id}`}>{r.name}</LinkBtn>
              <div className="sub2 tnum">{r.matric_no ?? r.jamb_reg_no ?? "—"} · {SOURCE_WORDS[r.source] ?? r.source}</div></span>,
            <span key="f">{r.file_programme_name ?? r.file_programme}{r.file_level ? <div className="sub2">{r.file_level} Level</div> : null}</span>,
            <span key="k">{r.kept_programme_name ?? r.kept_programme}{r.kept_level ? <div className="sub2">{r.kept_level} Level · set by {r.settled_by}</div> : <div className="sub2">set by {r.settled_by}</div>}</span>,
            <span key="t"><Pil kind={r.status === "REQUIRES_REVIEW" ? "warn" : r.status === "KEPT" ? "ok" : "info"}>{CONFLICT_WORDS[r.status]}</Pil>
              <div className="sub2 tnum">seen {r.seen}× · {day(r.last_seen)}</div>
              {r.note ? <div className="sub2">{r.note}{r.swap_ref ? ` (${r.swap_ref})` : ""}</div> : null}</span>,
            r.status === "REQUIRES_REVIEW" && mayDecide ? (
              <span key="a" className="row row--tight">
                <Btn kind="ghost" size="sm" onClick={() => { setAct({ row: r, decision: "KEEP" }); setNote(""); }}>Keep the record</Btn>
                <Btn kind="secondary" size="sm" onClick={() => { setAct({ row: r, decision: "APPLY" }); setNote(""); }}>Apply the upload&rsquo;s</Btn>
              </span>
            ) : <span key="a" />,
          ])} />
        ) : <PBody><div className="sub2">No upload has named another programme or level for a placement this portal recorded.</div></PBody>}
      </Panel>
      {act ? (
        <Modal title={act.decision === "KEEP" ? "Keep the recorded placement" : "Apply the upload's placement"} onClose={() => setAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setAct(null)}>Cancel</Btn>
            <Btn kind="primary" busy={busy} busyLabel="Saving…" disabled={note.trim().length < 10} onClick={() => void decide()}>{act.decision === "KEEP" ? "Keep the record" : "Apply and move the student"}</Btn></>}>
          <div>{conflictWords(act.row)}.</div>
          {act.decision === "APPLY" ? <Note kind="bad" title="The student is moved">A programme swap puts the student on {act.row.file_programme_name ?? act.row.file_programme}
            {act.row.file_level ? ` at ${act.row.file_level} Level` : ""}, made at once; the recorded placement stays in the programme history.</Note> : null}
          <Field id="pc-note" label="Reason" hint="Ten characters or more; kept on the record and the audit trail" full>
            <textarea id="pc-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
