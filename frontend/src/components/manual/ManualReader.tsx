"use client";
/** V387: the Quick Operational Manual as a person reads it — a search, the categories, and each procedure as purpose, numbered
 *  steps and the expected result. A step's menu item is the portal's own label and a link to the page; a control is named as
 *  the screen names it. Print and Download PDF go through the central document system; readings are recorded. */
import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { Btn, Note, PageHead, Pil } from "@/components/proto/ui";
import { ROUTES } from "@/components/proto/Shell";
import { printDocument } from "@/lib/document/html";
import { manualHtml } from "@/lib/manual-html";
import { CATEGORY_WORD, byCategory, dayOf, pieces, search, type ManualCategory, type ManualView, type Procedure } from "@/lib/manual";

function record(kind: "PROCEDURE" | "PRINT" | "PDF", procedureId?: string) {
  void fetch("/api/bff/api/v1/manual/views", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ kind, procedureId: procedureId ?? null }) }).catch(() => undefined);
}

export function Steps({ p, menus }: { p: Procedure; menus: string[] }) {
  return (
    <ol className="manual__steps">
      {p.steps.map((s, i) => (
        <li key={i}>
          {pieces(s, menus, ROUTES).map((x, k) =>
            x.kind === "text" ? <span key={k}>{x.text}</span>
              : x.kind === "control" ? <code key={k} className="manual__ctl">{x.text}</code>
              : x.href ? <Link key={k} href={x.href} className="manual__menu">{x.label}</Link>
              : <b key={k} className="manual__menu" title={x.missing ? "This menu item is not on the portal" : undefined}>{x.label}</b>)}
        </li>
      ))}
    </ol>
  );
}

export function ProcedureCard({ p, menus, open, onToggle }: { p: Procedure; menus: string[]; open: boolean; onToggle: () => void }) {
  return (
    <article id={`p-${p.slug}`} className="card manual__card" data-open={open ? "yes" : "no"}>
      <button type="button" className="manual__head" onClick={onToggle}>
        <span className="manual__title">{p.title}</span>
        <span className="sub2 manual__purpose">{p.purpose}</span>
        <span className="manual__chev" aria-hidden="true">{open ? "−" : "+"}</span>
      </button>
      {open ? (
        <div className="manual__body">
          <Steps p={p} menus={menus} />
          <div className="manual__expected"><b>Expected result:</b> {p.expected}</div>
        </div>
      ) : null}
    </article>
  );
}

export function ManualReader({ data, menus, label, initial, pdfHref }: { data: ManualView; menus: string[]; label: string; initial: string | null; pdfHref: string }) {
  const [q, setQ] = useState("");
  const [cat, setCat] = useState<ManualCategory | null>(null);
  const [open, setOpen] = useState<Set<string>>(() => new Set(initial ? [initial] : []));
  const [busy, setBusy] = useState(false);
  const scrolled = useRef(false);

  const rows = useMemo(() => {
    const hit = search(data.procedures, q, menus);
    return cat ? hit.filter((p) => p.category === cat) : hit;
  }, [data.procedures, q, cat, menus]);
  const groups = useMemo(() => byCategory(rows), [rows]);
  const present = useMemo(() => new Set(data.procedures.map((p) => p.category)), [data.procedures]);

  // the procedure a page sent the reader to is brought into view once
  useEffect(() => {
    if (!initial || scrolled.current) return;
    scrolled.current = true;
    document.getElementById(`p-${initial}`)?.scrollIntoView({ block: "start" });
  }, [initial]);

  function toggle(p: Procedure) {
    setOpen((s) => {
      const n = new Set(s);
      if (n.has(p.slug)) n.delete(p.slug);
      else { n.add(p.slug); record("PROCEDURE", p.id); }
      return n;
    });
  }
  function openAll(all: boolean) { setOpen(all ? new Set(rows.map((p) => p.slug)) : new Set()); }

  async function print() {
    setBusy(true);
    try {
      record("PRINT");
      await printDocument("STANDARD_REPORT", {
        title: "Quick Operational Manual", subtitle: `${label} · Edition ${data.edition.version}`,
        meta: [["Role", label], ["Edition", data.edition.version], ["Last updated", dayOf(data.edition.updated_at)], ["Procedures", String(rows.length)]],
        bodyHtml: manualHtml(rows, menus), footnote: "Menu and button names are the portal's own at the time of printing.",
      });
    } finally { setBusy(false); }
  }

  return (
    <div className="manual">
      <PageHead
        description={<>What to click, what to enter, what to confirm and what to expect — for the <b>{label}</b>. Edition {data.edition.version} · last updated {dayOf(data.edition.updated_at)}{data.edition.updated_office ? ` · ${data.edition.updated_office}` : ""}.</>}
        actions={<>
          <Btn kind="ghost" size="sm" disabled={busy || !rows.length} onClick={() => void print()}>Print</Btn>
          <a className="btn btn--ghost btn--sm" href={pdfHref} onClick={() => record("PDF")}>Download PDF</a>
        </>}
      />
      <div className="manual__search">
        <label className="lbl" htmlFor="manual-q">Search manual</label>
        <input id="manual-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Procedure, menu, action or keyword — e.g. matriculation, payment" autoComplete="off" />
      </div>
      <div className="manual__cats" role="group" aria-label="Categories">
        <button type="button" className={`pill ${cat === null ? "pill--info" : "pill--grey"}`} onClick={() => setCat(null)}>All</button>
        {(Object.keys(CATEGORY_WORD) as ManualCategory[]).filter((c) => present.has(c)).map((c) => (
          <button key={c} type="button" className={`pill ${cat === c ? "pill--info" : "pill--grey"}`} onClick={() => setCat(cat === c ? null : c)}>{CATEGORY_WORD[c]}</button>
        ))}
        <span className="sub2 manual__count">{rows.length} procedure{rows.length === 1 ? "" : "s"}</span>
        <Btn kind="ghost" size="sm" onClick={() => openAll(true)}>Open all</Btn>
        <Btn kind="ghost" size="sm" onClick={() => openAll(false)}>Close all</Btn>
      </div>
      {!data.procedures.length ? <Note kind="info" title="No procedure is published for your office yet">The Directorate of ICT publishes the manual office by office.</Note> : null}
      {data.procedures.length && !rows.length ? <Note kind="info" title="Nothing matches">Try another word, or clear the category.</Note> : null}
      {groups.map((g) => (
        <section key={g.category} className="manual__group">
          <h2 className="manual__h2">{g.word} <Pil kind="grey">{g.rows.length}</Pil></h2>
          {g.rows.map((p) => <ProcedureCard key={p.id} p={p} menus={menus} open={open.has(p.slug)} onToggle={() => toggle(p)} />)}
        </section>
      ))}
    </div>
  );
}
