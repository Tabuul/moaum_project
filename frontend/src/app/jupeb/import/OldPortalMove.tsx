"use client";
/** V659: an old-portal upload filed under the wrong session, moved — each upload with the sessions its students are in, and for one
 *  of them the server's judgement of every student before anything moves (their subjects and payments go with them, their class is
 *  left and the papers stating the old session are revoked); students who applied on this portal or are tied to the old session
 *  (the Board, results, attendance) stay where they are */
import { useCallback, useEffect, useState } from "react";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { jcall, when } from "@/lib/jupeb";

interface Batch { ref: string; file_name: string | null; imported_at: string; applied: number; sessions: { session: string; students: number }[] }
interface Judged {
  applicationId: string; applicationNo: string; name: string; session: string; state: string; status: string; message: string | null;
  subjects: number; payments: number; papers: number; className: string | null;
}
interface MoveResult { to: string; committed: boolean; moved: number; movable: number; left: number; rows: Judged[] }

const STATUS: Record<string, [string, "ok" | "warn" | "bad" | "grey"]> = {
  MOVE: ["Will move", "ok"], NOT_OLD_PORTAL: ["Applied on this portal", "grey"], SAME_SESSION: ["Already there", "grey"], WITHDRAWN: ["Withdrawn", "grey"],
  BOARD_REGISTERED: ["Registered with the Board", "warn"], RESULTS: ["Has results", "warn"], ATTENDANCE: ["Has attendance", "warn"],
  ACCOUNT_IN_TARGET: ["Login already in that session", "bad"],
};

export function OldPortalMove() {
  const [batches, setBatches] = useState<Batch[] | null>(null);
  const [sessions, setSessions] = useState<string[]>([]);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [moving, setMoving] = useState<Batch | null>(null);

  const apply = useCallback((r: Awaited<ReturnType<typeof jcall<{ batches: Batch[]; sessions: { session: string }[] }>>>) => {
    if (r.ok) { setBatches(r.data.batches); setSessions(r.data.sessions.map((s) => s.session)); setProblem(null); } else setProblem(r.problem);
  }, []);
  const load = useCallback(async () => apply(await jcall("/api/v1/jupeb/office/old-portal-students/batches")), [apply]);
  useEffect(() => {
    let live = true;
    void jcall<{ batches: Batch[]; sessions: { session: string }[] }>("/api/v1/jupeb/office/old-portal-students/batches").then((r) => { if (live) apply(r); });
    return () => { live = false; };
  }, [apply]);

  return (
    <Panel title="Uploaded into the wrong session" right={<span className="sub2">Moves an upload&apos;s students to the session they belong to</span>}>
      <PBody>
        <p className="sub2">The students move with their registered subjects and their payments (references and amounts unchanged). Their class is left, to be placed in
          one of the new session&apos;s, and an ID card or slip stating the old session is printed again. A student who applied on this portal, is registered with the
          Board, or has results or attendance in the old session stays where they are.</p>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {batches === null ? <p className="sub2">Reading the uploads…</p> : batches.length === 0 ? <p className="sub2">No upload from the old portal yet.</p> : (
          <div className="tablewrap" tabIndex={0}>
            <table className="tbl--data">
              <thead><tr><th>Upload</th><th>File</th><th>Uploaded</th><th className="num">Students</th><th>Now in</th><th></th></tr></thead>
              <tbody>{batches.map((b) => (
                <tr key={b.ref}>
                  <td className="tnum">{b.ref}</td>
                  <td className="sub2">{b.file_name ?? "—"}</td>
                  <td className="sub2">{when(b.imported_at)}</td>
                  <td className="num tnum">{b.applied}</td>
                  <td>{b.sessions.length ? b.sessions.map((s) => <div key={s.session}><span className="tnum">{s.session}</span><span className="sub2"> · {s.students}</span></div>) : <span className="sub2">—</span>}</td>
                  <td><Btn kind="secondary" disabled={!b.sessions.length} onClick={() => setMoving(b)}>Move…<span className="sr-only"> {b.ref}</span></Btn></td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        )}
      </PBody>
      {moving ? <MoveDialog batch={moving} sessions={sessions} onClose={() => setMoving(null)} onDone={async () => { setMoving(null); await load(); }} /> : null}
    </Panel>
  );
}

function MoveDialog({ batch, sessions, onClose, onDone }: { batch: Batch; sessions: string[]; onClose: () => void; onDone: () => Promise<void> }) {
  const now = new Set(batch.sessions.map((s) => s.session));
  const [to, setTo] = useState(sessions.find((s) => !now.has(s)) ?? sessions[0] ?? "");
  const [reason, setReason] = useState("");
  const [judged, setJudged] = useState<MoveResult | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function check(target: string) {
    setBusy("check"); setProblem(null); setJudged(null);
    try {
      const r = await jcall<MoveResult>("/api/v1/jupeb/office/old-portal-students/move", "POST", { batch: batch.ref, to: target, commit: false });
      if (!r.ok) { setProblem(r.problem); return; }
      setJudged(r.data);
      setPicked(new Set(r.data.rows.filter((x) => x.status === "MOVE").map((x) => x.applicationId)));
    } finally { setBusy(null); }
  }
  async function move() {
    setBusy("move"); setProblem(null);
    try {
      const r = await jcall<MoveResult>("/api/v1/jupeb/office/old-portal-students/move", "POST", { ids: [...picked], to, reason, commit: true },
        `JUPEB old-portal students moved to ${to}: ${reason}`);
      if (!r.ok) { setProblem(r.problem); return; }
      notify(`${r.data.moved} student${r.data.moved === 1 ? "" : "s"} moved to ${to}`, "ok");
      await onDone();
    } finally { setBusy(null); }
  }
  const movable = judged ? judged.rows.filter((x) => x.status === "MOVE") : [];
  const all = movable.length > 0 && movable.every((x) => picked.has(x.applicationId));

  return (
    <Modal wide title={`Move the students of ${batch.ref}`} sub={`${batch.file_name ?? "Old-portal upload"} · now in ${batch.sessions.map((s) => `${s.session} (${s.students})`).join(", ")}`}
      onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" />
        <Btn kind="primary" busy={busy === "move"} busyLabel="Moving…" disabled={!judged || picked.size === 0 || reason.trim().length < 5 || busy !== null}
          onClick={() => void move()}>{`Move ${picked.size} student${picked.size === 1 ? "" : "s"} to ${to}`}</Btn></>}>
      <div className="stack">
        <div className="grid grid--2">
          <Field id="mv-to" label="Session they belong to" required hint="A session of the calendar up to JUPEB's current one">
            <select id="mv-to" className="ctl" value={to} onChange={(e) => { setTo(e.target.value); setJudged(null); }}>
              {sessions.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </Field>
          <Field id="mv-reason" label="Reason" required hint="5 characters at least; kept on each student's timeline">
            <input id="mv-reason" className="ctl" maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)}
              placeholder={`Uploaded into the wrong session; these students are ${to}`} />
          </Field>
        </div>
        <div className="row"><Btn kind="secondary" busy={busy === "check"} busyLabel="Checking…" disabled={!to || busy !== null} onClick={() => void check(to)}>Check the students</Btn>
          {judged ? <span className="sub2" style={{ marginLeft: 8 }}>{judged.movable} can move · {judged.left} stay where they are · nothing is written until you move them</span> : null}</div>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {judged ? (
          <div className="tablewrap" tabIndex={0} style={{ maxHeight: 420 }}>
            <table className="tbl--data">
              <thead><tr>
                <th className="mid"><input type="checkbox" aria-label="Move every student that can move" checked={all} disabled={!movable.length}
                  onChange={(e) => setPicked(e.target.checked ? new Set(movable.map((x) => x.applicationId)) : new Set())} /></th>
                <th>App No</th><th>Name</th><th>Now in</th><th>Status</th><th>What happens</th>
              </tr></thead>
              <tbody>{judged.rows.map((x) => {
                const [label, kind] = STATUS[x.status] ?? [x.status, "grey"];
                return (
                  <tr key={x.applicationId}>
                    <td className="mid"><input type="checkbox" aria-label={`Move ${x.name}`} disabled={x.status !== "MOVE"} checked={picked.has(x.applicationId)}
                      onChange={(e) => setPicked((p) => { const n = new Set(p); if (e.target.checked) n.add(x.applicationId); else n.delete(x.applicationId); return n; })} /></td>
                    <td className="tnum">{x.applicationNo}</td><td>{x.name}</td><td className="tnum">{x.session}</td>
                    <td><Pil kind={kind}>{label}</Pil></td><td className="sub2">{x.message ?? "—"}</td>
                  </tr>
                );
              })}</tbody>
            </table>
          </div>
        ) : <Note kind="info" title="Choose the session, then check the students: the portal says what will happen to each before anything moves." />}
      </div>
    </Modal>
  );
}
