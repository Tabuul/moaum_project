"use client";

/** Document policies and templates (V262): per kind, whether it is billable and the fee, urgent, physical and international fees,
 *  self-service, the SLA, the scope a mini-transcript covers, the fields a stranger sees on verification; and the template
 *  versions — a new version never changes what an issued document was issued under. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { callDocs, dayOf, naira, type Policy, type Template } from "@/lib/documents";

const CONFIG = ["registrar", "dregistrar", "academic", "super"];
const FIELDS = ["holder", "matricNo", "programme", "award", "classOfDegree", "faculty", "department", "graduationSession", "graduationDate", "session", "level", "standing", "cgpa"];
type PolicyForm = { kind: string; label: string; billable: boolean; fee: string; urgentFee: string; physicalFee: string; internationalFee: string; selfService: boolean; slaDays: string; urgentSlaDays: string; includes: string; publicFields: string[]; graduatesOnly: boolean; active: boolean };
type TplForm = { kind: string; title: string; subtitle: string; signatoryName: string; signatoryTitle: string; secondName: string; secondTitle: string; footer: string; remarks: string };

export function Settings({ policies, templates, office }: { policies: Policy[]; templates: Template[]; office: string | null }) {
  const router = useRouter();
  const may = !!office && CONFIG.includes(office);
  const [pf, setPf] = useState<PolicyForm | null>(null);
  const [tf, setTf] = useState<TplForm | null>(null);
  const [busy, setBusy] = useState(false);
  const edit = (p: Policy): PolicyForm => ({ kind: p.kind, label: p.label, billable: p.billable, fee: p.fee === null ? "" : String(p.fee), urgentFee: String(p.urgent_fee), physicalFee: String(p.physical_fee), internationalFee: String(p.international_fee), selfService: p.self_service, slaDays: String(p.sla_days), urgentSlaDays: String(p.urgent_sla_days), includes: p.includes, publicFields: p.public_fields, graduatesOnly: p.graduates_only, active: p.active });
  async function savePolicy() {
    if (!pf) return;
    setBusy(true);
    try {
      const x = await callDocs("PUT", `/documents/policies/${pf.kind}`, { label: pf.label, billable: pf.billable, fee: pf.fee === "" ? null : Number(pf.fee), urgentFee: Number(pf.urgentFee) || 0, physicalFee: Number(pf.physicalFee) || 0, internationalFee: Number(pf.internationalFee) || 0, selfService: pf.selfService, slaDays: Number(pf.slaDays) || 5, urgentSlaDays: Number(pf.urgentSlaDays) || 2, includes: pf.includes, publicFields: pf.publicFields, graduatesOnly: pf.graduatesOnly, active: pf.active }, `Document policy ${pf.kind}`);
      if (!x.ok) { notifyProblem(x.problem); return; }
      notify("Policy saved"); setPf(null); router.refresh();
    } finally { setBusy(false); }
  }
  async function saveTemplate() {
    if (!tf) return;
    setBusy(true);
    try {
      const x = await callDocs<{ version: number }>("POST", "/documents/templates", { ...tf, subtitle: tf.subtitle || null, secondName: tf.secondName || null, secondTitle: tf.secondTitle || null, footer: tf.footer || null, remarks: tf.remarks || null }, `New template version for ${tf.kind}`);
      if (!x.ok) { notifyProblem(x.problem); return; }
      notify(`Template version ${x.data.version} is now in force`); setTf(null); router.refresh();
    } finally { setBusy(false); }
  }
  const latest = (k: string) => templates.filter((t) => t.kind === k).sort((a, b) => b.version - a.version)[0];

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href="/credentials/documents">Documents office</Link><span>›</span><strong>Policies &amp; templates</strong></div>
      <PageHead title="Document policies and templates" description="What each kind of document costs, how fast it is due, whether the student generates it alone, what a stranger sees when verifying it; and the template versions the documents are issued under." actions={<LinkBtn kind="ghost" href="/credentials/documents">Back to the office</LinkBtn>} />
      {!may ? <Note kind="info" title="You are reading these settings">The Registry and the Academic Office change them.</Note> : null}
      <Panel title="Policies by document kind">
        <DTable cols={["Document", "Fee", "Extras", "SLA|mid", "Self-service|mid", "Scope|mid", "Public fields", "Active|mid", "|num"]} rows={policies.map((p) => [
          <strong key="l">{p.label}<div className="sub2 tnum">{p.kind} · {p.number_prefix}/YYYY/NNNNNN</div></strong>,
          <span key="f" className="tnum">{p.billable ? (p.fee === null ? "Fee schedule" : naira(p.fee)) : "Free"}</span>,
          <span key="e" className="sub2 tnum">urgent {naira(p.urgent_fee)} · physical {naira(p.physical_fee)} · intl {naira(p.international_fee)}</span>,
          <span key="s" className="tnum">{p.sla_days} d{p.urgent_fee ? ` / ${p.urgent_sla_days} d` : ""}</span>,
          <Pil key="ss" kind={p.self_service ? "ok" : "grey"}>{p.self_service ? "Yes" : "No"}</Pil>,
          <span key="sc" className="sub2">{p.kind === "MINI_TRANSCRIPT" ? p.includes.toLowerCase().replace("_", " ") : p.graduates_only ? "graduates only" : "—"}</span>,
          <span key="pf" className="sub2">{p.public_fields.join(", ")}</span>,
          <Pil key="a" kind={p.active ? "ok" : "bad"}>{p.active ? "Active" : "Off"}</Pil>,
          may ? <Btn key="ed" kind="ghost" onClick={() => setPf(edit(p))}>Edit</Btn> : <span key="ed" />,
        ])} />
      </Panel>
      <Panel title="Templates" right={may ? <Btn kind="secondary" onClick={() => { const l = latest("TRANSCRIPT"); setTf({ kind: "TRANSCRIPT", title: l?.title ?? "", subtitle: l?.subtitle ?? "", signatoryName: l?.signatory_name ?? "", signatoryTitle: l?.signatory_title ?? "", secondName: l?.second_name ?? "", secondTitle: l?.second_title ?? "", footer: l?.footer ?? "", remarks: l?.remarks ?? "" }); }}>New template version</Btn> : `${templates.length} version(s)`}>
        <DTable cols={["Document|mid", "Version|mid", "Title", "Signatories", "Footer", "From|mid", "|mid"]} rows={templates.map((t) => [<span key="k" className="sub2">{t.kind.toLowerCase().replace("_", " ")}</span>, <span key="v" className="tnum">v{t.version}</span>, <strong key="t">{t.title}{t.subtitle ? <div className="sub2">{t.subtitle}</div> : null}</strong>, <span key="s" className="sub2">{t.signatory_name} ({t.signatory_title}){t.second_name ? `; ${t.second_name} (${t.second_title})` : ""}</span>, <span key="f" className="sub2">{t.footer ?? ""}</span>, <span key="d" className="tnum sub2">{dayOf(t.created_at)}</span>, <Pil key="a" kind={t.active ? "ok" : "grey"}>{t.active ? "In force" : "Kept"}</Pil>])} />
        <PBody><div className="sub2">A new version is what documents issued from now on carry; every document already issued stays under the version it was issued with, and its PDF renders under that version.</div></PBody>
      </Panel>

      {pf ? (
        <Modal title={`Policy · ${pf.label}`} wide onClose={() => setPf(null)} foot={<><Btn kind="ghost" onClick={() => setPf(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void savePolicy()} disabled={busy}>Save</Btn></>}>
          <div className="grid grid--3">
            <Field id="pf-label" label="Label"><input id="pf-label" className="ctl" value={pf.label} onChange={(e) => setPf({ ...pf, label: e.target.value })} /></Field>
            <Field id="pf-fee" label="Fee (₦)" hint={pf.kind === "TRANSCRIPT" ? "Blank: the fee schedule's transcript fee for the session" : "Blank means zero"}><input id="pf-fee" type="number" min={0} className="ctl" value={pf.fee} onChange={(e) => setPf({ ...pf, fee: e.target.value })} disabled={!pf.billable} /></Field>
            <Field id="pf-uf" label="Urgent processing fee (₦)"><input id="pf-uf" type="number" min={0} className="ctl" value={pf.urgentFee} onChange={(e) => setPf({ ...pf, urgentFee: e.target.value })} /></Field>
            <Field id="pf-pf" label="Physical delivery fee (₦)"><input id="pf-pf" type="number" min={0} className="ctl" value={pf.physicalFee} onChange={(e) => setPf({ ...pf, physicalFee: e.target.value })} /></Field>
            <Field id="pf-if" label="International delivery fee (₦)"><input id="pf-if" type="number" min={0} className="ctl" value={pf.internationalFee} onChange={(e) => setPf({ ...pf, internationalFee: e.target.value })} /></Field>
            <Field id="pf-sla" label="Standard processing (working days)"><input id="pf-sla" type="number" min={0} className="ctl" value={pf.slaDays} onChange={(e) => setPf({ ...pf, slaDays: e.target.value })} /></Field>
            <Field id="pf-usla" label="Urgent processing (days)"><input id="pf-usla" type="number" min={0} className="ctl" value={pf.urgentSlaDays} onChange={(e) => setPf({ ...pf, urgentSlaDays: e.target.value })} /></Field>
            {pf.kind === "MINI_TRANSCRIPT" ? <Field id="pf-inc" label="Mini-transcript covers"><select id="pf-inc" className="ctl" value={pf.includes} onChange={(e) => setPf({ ...pf, includes: e.target.value })}><option value="CURRENT_SEMESTER">The current semester</option><option value="SELECTED_SEMESTER">A selected semester</option><option value="SELECTED_SESSION">A selected session</option><option value="CUMULATIVE">The cumulative record</option></select></Field> : null}
          </div>
          <div className="row row--tight mt-1" style={{ gap: 18 }}>
            <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={pf.billable} onChange={(e) => setPf({ ...pf, billable: e.target.checked })} /> Billable</label>
            <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={pf.selfService} onChange={(e) => setPf({ ...pf, selfService: e.target.checked })} /> Self-service (a free kind the student generates at once)</label>
            <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={pf.graduatesOnly} onChange={(e) => setPf({ ...pf, graduatesOnly: e.target.checked })} /> Graduates only</label>
            <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={pf.active} onChange={(e) => setPf({ ...pf, active: e.target.checked })} /> Active</label>
          </div>
          <div className="eyebrow mt-2">Fields shown to a stranger on verification</div>
          <div className="row row--tight" style={{ gap: 12, flexWrap: "wrap" }}>{FIELDS.map((f) => <label key={f} className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={pf.publicFields.includes(f)} onChange={(e) => setPf({ ...pf, publicFields: e.target.checked ? [...pf.publicFields, f] : pf.publicFields.filter((x) => x !== f) })} /> {f}</label>)}</div>
          <div className="sub2 mt-1">Never shown: date of birth, address, phone, email, finances, internal identifiers. Results are never on the public page.</div>
        </Modal>
      ) : null}
      {tf ? (
        <Modal title="New template version" wide onClose={() => setTf(null)} foot={<><Btn kind="ghost" onClick={() => setTf(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveTemplate()} disabled={busy || !tf.title.trim() || !tf.signatoryName.trim() || !tf.signatoryTitle.trim()}>Put in force</Btn></>}>
          <div className="grid grid--2">
            <Field id="tf-kind" label="Document"><select id="tf-kind" className="ctl" value={tf.kind} onChange={(e) => { const l = latest(e.target.value); setTf({ kind: e.target.value, title: l?.title ?? "", subtitle: l?.subtitle ?? "", signatoryName: l?.signatory_name ?? "", signatoryTitle: l?.signatory_title ?? "", secondName: l?.second_name ?? "", secondTitle: l?.second_title ?? "", footer: l?.footer ?? "", remarks: l?.remarks ?? "" }); }}>{policies.map((p) => <option key={p.kind} value={p.kind}>{p.label}</option>)}</select></Field>
            <Field id="tf-title" label="Title" required><input id="tf-title" className="ctl" value={tf.title} onChange={(e) => setTf({ ...tf, title: e.target.value })} /></Field>
            <Field id="tf-sub" label="Subtitle" full><input id="tf-sub" className="ctl" value={tf.subtitle} onChange={(e) => setTf({ ...tf, subtitle: e.target.value })} /></Field>
            <Field id="tf-sn" label="Signatory" required><input id="tf-sn" className="ctl" value={tf.signatoryName} onChange={(e) => setTf({ ...tf, signatoryName: e.target.value })} /></Field>
            <Field id="tf-st" label="Signatory's title" required><input id="tf-st" className="ctl" value={tf.signatoryTitle} onChange={(e) => setTf({ ...tf, signatoryTitle: e.target.value })} /></Field>
            <Field id="tf-n2" label="Second signatory"><input id="tf-n2" className="ctl" value={tf.secondName} onChange={(e) => setTf({ ...tf, secondName: e.target.value })} /></Field>
            <Field id="tf-t2" label="Second signatory's title"><input id="tf-t2" className="ctl" value={tf.secondTitle} onChange={(e) => setTf({ ...tf, secondTitle: e.target.value })} /></Field>
            <Field id="tf-f" label="Footer" full><input id="tf-f" className="ctl" value={tf.footer} onChange={(e) => setTf({ ...tf, footer: e.target.value })} /></Field>
            <Field id="tf-r" label="Official remarks" full><textarea id="tf-r" className="ctl" rows={2} value={tf.remarks} onChange={(e) => setTf({ ...tf, remarks: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
