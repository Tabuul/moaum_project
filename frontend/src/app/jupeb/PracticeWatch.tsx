"use client";

/**
 * Practice results for the JUPEB Office (V350): every student who practised in the session — tests, attempts, average, best,
 * the last attempt and each subject's average — weakest first, so a student who is struggling is seen early and advised.
 * "Show only below" is the Office's own filter for the list, not a rule on the record. The advice is a notice to that one
 * student: on their dashboard at once (with the unread mark), and by email or text when asked; it is kept with the
 * announcements, and the list says when each student was last advised.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { day, jcall } from "@/lib/jupeb";

export interface PracticeStudent {
  application_id: string; application_no: string; name: string; class_name: string | null; combination_code: string | null; tests: number; attempts: number;
  average: number; best: number; last_at: string; subjects: { code: string; title: string; attempts: number; average: number }[] | null; advised_at: string | null;
}
interface Results { session: string; classes: { id: string; name: string }[]; students: PracticeStudent[] }
export interface Advice { id: string; name: string; title: string; body: string; email: boolean; sms: boolean }

/** the advice as first written for a student; the Office edits it before sending */
export function adviceFor(s: { application_id: string; name: string; average: number | null; subjects?: PracticeStudent["subjects"] }): Advice {
  const first = s.name.split(", ")[1]?.split(" ")[0] ?? "";
  const weak = (s.subjects ?? [])[0];
  const avg = s.average == null ? null : Number(s.average);
  return {
    id: s.application_id, name: s.name, title: "Your JUPEB practice tests", email: true, sms: false,
    body: `Dear ${first},\n\n${avg == null ? "We have looked at your practice tests." : `Your average in the JUPEB practice tests is ${avg}%.`}`
      + `${weak ? ` Your weakest subject is ${weak.title} (${Number(weak.average)}%).` : ""}\n\n`
      + `Please study harder: read your notes${weak ? ` in ${weak.title}` : ""} every day, attempt the practice tests again, and ask your lecturers or the JUPEB Office for help where you are stuck.\n\nJUPEB Office`,
  };
}

/** the dialog in which the Office writes to one student; sends through the API, which keeps it with the announcements */
export function AdviceDialog({ advice, onClose, onSent }: { advice: Advice; onClose: () => void; onSent: () => void }) {
  const [a, setA] = useState(advice);
  const [busy, setBusy] = useState(false);
  async function send() {
    setBusy(true);
    try {
      const r = await jcall<{ notified: number }>(`/api/v1/jupeb/office/applications/${a.id}/advise`, "POST", { title: a.title.trim(), body: a.body.trim(), email: a.email, sms: a.sms },
        `Practice advice to ${a.name}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`Sent to ${a.name}${r.data.notified ? " — also by email or text" : ""}.`);
      onSent();
    } finally { setBusy(false); }
  }
  return (
    <Modal title={`Advise ${a.name}`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><Btn kind="primary" disabled={busy || a.title.trim().length < 3 || a.body.trim().length < 3} onClick={() => void send()}>{busy ? "Sending…" : "Send"}</Btn></>}>
      <p className="sub2">It shows on the student&rsquo;s dashboard at once, marked unread, and is kept with the announcements.</p>
      <Field id="ad-t" label="Title" required><input id="ad-t" className="ctl" maxLength={160} value={a.title} onChange={(e) => setA({ ...a, title: e.target.value })} /></Field>
      <Field id="ad-b" label="Message" required><textarea id="ad-b" className="ctl" rows={8} maxLength={5000} value={a.body} onChange={(e) => setA({ ...a, body: e.target.value })} /></Field>
      <div className="row" style={{ gap: "var(--s-4)" }}>
        <label className="row row--inline row--tight"><input type="checkbox" checked={a.email} onChange={(e) => setA({ ...a, email: e.target.checked })} /> Email it too</label>
        <label className="row row--inline row--tight"><input type="checkbox" checked={a.sms} onChange={(e) => setA({ ...a, sms: e.target.checked })} /> Text them</label>
      </div>
    </Modal>
  );
}

export function PracticeWatch({ session, canWrite }: { session: string; canWrite: boolean }) {
  const [klass, setKlass] = useState("");
  const [below, setBelow] = useState("50");
  const [only, setOnly] = useState(true);
  const [data, setData] = useState<Results | null>(null);
  const [tick, setTick] = useState(0);
  const [advise, setAdvise] = useState<Advice | null>(null);
  useEffect(() => {
    if (!session) return;
    let live = true;
    const qs = new URLSearchParams({ session, ...(klass ? { classId: klass } : {}) });
    void jcall<Results>(`/api/v1/jupeb/office/practice-results?${qs.toString()}`).then((r) => { if (!live) return; if (r.ok) setData(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [session, klass, tick]);
  const cut = Number(below);
  const all = data?.students ?? [];
  const rows = only && Number.isFinite(cut) ? all.filter((s) => Number(s.average) < cut) : all;
  return (
    <Panel title="Practice tests: students who may need help" right={<span className="row" style={{ flexWrap: "wrap" }}>
      <select className="ctl" style={{ width: 170 }} aria-label="Class" value={klass} onChange={(e) => setKlass(e.target.value)}>
        <option value="">Every class</option>{(data?.classes ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select>
      <label className="row row--inline row--tight"><input type="checkbox" checked={only} onChange={(e) => setOnly(e.target.checked)} /> only below</label>
      <input className="ctl" style={{ width: 70 }} type="number" min={1} max={100} aria-label="Average below (%)" value={below} onChange={(e) => setBelow(e.target.value)} /><span className="sub2">%</span>
    </span>}>
      <PBody>
        {!data ? <p className="sub2">Loading…</p> : !all.length ? <Note kind="info" title="No practice attempt yet this session">Students&rsquo; results appear here, weakest first, once they take the practice tests.</Note> : (
          <>
            <p className="sub2">{`${all.length} student${all.length === 1 ? "" : "s"} practised; ${all.filter((s) => Number(s.average) < cut).length} average below ${below}%. Weakest first.`}</p>
            {rows.length ? (
              <DTable pageSize={15} cols={["Student", "Class", "Tests|num", "Attempts|num", "Average|num", "Best|num", "Weakest subject", "Last attempt", "Advised", ...(canWrite ? [""] : [])]}
                texts={rows.map((s) => `${s.name} ${s.application_no}`)}
                rows={rows.map((s) => {
                  const weak = (s.subjects ?? [])[0];
                  const avg = Number(s.average);
                  return [<Link key="n" href={`/jupeb/applications/${s.application_id}`}><b>{s.name}</b><div className="sub2 tnum">{s.application_no}</div></Link>,
                    s.class_name ?? "—", s.tests, s.attempts,
                    <Pil key="a" kind={avg < 40 ? "bad" : avg < 50 ? "warn" : avg < 70 ? "info" : "ok"}>{`${avg}%`}</Pil>, `${Number(s.best)}%`,
                    weak ? `${weak.code} · ${Number(weak.average)}%` : "—", day(s.last_at), s.advised_at ? day(s.advised_at) : "—",
                    ...(canWrite ? [<Btn key="v" kind="secondary" onClick={() => setAdvise(adviceFor(s))}>Advise</Btn>] : [])];
                })} />
            ) : <p className="sub2">{`No student averages below ${below}%.`}</p>}
          </>
        )}
      </PBody>
      {advise ? <AdviceDialog advice={advise} onClose={() => setAdvise(null)} onSent={() => { setAdvise(null); setTick((t) => t + 1); }} /> : null}
    </Panel>
  );
}
