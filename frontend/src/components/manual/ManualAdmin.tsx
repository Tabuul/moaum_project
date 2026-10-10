"use client";
/** V387: Manual Management — every procedure in every state; create, edit (a version kept), publish, unpublish, archive, restore,
 *  order within a category, bind to a page, preview as an office, release an edition. The form names menu items by their id and the
 *  screen checks each reference against the portal's own menus before it is saved. */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, PageHead, Pil, Tiles } from "@/components/proto/ui";
import { ROUTES } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Steps } from "@/components/manual/ManualReader";
import { CATEGORIES, CATEGORY_WORD, STATE_WORD, dayOf, menuChoices, unresolved, type ManualAdminView, type ManualCategory, type ManualState, type Procedure } from "@/lib/manual";
import { MENUS } from "@/lib/menus";

interface Draft { slug: string; title: string; purpose: string; category: ManualCategory; offices: string[]; capabilities: string[]; menuId: string; route: string; steps: string; expected: string; sortOrder: number; note: string }
const EMPTY: Draft = { slug: "", title: "", purpose: "", category: "DASHBOARD", offices: [], capabilities: [], menuId: "", route: "", steps: "", expected: "", sortOrder: 100, note: "" };
const toDraft = (p: Procedure): Draft => ({ slug: p.slug, title: p.title, purpose: p.purpose, category: p.category, offices: [...p.offices], capabilities: [...p.capabilities], menuId: p.menu_id ?? "", route: p.route ?? "", steps: p.steps.join("\n"), expected: p.expected, sortOrder: p.sort_order, note: "" });
const stateKind: Record<ManualState, "ok" | "warn" | "grey"> = { PUBLISHED: "ok", DRAFT: "warn", ARCHIVED: "grey" };

async function send(path: string, method: "POST" | "PUT", body: unknown, reason: string): Promise<{ ok: true; data: unknown } | { ok: false; problem: Problem }> {
  const r = await fetch(`/api/bff/api/v1/manual${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
  const j = await r.json().catch(() => null);
  return r.ok ? { ok: true, data: j } : { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
}

export function ManualAdmin({ data }: { data: ManualAdminView }) {
  const router = useRouter();
  const [q, setQ] = useState("");
  const [state, setState] = useState<ManualState | "">("");
  const [editing, setEditing] = useState<{ id: string | null; d: Draft } | null>(null);
  const [preview, setPreview] = useState<{ office: string; rows: Procedure[] } | null>(null);
  const [reading, setReading] = useState<Procedure | null>(null);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const rows = useMemo(() => {
    const w = q.trim().toLowerCase();
    return data.procedures.filter((p) => (!state || p.state === state) && (!w || [p.title, p.slug, p.purpose, p.offices.join(" ")].join(" ").toLowerCase().includes(w)));
  }, [data.procedures, q, state]);
  const sidebars = useMemo(() => Object.keys(MENUS).map((k) => ({ key: k, label: MENUS[k].label })), []);
  const d = editing?.d ?? null;
  const choices = useMemo(() => (d ? menuChoices(d.offices.filter((o) => o !== "everyone")) : []), [d]);
  const problems = useMemo(() => (d ? unresolved({ offices: d.offices, menu_id: d.menuId || null, route: d.route || null, steps: d.steps.split("\n") }, ROUTES) : []), [d]);

  function set<K extends keyof Draft>(k: K, v: Draft[K]) { setEditing((e) => (e ? { ...e, d: { ...e.d, [k]: v } } : e)); }
  function toggleIn(k: "offices" | "capabilities", v: string) { setEditing((e) => { if (!e) return e; const xs = e.d[k]; return { ...e, d: { ...e.d, [k]: xs.includes(v) ? xs.filter((x) => x !== v) : [...xs, v] } }; }); }
  function insertMenu(id: string) { if (!id) return; set("steps", `${d?.steps ?? ""}${d?.steps && !d.steps.endsWith("\n") ? "\n" : ""}Open {menu:${id}}.`); }

  async function save() {
    if (!editing) return;
    const body = { ...editing.d, steps: editing.d.steps.split("\n").map((s) => s.trim()).filter(Boolean), menuId: editing.d.menuId || null, route: editing.d.route || null, note: editing.d.note || null };
    setBusy(true); setProblem(null);
    try {
      const r = editing.id ? await send(`/admin/procedures/${editing.id}`, "PUT", body, editing.d.note || `Manual: ${editing.d.title} edited`) : await send("/admin/procedures", "POST", body, editing.d.note || `Manual: ${editing.d.title} drafted`);
      if (!r.ok) { setProblem(r.problem); return; }
      setEditing(null); setSaid(editing.id ? "Saved; the previous version is kept." : "Drafted; publish it when it is right."); router.refresh();
    } finally { setBusy(false); }
  }
  async function act(p: Procedure, action: "PUBLISH" | "UNPUBLISH" | "ARCHIVE" | "RESTORE") {
    const note = action === "ARCHIVE" ? window.prompt("Why is it archived?") ?? "" : "";
    if (action === "ARCHIVE" && !note) return;
    setBusy(true); setProblem(null);
    try {
      const r = await send(`/admin/procedures/${p.id}/${action}`, "POST", { note: note || null }, `Manual: ${p.title} ${action.toLowerCase()}ed`);
      if (!r.ok) { setProblem(r.problem); return; }
      setSaid(`${p.title}: ${action.toLowerCase()}ed.`); router.refresh();
    } finally { setBusy(false); }
  }
  async function move(p: Procedure, dir: -1 | 1) {
    const same = data.procedures.filter((x) => x.category === p.category).sort((a, b) => a.sort_order - b.sort_order || a.title.localeCompare(b.title));
    const i = same.findIndex((x) => x.id === p.id); const j = i + dir;
    if (i < 0 || j < 0 || j >= same.length) return;
    const ids = same.map((x) => x.id); [ids[i], ids[j]] = [ids[j], ids[i]];
    setBusy(true); setProblem(null);
    try { const r = await send("/admin/order", "PUT", { ids }, `Manual: ${CATEGORY_WORD[p.category]} reordered`); if (!r.ok) { setProblem(r.problem); return; } router.refresh(); } finally { setBusy(false); }
  }
  async function release() {
    const note = window.prompt("What does this edition add? (one line)") ?? "";
    if (!note) return;
    setBusy(true); setProblem(null);
    try { const r = await send("/admin/edition", "POST", { note }, `Manual: edition released — ${note}`); if (!r.ok) { setProblem(r.problem); return; } setSaid("Edition released."); router.refresh(); } finally { setBusy(false); }
  }
  async function previewAs(office: string) {
    if (!office) { setPreview(null); return; }
    setBusy(true); setProblem(null);
    try {
      const key = office; const isStudent = ["pgstudent", "jupebstudent"].includes(key); const isApplicant = ["pgapplicant", "jupebapplicant", "jupebcandidate", "cceapplicant"].includes(key);
      const r = await fetch(`/api/bff/api/v1/manual/admin/preview?office=${encodeURIComponent(isStudent ? "student" : isApplicant ? "applicant" : key)}${isStudent || isApplicant ? `&menu=${encodeURIComponent(key)}` : ""}`);
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setPreview({ office, rows: (j as { procedures: Procedure[] }).procedures });
    } finally { setBusy(false); }
  }

  return (
    <div className="manual">
      <PageHead description={<>Edition {data.edition.version} · last updated {dayOf(data.edition.updated_at)}{data.edition.updated_by ? ` by ${data.edition.updated_by}` : ""}{data.edition.note ? ` — ${data.edition.note}` : ""}.</>}
        actions={<><Btn kind="primary" size="sm" disabled={busy} onClick={() => setEditing({ id: null, d: { ...EMPTY } })}>New procedure</Btn><Btn kind="ghost" size="sm" disabled={busy} onClick={() => void release()}>Release a new edition</Btn></>} />
      <Tiles items={[["Published", data.counts.published, null, ""], ["Drafts", data.counts.draft, null, ""], ["Archived", data.counts.archived, null, ""], ["Readings, 30 days", data.counts.readings_30d, null, ""]]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said} action={<Btn kind="ghost" size="sm" onClick={() => setSaid(null)}>Close</Btn>} /> : null}

      {editing ? (
        <div className="card mt-2" style={{ padding: 16 }}>
          <h2 className="manual__h2">{editing.id ? "Edit the procedure" : "New procedure"}</h2>
          <div className="grid grid--2">
            <div><label className="lbl" htmlFor="m-title">Title</label><input id="m-title" className="ctl" value={d!.title} onChange={(e) => set("title", e.target.value)} /></div>
            <div><label className="lbl" htmlFor="m-slug">Key</label><input id="m-slug" className="ctl tnum" value={d!.slug} onChange={(e) => set("slug", e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, "-"))} placeholder="e.g. bursar-refunds" /></div>
            <div><label className="lbl" htmlFor="m-purpose">Purpose (one sentence)</label><input id="m-purpose" className="ctl" value={d!.purpose} onChange={(e) => set("purpose", e.target.value)} /></div>
            <div><label className="lbl" htmlFor="m-cat">Category</label><select id="m-cat" className="ctl" value={d!.category} onChange={(e) => set("category", e.target.value as ManualCategory)}>{CATEGORIES.map((c) => <option key={c} value={c}>{CATEGORY_WORD[c]}</option>)}</select></div>
          </div>
          <div className="mt-2"><div className="lbl">Offices that may perform it</div>
            <div className="row row--tight" style={{ flexWrap: "wrap" }}>
              {data.keys.map((k) => <label key={k} className="row row--inline row--tight" style={{ marginRight: 10 }}><input type="checkbox" checked={d!.offices.includes(k)} onChange={() => toggleIn("offices", k)} /> {MENUS[k]?.label ?? k}</label>)}
            </div></div>
          <div className="mt-2"><div className="lbl">Only with a support capability (any of)</div>
            <div className="row row--tight" style={{ flexWrap: "wrap" }}>
              {data.capabilities.map((c) => <label key={c} className="row row--inline row--tight" style={{ marginRight: 10 }}><input type="checkbox" checked={d!.capabilities.includes(c)} onChange={() => toggleIn("capabilities", c)} /> {c}</label>)}
            </div></div>
          <div className="grid grid--2 mt-2">
            <div><label className="lbl" htmlFor="m-menu">Menu item it lives on</label><select id="m-menu" className="ctl" value={d!.menuId} onChange={(e) => set("menuId", e.target.value)}><option value="">—</option>{choices.map((c) => <option key={c.id} value={c.id}>{c.label} ({c.group} · {MENUS[c.menu]?.label ?? c.menu})</option>)}</select></div>
            <div><label className="lbl" htmlFor="m-route">Contextual page (its How to list)</label><select id="m-route" className="ctl" value={d!.route} onChange={(e) => set("route", e.target.value)}><option value="">the menu item itself</option>{choices.map((c) => <option key={c.id} value={c.id}>{c.label} ({c.id})</option>)}</select></div>
          </div>
          <div className="mt-2"><label className="lbl" htmlFor="m-steps">Steps, one a line (name a control in `backticks`)</label>
            <textarea id="m-steps" className="ctl" rows={8} value={d!.steps} onChange={(e) => set("steps", e.target.value)} />
            <div className="row row--inline row--tight mt-1"><select className="ctl" style={{ maxWidth: 360 }} value="" onChange={(e) => insertMenu(e.target.value)} aria-label="Insert menu item"><option value="">Insert menu item…</option>{choices.map((c) => <option key={c.id} value={c.id}>{c.label} ({c.id})</option>)}</select><span className="sub2">A menu reference reads as the portal&rsquo;s current label and links to the page.</span></div>
            {problems.length ? <Note kind="bad" title="A reference the portal does not carry for these offices">{problems.map((x) => <div key={x.id}><code>{x.id}</code> — {x.where}</div>)}</Note> : null}
          </div>
          <div className="grid grid--2 mt-2">
            <div><label className="lbl" htmlFor="m-exp">Expected result</label><input id="m-exp" className="ctl" value={d!.expected} onChange={(e) => set("expected", e.target.value)} /></div>
            <div><label className="lbl" htmlFor="m-ord">Order within the category</label><input id="m-ord" className="ctl tnum" type="number" value={d!.sortOrder} onChange={(e) => set("sortOrder", Number(e.target.value) || 100)} /></div>
          </div>
          <div className="mt-2"><label className="lbl" htmlFor="m-note">Note for the record</label><input id="m-note" className="ctl" value={d!.note} onChange={(e) => set("note", e.target.value)} placeholder="why it changes" /></div>
          <div className="row row--inline mt-2"><Btn kind="primary" disabled={busy || !d!.title || !d!.slug || !d!.purpose || !d!.offices.length || !d!.steps.trim() || !d!.expected} onClick={() => void save()}>Save</Btn><Btn kind="ghost" disabled={busy} onClick={() => setEditing(null)}>Cancel</Btn></div>
        </div>
      ) : null}

      <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
        <input className="ctl" style={{ maxWidth: 320 }} value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search procedures" aria-label="Search procedures" />
        <select className="ctl" style={{ maxWidth: 180 }} value={state} onChange={(e) => setState(e.target.value as ManualState | "")} aria-label="State"><option value="">Every state</option>{(Object.keys(STATE_WORD) as ManualState[]).map((s) => <option key={s} value={s}>{STATE_WORD[s]}</option>)}</select>
        <select className="ctl" style={{ maxWidth: 300 }} value={preview?.office ?? ""} onChange={(e) => void previewAs(e.target.value)} aria-label="Preview as"><option value="">Preview as…</option>{sidebars.map((s) => <option key={s.key} value={s.key}>{s.label}</option>)}</select>
        <span className="sub2">{rows.length} of {data.procedures.length}</span>
      </div>

      {preview ? (
        <div className="card mt-2" style={{ padding: 16 }}>
          <div className="row row--inline" style={{ justifyContent: "space-between" }}><h2 className="manual__h2">As the {MENUS[preview.office]?.label ?? preview.office} reads it <Pil kind="grey">{preview.rows.length}</Pil></h2><Btn kind="ghost" size="sm" onClick={() => setPreview(null)}>Close</Btn></div>
          {preview.rows.map((p) => <div key={p.id} className="sub2" style={{ padding: "3px 0" }}><b>{p.title}</b> — {CATEGORY_WORD[p.category]}</div>)}
        </div>
      ) : null}

      <table className="tbl mt-2">
        <thead><tr><th>Title</th><th>Category</th><th>Offices</th><th>State</th><th className="num">Ver.</th><th className="num">Read</th><th>Updated</th><th></th></tr></thead>
        <tbody>
          {rows.map((p) => (
            <tr key={p.id}>
              <td><button type="button" className="manual__link" onClick={() => setReading(reading?.id === p.id ? null : p)}>{p.title}</button><div className="sub2">{p.slug}{p.capabilities.length ? ` · needs ${p.capabilities.join(" or ")}` : ""}</div></td>
              <td>{CATEGORY_WORD[p.category]}</td>
              <td className="sub2">{p.offices.map((o) => MENUS[o]?.label ?? o).join(", ")}</td>
              <td><Pil kind={stateKind[p.state]}>{STATE_WORD[p.state]}</Pil></td>
              <td className="num">{p.version}</td>
              <td className="num">{p.readings ?? 0}</td>
              <td className="sub2">{dayOf(p.updated_at)}{p.updated_by_name ? ` · ${p.updated_by_name}` : ""}</td>
              <td>
                <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
                  {p.state !== "ARCHIVED" ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => setEditing({ id: p.id, d: toDraft(p) })}>Edit</Btn> : null}
                  {p.state === "DRAFT" ? <Btn kind="primary" size="sm" disabled={busy} onClick={() => void act(p, "PUBLISH")}>Publish</Btn> : null}
                  {p.state === "PUBLISHED" ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void act(p, "UNPUBLISH")}>Unpublish</Btn> : null}
                  {p.state !== "ARCHIVED" ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void act(p, "ARCHIVE")}>Archive</Btn> : <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void act(p, "RESTORE")}>Restore</Btn>}
                  <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void move(p, -1)} title="Earlier in its category">↑</Btn>
                  <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void move(p, 1)} title="Later in its category">↓</Btn>
                </div>
                {reading?.id === p.id ? (
                  <div className="manual__body mt-1"><div className="sub2"><b>Purpose:</b> {p.purpose}</div><Steps p={p} menus={p.offices.filter((o) => o !== "everyone")} /><div className="manual__expected"><b>Expected result:</b> {p.expected}</div></div>
                ) : null}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
