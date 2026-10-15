"use client";

/** The documents office (V262): requests by stage, documents issued by kind, verification and download activity, revenue and
 *  processing time; graduates awaiting a digital certificate, issued one by one or in a run; documents flagged after a record
 *  changed — reviewed one by one on the register, or reissued (or their flags cleared) in one act with one reason after a
 *  correction that flagged many; codes strangers keep checking that were never issued. Every figure is a door. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { Donut, HBars, VZ, vzNum } from "@/components/proto/vz";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { KIND, STAGE, callDocs, dayOf, naira, whenAt } from "@/lib/documents";
import type { OfficeData } from "./page";

const SIGNERS = ["registrar", "dregistrar", "academic"];
/** who clears a flag (DocumentsController OFFICE); a reissue is a signer's */
const REVIEWERS = ["academic", "registrar", "dregistrar", "records"];
interface Dash {
  requests: Record<string, number>; documents: Record<string, number>; verification: Record<string, number>;
  revenue: { collected: number; collected30: number; outstanding: number; byKind: { kind: string; label: string; amount: number; n: number }[]; byMonth: { month: string; amount: number; n: number }[] };
  processing: { avgDays: number | null; byKind: { kind: string; label: string; n: number; open: number }[]; byStage: { stage: string; n: number }[]; deliveries: { kind: string; state: string; n: number }[] };
}
const STAGE_COL: Record<string, string> = { AWAITING_PAYMENT: VZ.warn, HELD_AT_CLEARANCE: VZ.crit, READY: VZ.s1, PROCESSING: VZ.s1, GENERATED: VZ.s3, CORRECTION: VZ.s2, VERIFIED: VZ.s4, RELEASED: VZ.good, DELIVERED: VZ.good, COMPLETED: VZ.s5, REJECTED: VZ.crit, CANCELLED: VZ.axis };

export function Office({ data, office }: { data: OfficeData; office: string | null }) {
  const router = useRouter();
  const d = JSON.parse(data.dashboard) as Dash;
  const r = d.requests, docs = d.documents, v = d.verification;
  const may = !!office && SIGNERS.includes(office);
  const [picked, setPicked] = useState<string[]>([]);
  const [ask, setAsk] = useState(false);
  const [busy, setBusy] = useState(false);
  const mayClear = !!office && REVIEWERS.includes(office);
  const [flagPick, setFlagPick] = useState<string[]>([]);
  const [flagAct, setFlagAct] = useState<{ kind: "reissue" | "clear"; reason: string } | null>(null);
  const q = (path: string, extra = "") => `${path}${extra ? `?${extra}` : ""}`;

  async function issueOne(studentId: string, name: string) {
    setBusy(true);
    try {
      const x = await callDocs<{ number: string }>("POST", "/documents/certificates", { studentId }, `Issue digital certificate: ${name}`);
      if (!x.ok) { notifyProblem(x.problem); return; }
      notify(`Certificate ${x.data.number} issued`); router.refresh();
    } finally { setBusy(false); }
  }
  async function issueBulk() {
    setBusy(true);
    try {
      const x = await callDocs<{ issued: number }>("POST", "/documents/certificates/bulk", { studentIds: picked }, `Issue ${picked.length} digital certificates`);
      if (!x.ok) { notifyProblem(x.problem); return; }
      notify(`${x.data.issued} certificate(s) issued`); setAsk(false); setPicked([]); router.refresh();
    } finally { setBusy(false); }
  }
  /** the chosen flagged documents reissued (each a new version, the earlier copy then verifying as replaced) or their flags cleared */
  async function actOnFlagged() {
    if (!flagAct) return;
    setBusy(true);
    try {
      const n = flagPick.length;
      if (flagAct.kind === "reissue") {
        const x = await callDocs<{ reissued: number }>("POST", "/documents/issued/reissue-batch", { ids: flagPick, reason: flagAct.reason.trim() }, `Reissue ${n} flagged document(s): ${flagAct.reason.trim()}`);
        if (!x.ok) { notifyProblem(x.problem); return; }
        notify(`${x.data.reissued} document(s) reissued; the earlier copies now verify as replaced`);
      } else {
        const x = await callDocs<{ cleared: number }>("POST", "/documents/issued/clear-flags", { ids: flagPick, reason: flagAct.reason.trim() || null }, `Clear the flags of ${n} document(s)`);
        if (!x.ok) { notifyProblem(x.problem); return; }
        notify(`${x.data.cleared} flag(s) cleared; the documents stand`);
      }
      setFlagAct(null); setFlagPick([]); router.refresh();
    } finally { setBusy(false); }
  }
  const flagIds = data.flagged.map((f) => f.id);
  const allFlagged = flagIds.length > 0 && flagIds.every((id) => flagPick.includes(id));

  const HEAD = ["S/N", "Student ID", "Student Name", "Programme", "Award", "Session", "CGPA", "Class", "Cleared"];
  const body = () => data.awaitingCertificate.map((g, i) => [i + 1, g.student_number, g.student_name, g.programme ?? "", g.award, g.session, g.cgpa, g.class_of_degree, g.cleared ? "Yes" : "No"]);
  async function excel() { const blob = await brandedXlsx("Graduates Awaiting Certificate", HEAD, body(), { sheetName: "Awaiting", serial: docSerial("DOC") }); downloadBlob(blob, "graduates-awaiting-certificate.xlsx"); }

  return (
    <>
      <PageHead title="Documents office" 
        actions={<>
          <LinkBtn kind="secondary" href="/credentials/documents/requests">Requests</LinkBtn>
          <LinkBtn kind="secondary" href="/credentials/documents/register">Issued documents</LinkBtn>
          <LinkBtn kind="secondary" href="/credentials/documents/settings">Policies &amp; templates</LinkBtn>
          <LinkBtn kind="ghost" href="/verify/document">Public verification page</LinkBtn>
        </>} />
      <Tiles items={[
        ["New requests", vzNum(r.new), r.new ? "var(--amber-ink)" : null, "Paid, not yet started", q("/credentials/documents/requests", "stage=NEW")],
        ["Payment pending", vzNum(r.payment_pending), null, `${naira(d.revenue.outstanding)} outstanding`, q("/credentials/documents/requests", "stage=AWAITING_PAYMENT")],
        ["Held at clearance", vzNum(r.held), r.held ? "var(--red-ink)" : null, "A unit holds the student", q("/credentials/documents/requests", "stage=HELD_AT_CLEARANCE")],
        ["Processing", vzNum(r.processing), null, "Validation and generation", q("/credentials/documents/requests", "stage=PROCESSING")],
        ["Quality check", vzNum(r.quality_check), r.quality_check ? "var(--amber-ink)" : null, "Generated, to be checked", q("/credentials/documents/requests", "stage=QUALITY_CHECK")],
        ["Awaiting release", vzNum(r.approved), r.approved ? "var(--amber-ink)" : null, "Approved; the Registrar authorises", q("/credentials/documents/requests", "stage=VERIFIED")],
        ["Ready for delivery", vzNum(r.ready_for_delivery), "var(--green-ink)", "Released, deliveries open", q("/credentials/documents/requests", "stage=RELEASED")],
        ["Delivered", vzNum(r.delivered + r.completed), null, `${vzNum(r.completed)} completed`, q("/credentials/documents/requests", "stage=DELIVERED")],
        ["Breaching SLA", vzNum(r.breaching), r.breaching ? "var(--red-ink)" : null, "Past the due date", q("/credentials/documents/requests", "stage=BREACHING")],
        ["Certificates issued", vzNum(docs.certificates), "var(--green-ink)", `${vzNum(docs.certificates_pending)} graduate(s) awaiting one`, q("/credentials/documents/register", "kind=DEGREE_CERTIFICATE")],
        ["Transcripts issued", vzNum(docs.transcripts + docs.sessional + docs.mini + docs.statements), null, `${vzNum(docs.transcripts)} full · ${vzNum(docs.sessional)} sessional · ${vzNum(docs.mini)} mini · ${vzNum(docs.statements)} statements`, q("/credentials/documents/register")],
        ["Revoked · reissued · flagged", `${vzNum(docs.revoked)} · ${vzNum(docs.reissued)} · ${vzNum(docs.flagged)}`, docs.flagged ? "var(--amber-ink)" : null, "Revoked, reissued as a new version, flagged for review", q("/credentials/documents/register", "flagged=true")],
      ]} cls="grid--4" />

      <div className="grid grid--2">
        <Panel title="Requests by stage" right={`${vzNum(r.total)} requests`}>
          <PBody>{d.processing.byStage.length ? <Donut capLabel="requests" capValue={vzNum(r.total)} items={d.processing.byStage.map((s) => ({ l: STAGE[s.stage]?.[0] ?? s.stage, v: Number(s.n), c: STAGE_COL[s.stage] ?? VZ.s5 }))} onPick={(_, i) => router.push(q("/credentials/documents/requests", `stage=${d.processing.byStage[i].stage}`))} /> : <div className="sub2">No request yet.</div>}</PBody>
        </Panel>
        <Panel title="Verification and downloads, last 30 days" right={`${vzNum(v.suspected)} suspected forgeries`}>
          <PBody>
            <Tiles items={[["Verifications", vzNum(v.last30), null, `${vzNum(v.valid30)} valid`], ["Not found", vzNum(v.notFound30), v.notFound30 ? "var(--red-ink)" : null, "Codes nobody issued"], ["Downloads", vzNum(v.downloads30), null, "Students, offices, recipients"]]} cls="grid--3" />
            {data.suspected.length ? <div className="sub2 mt-1">Checked three or more times, never issued: {data.suspected.slice(0, 5).map((s) => `${s.code} (${s.attempts})`).join(", ")} — a records matter for the Registrar.</div> : null}
          </PBody>
        </Panel>
      </div>
      <div className="grid grid--2">
        <Panel title="Revenue by document kind" right={`${naira(d.revenue.collected)} collected · ${naira(d.revenue.collected30)} in 30 days`}>
          <PBody>{d.revenue.byKind.length ? <HBars items={d.revenue.byKind.map((k) => ({ l: `${k.label} · ${naira(k.amount)} (${k.n})`, v: Number(k.amount) }))} /> : <div className="sub2">No fee collected yet.</div>}</PBody>
        </Panel>
        <Panel title="Processing" right={d.processing.avgDays != null ? `${d.processing.avgDays} day(s) from payment to release on average` : "No release yet"}>
          <PBody>{d.processing.byKind.length ? <HBars items={d.processing.byKind.map((k) => ({ l: `${k.label} · ${k.open} open of ${k.n}`, v: Number(k.n) }))} onPick={(_, i) => router.push(q("/credentials/documents/requests", `kind=${d.processing.byKind[i].kind}`))} /> : <div className="sub2">No request yet.</div>}
            {d.processing.deliveries.length ? <div className="sub2 mt-1">Deliveries: {d.processing.deliveries.map((x) => `${x.kind.toLowerCase()} ${x.state.toLowerCase()} ${x.n}`).join(" · ")}</div> : null}</PBody>
        </Panel>
      </div>

      <Panel title="Graduates awaiting a digital certificate" right={<span className="row row--inline row--tight">{may && picked.length ? <Btn kind="primary" onClick={() => setAsk(true)}>Issue {picked.length} certificate(s)</Btn> : null}<Btn kind="ghost" onClick={() => void excel()} disabled={!data.awaitingCertificate.length}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Graduates Awaiting Certificate", "", HEAD, body(), docSerial("DOC"))} disabled={!data.awaitingCertificate.length}>PDF</Btn></span>}>
        {data.awaitingCertificate.length ? <DTable pageSize={25} cols={[...(may ? ["|mid"] : []), "S/N|num", "Graduate", "Programme", "Award", "Session|mid", "CGPA|num", "Class", "Cleared|mid", "|num"]} rows={data.awaitingCertificate.map((g, i) => [
          ...(may ? [<input key="pk" type="checkbox" aria-label={`Choose ${g.student_name}`} disabled={!g.cleared} checked={picked.includes(g.student_id)} onChange={(e) => setPicked(e.target.checked ? [...picked, g.student_id] : picked.filter((x) => x !== g.student_id))} />] : []),
          <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="n"><strong>{g.student_name}</strong><div className="sub2 tnum">{g.student_number}</div></span>, <span key="p" className="sub2">{g.programme ?? "—"}</span>, g.award, <span key="s" className="tnum">{g.session}</span>, <span key="c" className="tnum">{Number(g.cgpa).toFixed(2)}</span>, g.class_of_degree,
          <Pil key="cl" kind={g.cleared ? "ok" : "bad"}>{g.cleared ? "Cleared" : "Held"}</Pil>,
          <span key="a" className="row row--inline row--tight">{may && g.cleared ? <Btn kind="primary" onClick={() => void issueOne(g.student_id, g.student_name)} disabled={busy}>Issue</Btn> : null}<LinkBtn href={`/students/${g.student_id}`} size="sm">Record</LinkBtn></span>,
        ])} texts={data.awaitingCertificate.map((g) => `${g.student_name} ${g.student_number} ${g.programme ?? ""}`)} /> : <PBody><div className="sub2">Every graduated, Senate-approved student holds a valid digital certificate.</div></PBody>}
      </Panel>

      {data.flagged.length ? (
        <Panel title="Documents flagged after the record changed" right={<span className="row row--inline row--tight">
          {mayClear ? <Btn kind="ghost" size="sm" onClick={() => setFlagPick(allFlagged ? [] : flagIds)}>{allFlagged ? "Clear the choice" : `Choose all ${flagIds.length}`}</Btn> : null}
          {may && flagPick.length ? <Btn kind="primary" size="sm" disabled={busy} onClick={() => setFlagAct({ kind: "reissue", reason: "" })}>{`Reissue ${flagPick.length}…`}</Btn> : null}
          {mayClear && flagPick.length ? <Btn kind="secondary" size="sm" disabled={busy} onClick={() => setFlagAct({ kind: "clear", reason: "" })}>{`Clear ${flagPick.length} flag${flagPick.length === 1 ? "" : "s"}…`}</Btn> : null}
          <span className="sub2">{data.flagged.length}</span></span>}>
          <DTable cols={[...(mayClear ? ["|mid"] : []), "Document", "Holder", "Flagged|mid", "Why", "|num"]} rows={data.flagged.map((f) => [
            ...(mayClear ? [<input key="pk" type="checkbox" aria-label={`Choose ${f.kind_label} ${f.number ?? f.verification_code}${f.student_name ? ` of ${f.student_name}` : ""}`} checked={flagPick.includes(f.id)} onChange={(e) => setFlagPick(e.target.checked ? [...flagPick, f.id] : flagPick.filter((x) => x !== f.id))} />] : []),
            <span key="d"><strong>{f.kind_label}</strong> <span className="tnum sub2">{f.number}</span></span>, <span key="h">{f.student_name}<div className="sub2 tnum">{f.student_number}</div></span>, <span key="w" className="tnum sub2">{whenAt(f.flagged_at)}</span>, <span key="r" className="sub2">{f.flag_reason}</span>, <LinkBtn key="o" href={`/credentials/documents/register?q=${encodeURIComponent(f.number ?? f.verification_code)}`} size="sm" kind="primary">Review</LinkBtn>])}
            texts={data.flagged.map((f) => `${f.kind_label} ${f.number ?? ""} ${f.student_name ?? ""} ${f.student_number ?? ""} ${f.flag_reason ?? ""}`)} />
        </Panel>
      ) : <Note kind="ok" title="No issued document is flagged" />}

      <div className="sub2">Revenue by month: {d.revenue.byMonth.map((m) => `${m.month} ${naira(m.amount)} (${m.n})`).join(" · ") || "none yet"} · <Link className="lnk" href="/credentials/transcripts">the earlier transcript queue</Link> still opens.</div>

      {flagAct ? (
        <Modal title={flagAct.kind === "reissue" ? `Reissue ${flagPick.length} flagged document${flagPick.length === 1 ? "" : "s"}` : `Clear ${flagPick.length} flag${flagPick.length === 1 ? "" : "s"}`}
          sub={flagAct.kind === "reissue" ? "Each becomes a new version under the same number; the earlier copy then verifies as replaced, and each holder is told" : "Each document stands as issued; the review is kept on its history"}
          onClose={() => setFlagAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setFlagAct(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={busy || (flagAct.kind === "reissue" && flagAct.reason.trim().length < 5)} onClick={() => void actOnFlagged()}>{busy ? "Working…" : flagAct.kind === "reissue" ? "Reissue" : "Clear the flags"}</Btn></>}>
          <p className="sub2">{flagAct.kind === "reissue" ? "All of them are reissued or none: a document no longer current stops the run and is named." : "Clear a flag when the change does not touch the document — a sessional transcript of another session, say."}</p>
          <Field id="fl-why" label={flagAct.kind === "reissue" ? "What was corrected" : "Note"} required={flagAct.kind === "reissue"}
            hint={flagAct.kind === "reissue" ? "On every reissue and in each holder's message" : "Optional; kept on each document's history"}>
            <textarea id="fl-why" className="ctl" rows={2} maxLength={600} value={flagAct.reason} onChange={(e) => setFlagAct({ ...flagAct, reason: e.target.value })}
              placeholder={flagAct.kind === "reissue" ? "Units of ZZC 101 corrected on the Senate's approval (AMD-2026-00001)" : "Reviewed; the document stands"} /></Field>
        </Modal>
      ) : null}

      {ask ? (
        <Modal title={`Issue ${picked.length} digital certificate(s)`} onClose={() => setAsk(false)} foot={<><Btn kind="ghost" onClick={() => setAsk(false)}>Cancel</Btn><Btn kind="primary" onClick={() => void issueBulk()} disabled={busy}>{busy ? "Issuing…" : "Issue"}</Btn></>}>
          <p>Each certificate is numbered, given a verification code, and the graduate told. One that fails the checks stops the run. Issued {dayOf(new Date().toISOString())}.</p>
        </Modal>
      ) : null}
    </>
  );
}
