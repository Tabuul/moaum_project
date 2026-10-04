"use client";
/** The Bursar's GST fee (V314): the fee per session, for everyone or for a level, an entry mode, a faculty or a programme — a new
 *  statement supersedes the old and never touches a payment already made — and the rule it enforces: whether it gates GST/EPS
 *  registration, whether it gates the whole registration, and that one payment covers EPS. The GST and EPS offices read it here
 *  through their dashboards; they do not change it. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { dayOf, naira, num, type GstFeePage, type GstFeeRule } from "@/lib/gst";

const MODE: Record<string, string> = { UTME: "UTME", DIRECT_ENTRY: "Direct Entry", TRANSFER: "Transfer", JUPEB: "JUPEB", SANDWICH: "Sandwich" };
const scopeOf = (r: GstFeeRule) => [r.programme ? `Programme: ${r.programme}` : null, r.faculty ? `Faculty: ${r.faculty}` : null, r.level ? `${r.level} Level` : null, r.entry_mode ? MODE[r.entry_mode] ?? r.entry_mode : null].filter(Boolean).join(" · ") || "Every undergraduate";

export function GstFeePanel({ session, data, faculties, programmes, may }: {
  session: string; data: GstFeePage | null; faculties: { code: string; name: string }[]; programmes: { code: string; name: string; category?: string }[]; may: boolean;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [form, setForm] = useState({ amount: "", level: "", entryMode: "", facultyCode: "", programmeCode: "", effectiveFrom: "", note: "" });
  const [setting, setSetting] = useState({ gstEps: data?.setting.required_for_gst_eps ?? true, all: data?.setting.required_for_all ?? false, covers: data?.setting.covers_eps ?? true });
  const rules = data?.rules ?? [];
  const general = rules.find((r) => !r.level && !r.entry_mode && !r.faculty_code && !r.programme_code);

  async function send(method: string, path: string, body: unknown, reason: string, done: string, key: string) {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/gst${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return; }
      notify(done); router.refresh();
    } finally { setBusy(null); }
  }
  const state = () => {
    const amount = Number(form.amount);
    if (!form.amount || Number.isNaN(amount) || amount < 0) { notifyProblem({ status: 422, title: "State the GST fee in naira, zero or more." }); return; }
    void send("PUT", "/fee", { session, amount, level: form.level ? Number(form.level) : null, entryMode: form.entryMode || null, facultyCode: form.facultyCode || null, programmeCode: form.programmeCode || null, effectiveFrom: form.effectiveFrom || null, note: form.note || null },
      `GST fee stated for ${session}: ${amount}`, `GST fee for ${session} stated: ${naira(amount)}`, "fee").then(() => setForm({ amount: "", level: "", entryMode: "", facultyCode: "", programmeCode: "", effectiveFrom: "", note: "" }));
  };

  return (
    <Panel title="GST fee · General Studies & Entrepreneurship" right={general ? `${naira(general.amount)} for ${session}${rules.length > 1 ? ` · ${rules.length} rules` : ""}` : `Not yet stated for ${session}`}>
      <PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <div className="sub2">A separate obligation from school fees, paid once per session against a reference of its own on the same gateway and ledger. One payment covers both GST and EPS; there is no EPS fee. While it is unpaid the student&rsquo;s GST and EPS courses are locked on the registration form. A new statement supersedes the old for the same scope; payments already confirmed keep their amount.{data ? ` Paid so far for ${session}: ${num(data.paid.students)} students, ${naira(data.paid.amount)}.` : ""}</div>
        {!general && rules.length === 0 ? <Note kind="info" title={`No GST fee for ${session}`}>Until it is stated nothing is owed and nothing is locked; the GST and EPS dashboards show every student as &ldquo;no fee stated&rdquo;.</Note> : null}
        {may ? (
          <>
            <div className="grid grid--4 mt-2">
              <Field id="gf-amount" label="GST fee (₦)" required><input id="gf-amount" type="number" min={0} step="0.01" className="ctl tnum" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} placeholder="10000" /></Field>
              <Field id="gf-level" label="Level" hint="Blank = every level"><select id="gf-level" className="ctl" value={form.level} onChange={(e) => setForm({ ...form, level: e.target.value })}><option value="">All levels</option>{[100, 200, 300, 400, 500, 600].map((l) => <option key={l} value={l}>{l} Level</option>)}</select></Field>
              <Field id="gf-mode" label="Entry mode" hint="Blank = all entrants"><select id="gf-mode" className="ctl" value={form.entryMode} onChange={(e) => setForm({ ...form, entryMode: e.target.value })}><option value="">All entrants</option>{Object.entries(MODE).map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select></Field>
              <Field id="gf-from" label="Effective from" hint="Blank = today"><input id="gf-from" type="date" className="ctl" value={form.effectiveFrom} onChange={(e) => setForm({ ...form, effectiveFrom: e.target.value })} /></Field>
              <Field id="gf-fac" label="Faculty" hint="Blank = every faculty"><select id="gf-fac" className="ctl" value={form.facultyCode} onChange={(e) => setForm({ ...form, facultyCode: e.target.value })}><option value="">All faculties</option>{faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}</select></Field>
              <Field id="gf-prog" label="Programme" hint="Blank = every programme"><select id="gf-prog" className="ctl" value={form.programmeCode} onChange={(e) => setForm({ ...form, programmeCode: e.target.value })}><option value="">All programmes</option>{programmes.filter((p) => !p.category || p.category === "UNDER GRADUATE").map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}</select></Field>
              <Field id="gf-note" label="Note"><input id="gf-note" className="ctl" value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} placeholder="Council approval, memo reference…" /></Field>
              <div className="row row--inline row--tight" style={{ alignItems: "flex-end" }}><Btn kind="primary" disabled={busy !== null} onClick={state}>{busy === "fee" ? "Stating…" : `State the GST fee for ${session}`}</Btn></div>
            </div>
            <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
              <label className="row row--inline row--tight"><input type="checkbox" checked={setting.gstEps} onChange={(e) => setSetting({ ...setting, gstEps: e.target.checked })} /> GST payment required to register GST/EPS courses</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={setting.all} onChange={(e) => setSetting({ ...setting, all: e.target.checked })} /> GST payment required for the whole course registration</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={setting.covers} onChange={(e) => setSetting({ ...setting, covers: e.target.checked })} /> GST payment covers EPS</label>
              <Btn kind="secondary" size="sm" disabled={busy !== null} onClick={() => void send("PUT", `/setting?session=${encodeURIComponent(session)}`, { requiredForGstEps: setting.gstEps, requiredForAll: setting.all, coversEps: setting.covers }, "GST rule changed", "GST rule saved", "setting")}>{busy === "setting" ? "Saving…" : "Save the rule"}</Btn>
            </div>
          </>
        ) : <Note kind="info" title="Read only">The Bursar states the GST fee; the GST and EPS offices read it on their dashboards.</Note>}
      </PBody>
      {rules.length ? <DTable cols={["S/N|num", "Applies to", "Fee|num", "Effective|mid", "Stated by", "Note", may ? "Withdraw|mid" : "|mid"]} rows={rules.map((r, i) => [
        <span key="n" className="tnum sub2">{i + 1}</span>, <span key="s">{scopeOf(r)}</span>, <b key="a" className="tnum">{naira(r.amount)}</b>, <span key="e" className="tnum sub2">{dayOf(r.effective_from)}</span>,
        <span key="b" className="sub2">{r.stated_by ?? ""}{r.stated_office ? ` (${r.stated_office})` : ""} · {dayOf(r.stated_at)}</span>, <span key="o" className="sub2">{r.note ?? ""}</span>,
        may ? <Btn key="w" kind="ghost" size="sm" disabled={busy !== null} onClick={() => { if (window.confirm(`Withdraw this GST fee rule (${scopeOf(r)}, ${naira(r.amount)})? Students it priced fall back to the next rule, or to no fee.`)) void send("POST", `/fee/${r.id}/end?session=${encodeURIComponent(session)}`, {}, `GST fee rule withdrawn: ${scopeOf(r)}`, "GST fee rule withdrawn", r.id); }}>Withdraw</Btn> : <span key="w" />,
      ])} /> : null}
      {data?.history.length ? (
        <PBody>
          <details><summary className="sub2">Superseded rules for {session} ({data.history.length}) — payments made under them keep their amounts</summary>
            <DTable cols={["S/N|num", "Applied to", "Fee|num", "Stated|mid", "Superseded|mid"]} rows={data.history.map((r, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>, <span key="s">{scopeOf(r)}</span>, <span key="a" className="tnum">{naira(r.amount)}</span>, <span key="d" className="tnum sub2">{dayOf(r.stated_at)}</span>, <Pil key="x" kind="grey">{dayOf(r.superseded_at)}</Pil>,
            ])} />
          </details>
        </PBody>
      ) : null}
    </Panel>
  );
}
