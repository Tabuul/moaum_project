"use client";

/**
 * V548: the records check acted on. The students with no state of origin are told from here — at most once a week each, by
 * e-mail, SMS and the portal — and the Registry sees how many were told, have given it since, still have not, or gave the home
 * state and wait for the Registry to confirm it. A postgraduate record on an undergraduate programme is moved to a postgraduate
 * programme here, with the reason.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Tiles } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";

export interface TellProgress {
  issue: string; week: string; listed: number; told: number; toldThisWeek: number; givenSince: number; stillMissing: number; neverTold: number;
  waitingForRegistry: number; toTell: number; lastTold: string | null; notices: { channel: string; state: string; n: number }[];
}

const count = (n: number) => Number(n).toLocaleString("en-NG");
const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });
const CHANNEL: Record<string, string> = { EMAIL: "E-mail", SMS: "SMS", PORTAL: "Portal" };
const STATE: Record<string, string> = { QUEUED: "waiting to go", SENT: "sent", FAILED: "failed", CANCELLED: "cancelled", DELIVERED: "delivered", BOUNCED: "bounced", UNDELIVERED: "not delivered" };
export const TELLERS = ["records", "registrar", "dregistrar", "ict", "super"];
export const MOVERS = ["records", "registrar", "dregistrar", "pgschool", "pgsecretary", "super"];

async function send(path: string, body: unknown, reason: string): Promise<{ ok: true; data: Record<string, unknown> } | { ok: false; problem: Problem }> {
  const r = await fetch(`/api/bff/api/v1/records/issues${path}`, {
    method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText } };
  return { ok: true, data: j as Record<string, unknown> };
}

/** the students with no state of origin: told from here, and where they stand */
export function TellStudents({ p, faculty, facultyName, may }: { p: TellProgress; faculty: string | null; facultyName: string; may: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const left = p.toTell;

  async function tell() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await send("/notices", { issue: "NO_STATE_OF_ORIGIN", faculty }, `Students with no state of origin told to give it (${facultyName})`);
      if (!r.ok) { setProblem(r.problem); return; }
      const told = Number(r.data.told ?? 0), before = Number(r.data.toldThisWeekAlready ?? 0), unreached = Number(r.data.unreached ?? 0);
      notify(`${count(told)} student${told === 1 ? "" : "s"} told${before ? `; ${count(before)} already told this week` : ""}${unreached ? `; ${count(unreached)} could not be reached` : ""}`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="stack" style={{ gap: 8 }}>
      <Tiles items={[
        ["Told", count(p.told), null, p.lastTold ? `last ${when(p.lastTold)}` : "not yet"],
        ["Given since", count(p.givenSince), p.givenSince ? "var(--green-ink)" : null, "told, and the record now has a state"],
        ["Still missing", count(p.stillMissing), p.stillMissing ? "var(--red-ink)" : null, `${count(p.neverTold)} never told`],
        ["Wait for the Registry", count(p.waitingForRegistry), p.waitingForRegistry ? "var(--amber-ink, #8a5a00)" : null, "gave the home state: confirm it"],
      ]} />
      {p.notices.length ? (
        <div className="sub2">Notices: {p.notices.map((x) => `${CHANNEL[x.channel] ?? x.channel} ${count(x.n)} ${STATE[x.state] ?? x.state.toLowerCase()}`).join(" · ")}</div>
      ) : null}
      {may ? (
        <div className="row row--end">
          <div className="sub2 grow">
            {left ? `${count(left)} student${left === 1 ? "" : "s"}${faculty ? ` of ${facultyName}` : ""} not told this week (${p.week}) would be told by e-mail, SMS and the portal to choose the state on the Biodata form.`
              : `Every student listed has been told this week (${p.week}) or waits for the Registry.`}
          </div>
          <Btn kind="primary" busy={busy} disabled={!left} onClick={() => void tell()}>Tell the students</Btn>
        </div>
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
    </div>
  );
}

interface MoveOptions {
  student: { id: string; name: string; number: string | null; programmeCode: string | null; programme: string | null; department: string | null; level: number | null; entryMode: string | null; status: string };
  movable: boolean; registrations: number;
  moves: { from: string; to: string; level: number; reason: string; at: string }[];
  options: { code: string; name: string; department: string; sameDepartment: boolean }[];
}

/** a postgraduate record on an undergraduate programme, moved to a postgraduate programme with the reason */
export function MoveRecord({ studentId, onClose }: { studentId: string; onClose: () => void }) {
  const router = useRouter();
  const [o, setO] = useState<MoveOptions | null>(null);
  const [form, setForm] = useState({ programme: "", level: "700", reason: "" });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch(`/api/bff/api/v1/records/issues/move/${studentId}`);
      const j = await r.json().catch(() => null);
      if (!alive) return;
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      const m = j as MoveOptions;
      setO(m);
      const lvl = m.student.level && [700, 800, 900].includes(m.student.level) ? String(m.student.level) : "700";
      setForm((f) => ({ ...f, programme: m.options.find((x) => x.sameDepartment)?.code ?? "", level: lvl }));
    })();
    return () => { alive = false; };
  }, [studentId]);

  const same = o?.options.filter((x) => x.sameDepartment) ?? [];
  const other = o?.options.filter((x) => !x.sameDepartment) ?? [];
  const chosen = o?.options.find((x) => x.code === form.programme);

  async function move() {
    if (!o) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await send(`/move/${studentId}`, { programme: form.programme, level: Number(form.level), reason: form.reason.trim() },
        `Record of ${o.student.number ?? o.student.name} moved to ${form.programme}: ${form.reason.trim()}`);
      if (!r.ok) { setProblem(r.problem); return; }
      notify(`${o.student.name} moved to ${chosen?.name ?? form.programme}, ${form.level} Level`);
      onClose();
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title="Move to a postgraduate programme" sub={o ? `${o.student.name} · ${o.student.number ?? "no number yet"}` : "Reading the record…"} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <span className="grow" />
        <Btn kind="primary" busy={busy} disabled={!o?.movable || !form.programme || form.reason.trim().length < 10} onClick={() => void move()}>Move the record</Btn>
      </>}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {o ? (
        <>
          <div className="sub2">
            Now on <b>{o.student.programme ?? o.student.programmeCode}</b> ({o.student.programmeCode}) at {o.student.level ?? "no"} Level, entry mode {o.student.entryMode ?? "none"}.
            {o.registrations ? ` ${count(o.registrations)} course registration${o.registrations === 1 ? " stays" : "s stay"} as they were made.` : ""}
          </div>
          {!o.movable ? (
            <Note kind="info" title="This record is not moved here">Only a live postgraduate record (the postgraduate entry mode, or a level of 700 and above) on an undergraduate programme is moved here; any other change of programme is a transfer.</Note>
          ) : (
            <>
              <Field id="mv-prog" label="Postgraduate programme">
                <select id="mv-prog" className="ctl" style={{ minWidth: 320 }} value={form.programme} onChange={(e) => setForm({ ...form, programme: e.target.value })}>
                  <option value="">Choose the programme</option>
                  {same.length ? <optgroup label="The student's department">{same.map((x) => <option key={x.code} value={x.code}>{x.name} ({x.code})</option>)}</optgroup> : null}
                  <optgroup label="Other departments">{other.map((x) => <option key={x.code} value={x.code}>{x.name} ({x.code})</option>)}</optgroup>
                </select>
              </Field>
              {chosen && !chosen.sameDepartment ? <Note kind="info" title="Another department">The programme chosen is not of the student&rsquo;s department ({o.student.department}).</Note> : null}
              <Field id="mv-lvl" label="Level">
                <select id="mv-lvl" className="ctl" value={form.level} onChange={(e) => setForm({ ...form, level: e.target.value })}>
                  <option value="700">700 — postgraduate diploma, or a master&rsquo;s first year</option>
                  <option value="800">800 — master&rsquo;s</option>
                  <option value="900">900 — doctorate</option>
                </select>
              </Field>
              <Field id="mv-why" label="Why the record is moved">
                <textarea id="mv-why" className="ctl" rows={3} maxLength={500} placeholder="The School of Postgraduate Studies' admission list of 2025/2026" value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
              </Field>
              <div className="sub2">The entry mode becomes Postgraduate. The move is kept with the reason on the record&rsquo;s history.</div>
            </>
          )}
          {o.moves.length ? <div className="sub2">Moved before: {o.moves.map((m) => `${m.from} → ${m.to} (${when(m.at)})`).join("; ")}</div> : null}
        </>
      ) : null}
    </Modal>
  );
}
