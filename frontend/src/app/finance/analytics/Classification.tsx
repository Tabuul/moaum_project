"use client";

/**
 * The Bursary's classification catalogue (V409): the programme types a payer is read into (by entry mode, then programme
 * category), the purposes a payment is for (with the income account each posts to and what it entitles), and the rules
 * that say which source module generated a payment and which office owns it — the most particular rule winning. Stated
 * here, they classify every payment on the ledger at once; nothing is re-entered and no payment changes.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { moduleWord } from "@/lib/analytics";

interface ProgrammeType { code: string; label: string; ord: number; active: boolean; entry_modes: string[]; programme_categories: string[]; study_mode: string | null; description: string | null }
interface Purpose { code: string; label: string; ord: number; active: boolean; gl_account: string; entitlement: string | null }
interface Rule {
  id: string; purpose: string | null; purpose_label: string | null; programme_type: string | null; programme_type_label: string | null; source_module: string;
  responsible_office: string; responsible_office_label: string | null; note: string | null;
}
interface Catalogue {
  programmeTypes: ProgrammeType[]; purposes: Purpose[]; rules: Rule[]; offices: { code: string; label: string }[]; entryModes: string[]; programmeCategories: string[];
}
type Tab = "types" | "purposes" | "rules";

const words = (xs: string[]) => (xs.length ? xs.map((x) => x.replace(/_/g, " ").toLowerCase()).join(", ") : "—");

async function put<T>(path: string, body: unknown, reason: string): Promise<T | null> {
  const r = await fetch(`/api/bff/api/v1/analytics/finance${path}`, {
    method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return null; }
  return j as T;
}

export function Classification({ onChanged }: { onChanged: () => void }) {
  const [cat, setCat] = useState<Catalogue | null>(null);
  const [version, setVersion] = useState(0);
  const [tab, setTab] = useState<Tab>("types");
  const [busy, setBusy] = useState(false);
  const [type, setType] = useState({ code: "", label: "", entryModes: [] as string[], categories: [] as string[], studyMode: "", ord: "100", active: true, description: "" });
  const [purpose, setPurpose] = useState({ code: "", label: "", glAccount: "4090", entitlement: "", ord: "100", active: true });
  const [rule, setRule] = useState({ purpose: "", programmeType: "", sourceModule: "", responsibleOffice: "", note: "" });

  useEffect(() => {
    let live = true;
    void fetch("/api/bff/api/v1/analytics/finance/classification", { cache: "no-store" }).then((r) => (r.ok ? r.json() : null)).then((j) => { if (live && j) setCat(j as Catalogue); });
    return () => { live = false; };
  }, [version]);

  async function saved(ok: unknown, what: string) {
    if (!ok) return;
    notify(what);
    setVersion((v) => v + 1);
    onChanged();
  }
  async function saveType() {
    setBusy(true);
    try {
      await saved(await put(`/programme-types/${encodeURIComponent(type.code.trim().toUpperCase())}`, {
        label: type.label, entryModes: type.entryModes, programmeCategories: type.categories, studyMode: type.studyMode || null, ord: Number(type.ord) || 100, active: type.active, description: type.description || null,
      }, `Programme type ${type.code.toUpperCase()} stated`), `Programme type ${type.code.toUpperCase()} stated; every payment is read into it at once`);
    } finally { setBusy(false); }
  }
  async function savePurpose() {
    setBusy(true);
    try {
      await saved(await put(`/purposes/${encodeURIComponent(purpose.code.trim().toUpperCase())}`, {
        label: purpose.label, glAccount: purpose.glAccount, entitlement: purpose.entitlement || null, ord: Number(purpose.ord) || 100, active: purpose.active,
      }, `Payment purpose ${purpose.code.toUpperCase()} stated`), `Purpose ${purpose.code.toUpperCase()} stated`);
    } finally { setBusy(false); }
  }
  async function saveRule() {
    setBusy(true);
    try {
      await saved(await put("/classification", {
        purpose: rule.purpose || null, programmeType: rule.programmeType || null, sourceModule: rule.sourceModule.trim().toUpperCase(), responsibleOffice: rule.responsibleOffice, note: rule.note || null,
      }, `Classification of ${rule.purpose || "every purpose"} for ${rule.programmeType || "every programme type"} stated`), "Classification stated; the ledger is classified by it at once");
    } finally { setBusy(false); }
  }
  const toggle = (xs: string[], x: string) => (xs.includes(x) ? xs.filter((y) => y !== x) : [...xs, x]);

  if (!cat) return <Panel title="Payment classification"><PBody><div className="sub2">Loading the classification…</div></PBody></Panel>;
  const typeOpts = cat.programmeTypes.map((t) => ({ value: t.code, label: t.label }));
  const purposeOpts = cat.purposes.map((p) => ({ value: p.code, label: p.label }));
  const officeOpts = cat.offices.map((o) => ({ value: o.code, label: o.label }));

  return (
    <Panel title="Payment classification" right={<span className="sub2">Programme type, purpose, source module and responsible office: one gateway, one ledger, every payment classified</span>}>
      <PBody>
        <Tabs<Tab> label="Classification" value={tab} onChange={setTab} items={[
          { id: "types", label: "Programme types", count: cat.programmeTypes.length },
          { id: "purposes", label: "Purposes", count: cat.purposes.length },
          { id: "rules", label: "Module and office", count: cat.rules.length },
        ]} />
      </PBody>

      {tab === "types" ? (
        <>
          <DTable pageSize={0} cols={["S/N|num", "Code", "Programme type", "Entry modes", "Programme categories", "Study mode", "Active|mid", "|num"]} rows={cat.programmeTypes.map((t, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="c" className="tnum">{t.code}</span>, <span key="l" className="b600">{t.label}{t.description ? <div className="sub2">{t.description}</div> : null}</span>,
            <span key="e" className="sub2">{words(t.entry_modes)}</span>, <span key="p" className="sub2">{words(t.programme_categories)}</span>, <span key="m" className="sub2">{t.study_mode ? words([t.study_mode]) : "—"}</span>,
            <Pil key="a" kind={t.active ? "ok" : "grey"}>{t.active ? "Active" : "Off"}</Pil>,
            <Btn key="x" kind="ghost" size="sm" onClick={() => setType({ code: t.code, label: t.label, entryModes: t.entry_modes, categories: t.programme_categories, studyMode: t.study_mode ?? "", ord: String(t.ord), active: t.active, description: t.description ?? "" })}>Edit</Btn>,
          ])} />
          <PBody>
            <div className="sub2 mb-2">A payer is read into the first type whose entry modes hold theirs; failing that, the first whose programme categories hold their programme&rsquo;s. A type with nothing mapped classifies nobody until the University runs it.</div>
            <div className="grid grid--3">
              <Field id="pt-code" label="Code" hint="Capitals and underscores; e.g. SANDWICH"><input id="pt-code" className="ctl tnum" value={type.code} onChange={(e) => setType({ ...type, code: e.target.value.toUpperCase() })} /></Field>
              <Field id="pt-label" label="Label"><input id="pt-label" className="ctl" value={type.label} onChange={(e) => setType({ ...type, label: e.target.value })} /></Field>
              <Field id="pt-mode" label="Study mode">
                <select id="pt-mode" className="ctl" value={type.studyMode} onChange={(e) => setType({ ...type, studyMode: e.target.value })}><option value="">Not stated</option><option value="FULL_TIME">Full-time</option><option value="PART_TIME">Part-time</option><option value="SANDWICH">Sandwich</option></select>
              </Field>
            </div>
            <div className="grid grid--2 mt-2">
              <Field id="pt-entry" label="Entry modes of this type">
                <div className="row" style={{ flexWrap: "wrap", gap: 10 }}>{cat.entryModes.map((m) => <label key={m} className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={type.entryModes.includes(m)} onChange={() => setType({ ...type, entryModes: toggle(type.entryModes, m) })} /> {words([m])}</label>)}</div>
              </Field>
              <Field id="pt-cat" label="Programme categories of this type">
                <div className="row" style={{ flexWrap: "wrap", gap: 10 }}>{cat.programmeCategories.map((c) => <label key={c} className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={type.categories.includes(c)} onChange={() => setType({ ...type, categories: toggle(type.categories, c) })} /> {c.toLowerCase()}</label>)}</div>
              </Field>
            </div>
            <div className="row mt-2">
              <label className="sub2 row"><input type="checkbox" checked={type.active} onChange={(e) => setType({ ...type, active: e.target.checked })} /> Active</label>
              <Btn kind="primary" disabled={busy || !type.code.trim() || !type.label.trim()} onClick={() => void saveType()}>{busy ? "Saving…" : "State the programme type"}</Btn>
            </div>
          </PBody>
        </>
      ) : null}

      {tab === "purposes" ? (
        <>
          <DTable pageSize={0} cols={["S/N|num", "Code", "Purpose", "Income account", "What it entitles", "Active|mid", "|num"]} rows={cat.purposes.map((p, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="c" className="tnum">{p.code}</span>, <span key="l" className="b600">{p.label}</span>,
            <span key="g" className="tnum">{p.gl_account}</span>, <span key="e" className="sub2">{p.entitlement ?? "—"}</span>, <Pil key="a" kind={p.active ? "ok" : "grey"}>{p.active ? "Active" : "Off"}</Pil>,
            <Btn key="x" kind="ghost" size="sm" onClick={() => setPurpose({ code: p.code, label: p.label, glAccount: p.gl_account, entitlement: p.entitlement ?? "", ord: String(p.ord), active: p.active })}>Edit</Btn>,
          ])} texts={cat.purposes.map((p) => `${p.code} ${p.label}`)} />
          <PBody>
            <div className="grid grid--3">
              <Field id="pp-code" label="Code" hint="Capitals and underscores; e.g. CONVOCATION_FEE"><input id="pp-code" className="ctl tnum" value={purpose.code} onChange={(e) => setPurpose({ ...purpose, code: e.target.value.toUpperCase() })} /></Field>
              <Field id="pp-label" label="Label"><input id="pp-label" className="ctl" value={purpose.label} onChange={(e) => setPurpose({ ...purpose, label: e.target.value })} /></Field>
              <Field id="pp-gl" label="Income account" hint="An income account of the general ledger, 4010–4090"><input id="pp-gl" className="ctl tnum" inputMode="numeric" value={purpose.glAccount} onChange={(e) => setPurpose({ ...purpose, glAccount: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            </div>
            <Field id="pp-ent" label="What a confirmed payment entitles"><input id="pp-ent" className="ctl" value={purpose.entitlement} onChange={(e) => setPurpose({ ...purpose, entitlement: e.target.value })} /></Field>
            <div className="row mt-2">
              <label className="sub2 row"><input type="checkbox" checked={purpose.active} onChange={(e) => setPurpose({ ...purpose, active: e.target.checked })} /> Active</label>
              <Btn kind="primary" disabled={busy || !purpose.code.trim() || !purpose.label.trim()} onClick={() => void savePurpose()}>{busy ? "Saving…" : "State the purpose"}</Btn>
            </div>
          </PBody>
        </>
      ) : null}

      {tab === "rules" ? (
        <>
          <DTable pageSize={0} cols={["S/N|num", "Purpose", "Programme type", "Source module", "Responsible office", "Note", "|num"]} rows={cat.rules.map((r, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="p">{r.purpose_label ?? <span className="sub2">Any purpose</span>}</span>,
            <span key="t">{r.programme_type_label ?? <span className="sub2">Any programme type</span>}</span>, <span key="m" className="b600">{moduleWord(r.source_module)}</span>,
            <span key="o">{r.responsible_office_label ?? r.responsible_office}</span>, <span key="n" className="sub2">{r.note ?? "—"}</span>,
            <Btn key="x" kind="ghost" size="sm" onClick={() => setRule({ purpose: r.purpose ?? "", programmeType: r.programme_type ?? "", sourceModule: r.source_module, responsibleOffice: r.responsible_office, note: r.note ?? "" })}>Edit</Btn>,
          ])} texts={cat.rules.map((r) => `${r.purpose_label ?? ""} ${r.programme_type_label ?? ""} ${r.source_module} ${r.responsible_office_label ?? ""}`)} />
          <PBody>
            <div className="sub2 mb-2">The most particular rule wins: a purpose and a programme type together, then the purpose alone, then the programme type alone, then the rule for everything. The source module is what generated a payment; the responsible office is who owns it.</div>
            <div className="grid grid--2">
              <Field id="cr-purpose" label="Purpose"><SearchSelect id="cr-purpose" value={rule.purpose} allLabel="Any purpose" options={purposeOpts} onChange={(v) => setRule({ ...rule, purpose: v })} /></Field>
              <Field id="cr-type" label="Programme type"><SearchSelect id="cr-type" value={rule.programmeType} allLabel="Any programme type" options={typeOpts} onChange={(v) => setRule({ ...rule, programmeType: v })} /></Field>
              <Field id="cr-module" label="Source module" hint="Capitals and underscores; e.g. SANDWICH, STUDENT_FINANCE"><input id="cr-module" className="ctl tnum" value={rule.sourceModule} onChange={(e) => setRule({ ...rule, sourceModule: e.target.value.toUpperCase() })} /></Field>
              <Field id="cr-office" label="Responsible office"><SearchSelect id="cr-office" value={rule.responsibleOffice} placeholder="Choose the office" options={officeOpts} onChange={(v) => setRule({ ...rule, responsibleOffice: v })} /></Field>
            </div>
            <Field id="cr-note" label="Note"><input id="cr-note" className="ctl" value={rule.note} onChange={(e) => setRule({ ...rule, note: e.target.value })} /></Field>
            <div className="row mt-2"><Btn kind="primary" disabled={busy || !rule.sourceModule.trim() || !rule.responsibleOffice} onClick={() => void saveRule()}>{busy ? "Saving…" : "State the rule"}</Btn></div>
          </PBody>
        </>
      ) : null}
    </Panel>
  );
}
