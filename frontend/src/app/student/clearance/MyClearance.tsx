"use client";

/** My Clearance (V415): each office, its word and the date; an office that asks for something says what, and the document
 *  is uploaded here; the alumni details for final clearance; the certificate once every office has cleared. V668: for a final
 *  clearance, where it stands in the student's words — the offices still to clear, the Bursary last, and the school fees owed by
 *  session and semester with the way to pay them. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { EMPLOYMENT, finalWords, stateKind, stateWord, type AlumniDetails, type MyClearance, type MyFinal, type MyProcess, type Stage } from "@/lib/clearance";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "");
async function readFile(f: File): Promise<string> {
  return await new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = () => rej(r.error); r.readAsDataURL(f); });
}

export function MyClearanceScreen({ data }: { data: MyClearance }) {
  const live = data.processes.filter((p) => !p.cancelled_at);
  const past = data.processes.filter((p) => p.cancelled_at);
  if (!data.processes.length) {
    return <Note kind="info" title="No clearance has been started for you">The Registry starts fresh clearance after admission and screening, and final clearance in your final year.</Note>;
  }
  return (
    <>
      {data.final ? <FinalPosition f={data.final} /> : null}
      {live.map((p) => <ProcessCard key={p.id} p={p} />)}
      {data.alumni && live.some((p) => p.stages.some((s) => s.unit === "ALUMNI" && s.applies)) ? <AlumniForm a={data.alumni} /> : null}
      {past.length ? (
        <Panel title="Earlier clearances">
          <PBody>{past.map((p) => <div key={p.id} className="sub2">{p.workflow_label} · {p.session} · {p.reference} — cancelled{p.cancel_reason ? `: ${p.cancel_reason}` : ""}</div>)}</PBody>
        </Panel>
      ) : null}
    </>
  );
}

const naira = (n: unknown) => `₦${Number(n ?? 0).toLocaleString("en-NG", { maximumFractionDigits: 2 })}`;
const semesterWord = (n: number) => (n === 1 ? "First semester" : n === 2 ? "Second semester" : n === 3 ? "Third semester" : `Semester ${n}`);

/** V668: the final clearance in the student's words — what is next, and the school fees owed by session and semester */
function FinalPosition({ f }: { f: MyFinal }) {
  const w = finalWords(f);
  const owed = Number(f.outstanding) >= 1;
  return (
    <Panel title="Your graduation" right={f.award ? <span className="sub2">{f.award}{f.minute ? ` · ${f.basis === "COLLEGE_BOARD" ? "College Board" : "Senate"} minute ${f.minute}` : ""}</span> : undefined}>
      <PBody>
        <Note kind={w.kind} title={w.title} action={owed && f.onlinePayment ? <LinkBtn kind="urgent" href="/student/fees">Pay outstanding school fees</LinkBtn> : undefined}>{w.body}</Note>
        {!f.graduated ? (
          <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
            <span className="tnum"><span className="sub2">School fees assessed</span> <b>{naira(f.assessed)}</b></span>
            {Number(f.waived) >= 1 ? <span className="tnum"><span className="sub2">Waived or adjusted</span> <b>{naira(f.waived)}</b></span> : null}
            <span className="tnum"><span className="sub2">Paid</span> <b className="ink-green">{naira(f.paid)}</b></span>
            <span className="tnum"><span className="sub2">Outstanding</span> <b className={owed ? "ink-red" : ""}>{naira(f.outstanding)}</b></span>
            {f.beingAssessed ? <span className="sub2">{f.beingAssessed} semester{f.beingAssessed === 1 ? "" : "s"} being assessed by the Bursary</span> : null}
          </div>
        ) : null}
      </PBody>
      {owed ? (
        <DTable pageSize={0} cols={["Session", "Semester", "Outstanding|num"]} rows={f.owing.map((o) => [
          <span key="s" className="tnum">{o.session}</span>, <span key="m">{semesterWord(o.semester)}</span>, <span key="o" className="tnum ink-red">{naira(o.outstanding)}</span>])} />
      ) : null}
    </Panel>
  );
}

function ProcessCard({ p }: { p: MyProcess }) {
  const [open, setOpen] = useState<string | null>(p.stages.find((s) => ["REQUIRES_ACTION", "NOT_CLEARED", "REJECTED"].includes(s.state))?.unit ?? null);
  const done = !!p.completed_at;
  return (
    <Panel title={`${p.workflow_label} · ${p.session}`} right={<span className="row row--tight"><span className="sub2 tnum">{p.reference}</span><Pil kind={stateKind(p.overall)}>{stateWord(p.overall)}</Pil></span>}>
      <div className="card__body" style={{ padding: 0, gap: 0 }}>
        {p.stages.map((s) => (
          <div key={s.unit} style={{ borderBottom: "1px solid var(--line-2)" }}>
            <button type="button" className="row" onClick={() => setOpen(open === s.unit ? null : s.unit)} aria-expanded={open === s.unit}
              style={{ width: "100%", padding: "var(--s-3) var(--s-4)", background: "none", border: 0, cursor: "pointer", textAlign: "left", gap: "var(--s-3)" }}>
              <b className="grow">{s.label}</b>
              <span className="sub2">{when(s.decided_at)}</span>
              <Pil kind={stateKind(s.state)}>{s.state === "CLEARED" ? "✓ Cleared" : stateWord(s.state)}</Pil>
            </button>
            {open === s.unit ? <StageDetail p={p} s={s} /> : null}
          </div>
        ))}
      </div>
      {done && p.certificate ? (
        <PBody>
          <div className="row"><a className="btn btn--go btn--sm" href={`/student/clearance/certificate?process=${encodeURIComponent(p.id)}`}>Download the clearance certificate</a></div>
        </PBody>
      ) : null}
    </Panel>
  );
}

function StageDetail({ p, s }: { p: MyProcess; s: Stage }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const docs = p.documents.filter((d) => d.unit === s.unit && !d.superseded);
  const asks = s.documents.length ? s.documents : ["REQUIRES_ACTION", "NOT_CLEARED", "REJECTED"].includes(s.state) ? ["Supporting document"] : [];
  const canUpload = s.applies && s.state !== "CLEARED" && !p.completed_at;

  async function upload(f: File | undefined, label: string) {
    if (!f) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/me/clearance/${p.id}/documents`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${label} uploaded for ${s.label} clearance`) },
        body: JSON.stringify({ unit: s.unit, label, fileName: f.name, contentBase64: await readFile(f) }),
      });
      if (!r.ok) { const pr = await r.json().catch(() => ({ status: r.status, title: "The upload was refused." })); setProblem(pr); notifyProblem(pr); return; }
      notify(`${label} uploaded — the ${s.label} is told`);
      router.refresh();
    } finally { setBusy(false); }
  }

  const rows: [string, string][] = [];
  if (s.state === "NOT_APPLICABLE") rows.push(["", "Not required for you."]);
  if (s.state === "WAITING") rows.push(["", "Opens when the offices before it have cleared you."]);
  if (s.item) rows.push([s.state === "REQUIRES_ACTION" ? "What to do" : s.state === "REJECTED" ? "Reason" : s.state === "NOT_CLEARED" ? "Outstanding" : "Detail", s.item]);
  if (s.note) rows.push(["Remark", s.note]);
  if (s.instructions) rows.push(["Instructions", s.instructions]);
  if (s.deadline && s.state !== "CLEARED") rows.push(["Deadline", when(s.deadline)]);
  if (s.officer) rows.push(["By", `${s.officer}, ${when(s.decided_at)}`]);

  return (
    <div style={{ padding: "0 var(--s-4) var(--s-3)" }}>
      {rows.map(([k, v], i) => <div key={i} className="row row--tight"><span className="sub2" style={{ minWidth: 100 }}>{k}</span><span>{v}</span></div>)}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {docs.length ? (
        <div className="mt-1">
          {docs.map((d) => (
            <div key={d.id} className="row row--tight">
              <a href={`/api/bff/api/v1/me/clearance/documents/${d.id}/file`} target="_blank" rel="noreferrer">{d.label}</a>
              <Pil kind={d.state === "APPROVED" ? "ok" : d.state === "REJECTED" || d.state === "REQUIRES_REUPLOAD" ? "bad" : "info"}>{d.state.replace(/_/g, " ").toLowerCase()}</Pil>
              {d.reason ? <span className="sub2">{d.reason}</span> : null}
            </div>
          ))}
        </div>
      ) : null}
      {canUpload && asks.length ? (
        <div className="row row--tight mt-1" style={{ flexWrap: "wrap" }}>
          {asks.map((label) => (
            <label key={label} className="btn btn--primary btn--sm" style={{ cursor: busy ? "wait" : "pointer" }}>{busy ? "Uploading…" : `Upload ${label}`}
              <input type="file" accept="application/pdf,image/jpeg,image/png" hidden disabled={busy} onChange={(e) => void upload(e.target.files?.[0], label)} />
            </label>
          ))}
          <span className="sub2">PDF, JPEG or PNG, up to 5 MB</span>
        </div>
      ) : null}
    </div>
  );
}

function AlumniForm({ a }: { a: AlumniDetails }) {
  const router = useRouter();
  const [f, setF] = useState({
    phone: a.phone ?? "", email: a.email ?? "", address: a.address ?? "", stateOfResidence: a.state_of_residence ?? "", country: a.country ?? "",
    employmentStatus: a.employment_status ?? "", employer: a.employer ?? "", occupation: a.occupation ?? "", linkedin: a.linkedin ?? "",
    associationMember: a.association_member, membershipNo: a.membership_no ?? "",
  });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const put = async (path: string, body: unknown, reason: string) => {
    const r = await fetch(`/api/bff/api/v1/me${path}`, { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
    if (!r.ok) { const pr = await r.json().catch(() => ({ status: r.status, title: "Not saved." })); setProblem(pr); notifyProblem(pr); return false; }
    return true;
  };

  async function save(confirm: boolean) {
    setBusy(true); setProblem(null);
    try {
      if (!(await put("/contact", { phone: f.phone.trim() || null, email: f.email.trim() || null, address: f.address.trim() || null }, "Contact details for the alumni record"))) return;
      if (!(await put("/clearance/alumni", { stateOfResidence: f.stateOfResidence, country: f.country, employmentStatus: f.employmentStatus, employer: f.employer,
        occupation: f.occupation, linkedin: f.linkedin, associationMember: f.associationMember, membershipNo: f.membershipNo, confirm }, confirm ? "Alumni details confirmed" : "Alumni details saved"))) return;
      notify(confirm ? "Your alumni details are confirmed" : "Saved");
      router.refresh();
    } finally { setBusy(false); }
  }

  const input = (k: keyof typeof f, label: string, hint?: string) => (
    <Field id={`al-${k}`} label={label} hint={hint}>
      <input id={`al-${k}`} className="ctl" value={String(f[k])} onChange={(e) => setF({ ...f, [k]: e.target.value })} />
    </Field>
  );

  return (
    <Panel title="Alumni details" right={a.confirmed_at ? <Pil kind="ok">Confirmed {when(a.confirmed_at)}</Pil> : <Pil kind="warn">Not yet confirmed</Pil>}>
      <PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <div className="grid grid--2">
          {input("email", "E-mail")}
          {input("phone", "Phone")}
          {input("address", "Address")}
          {input("stateOfResidence", "State of residence")}
          {input("country", "Country")}
          <Field id="al-emp" label="Employment">
            <select id="al-emp" className="ctl" value={f.employmentStatus} onChange={(e) => setF({ ...f, employmentStatus: e.target.value })}>
              <option value="">Not stated</option>{EMPLOYMENT.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </Field>
          {input("employer", "Employer", "Optional")}
          {input("occupation", "Occupation", "Optional")}
          {input("linkedin", "LinkedIn or website", "Optional")}
          {input("membershipNo", "Alumni association number", "If you have one")}
        </div>
        <label className="row row--tight mt-1"><input type="checkbox" className="chk" checked={f.associationMember} onChange={(e) => setF({ ...f, associationMember: e.target.checked })} /> I am a member of the alumni association</label>
        <div className="row row--tight mt-2">
          <Btn kind="ghost" disabled={busy} onClick={() => void save(false)}>Save</Btn>
          <Btn kind="go" disabled={busy || !f.email.trim() || !f.phone.trim()} onClick={() => void save(true)}>Confirm my details</Btn>
        </div>
      </PBody>
    </Panel>
  );
}
