"use client";

/**
 * V648: one fee line — what it is and whether it has been used (View), and every version of it (History): created, edited, the
 * corrected line stated beside it, replaced, deactivated, removed — with who, when and why, from the audit trail. Read when opened.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil, Spinner } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { USED_WORDS, VERSION_WORDS, type LineUsage, type LineVersion } from "@/lib/fee-setup";
import { FeeLineDetails, type RemoveLine } from "./FeeLineRemove";

const naira = (n: number | string | null | undefined) => (n == null ? "—" : `₦${Number(n).toLocaleString("en-NG")}`);
const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

function useRead<T>(url: string): { data: T | null; failed: string | null } {
  const [data, setData] = useState<T | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    fetch(url, { cache: "no-store" }).then(async (r) => {
      const j = await r.json().catch(() => null);
      if (!alive) return;
      if (!r.ok) { setFailed((j as Problem | null)?.detail ?? (j as Problem | null)?.title ?? r.statusText); return; }
      setData(j as T);
    }).catch(() => { if (alive) setFailed("The portal could not reach the server."); });
    return () => { alive = false; };
  }, [url]);
  return { data, failed };
}

/** View: the line and its use, as the database decides it */
export function FeeLineView({ session, line, status, levelProblem, removed = false, onClose, onHistory }: {
  session: string; line: RemoveLine; status: string; levelProblem: string | null; removed?: boolean; onClose: () => void; onHistory: (() => void) | null;
}) {
  const { data, failed } = useRead<LineUsage[]>(`/api/bff/api/v1/finance/sessions/${session}/schedule/usage?ids=${encodeURIComponent(line.id)}`);
  const u = data?.[0] ?? null;
  return (
    <Modal title="Fee structure" sub={session} onClose={onClose}
      foot={<>{onHistory ? <Btn kind="ghost" onClick={onHistory}>View history</Btn> : null}<span className="grow" /><Btn kind="secondary" onClick={onClose}>Close</Btn></>}>
      <FeeLineDetails session={session} line={line} status={status} />
      {levelProblem ? <Note kind="bad" title="Level outside the programme structure">{levelProblem}</Note> : null}
      {removed ? <Note kind="info" title="Removed permanently">It was never used: no student was charged by it and no invoice, payment or ledger entry was made under it. Its history keeps it as it was.</Note>
        : failed ? <Note kind="bad" title="Its use could not be read">{failed}</Note>
        : data && !data.length ? <Note kind="info" title="Not on the schedule">This line is no longer on the schedule.</Note>
        : !u ? <div className="row row--tight mt-2 sub2" role="status" aria-live="polite"><Spinner /> Checking financial dependencies…</div>
        : (
          <Note kind={u.used_by === "NONE" ? "ok" : u.used_by === "STUDENTS" ? "info" : "bad"} title={<span className="row row--tight">Use <Pil kind={USED_WORDS[u.used_by][1]}>{USED_WORDS[u.used_by][0]}</Pil></span>}>
            {u.message}
            <div className="sub2 mt-2">
              {u.students.toLocaleString()} student{u.students === 1 ? "" : "s"} charged now · {u.references_generated.toLocaleString()} invoice{u.references_generated === 1 ? "" : "s"} ·{" "}
              {u.references_paid.toLocaleString()} paid ({naira(u.amount_paid)}) · {u.ledger_entries.toLocaleString()} ledger entr{u.ledger_entries === 1 ? "y" : "ies"}
            </div>
          </Note>
        )}
    </Modal>
  );
}

/** History: every version of the line */
export function FeeLineHistory({ session, line, onClose }: { session: string; line: { id: string; item: string }; onClose: () => void }) {
  const { data, failed } = useRead<LineVersion[]>(`/api/bff/api/v1/finance/sessions/${session}/schedule/${line.id}/history`);
  return (
    <Modal wide title={`History · ${line.item}`} sub={session} onClose={onClose} foot={<><span className="grow" /><Btn kind="secondary" onClick={onClose}>Close</Btn></>}>
      {failed ? <Note kind="bad" title="The history could not be read">{failed}</Note>
        : !data ? <div className="row row--tight sub2" role="status" aria-live="polite"><Spinner /> Reading the history…</div>
        : !data.length ? <div className="sub2">No change is recorded for this line.</div>
        : (
          <DTable pageSize={25} cols={["Version|num", "When|mid", "Change", "Item", "Level|num", "Amount|num", "By", "Reason"]} rows={data.map((v) => [
            <span key="n" className="tnum">{v.version}</span>,
            <span key="w" className="tnum sub2">{when(v.at)}</span>,
            <span key="c">{VERSION_WORDS[v.action] ?? v.action}{v.ended && v.action !== "REMOVED" && v.action !== "DEACTIVATED" && v.action !== "REPLACED" ? <span className="sub2"> · ended</span> : null}</span>,
            <span key="i">{v.item ?? "—"}{v.programme_code || v.faculty_code ? <span className="sub2"> · {[v.programme_code, v.faculty_code].filter(Boolean).join(" · ")}</span> : null}</span>,
            <span key="l" className="tnum">{v.level ?? "Every"}</span>,
            <span key="a" className="tnum">{naira(v.amount)}</span>,
            <span key="b" className="sub2">{v.by_name ?? v.office ?? "—"}</span>,
            <span key="r" className="sub2">{v.reason ?? "—"}</span>,
          ])} />
        )}
    </Modal>
  );
}
