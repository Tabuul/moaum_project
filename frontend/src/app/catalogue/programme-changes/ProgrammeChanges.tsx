"use client";
/** Every correction of a programme's code (V716), newest first: the old and the new code, the programme, why, on which ticket, by whom
 *  and when; undone by the Director of ICT or the ICT Support Desk from the record (the students and every record back, the old code in
 *  use again). The record is never altered; the report is the filtered trail. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { ProgrammeChangeList, ProgrammeChangeRow } from "@/lib/programme-correction";

const at = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");

const why = (r: ProgrammeChangeRow) => [r.reason_words ?? r.reason_kind, r.remarks].filter(Boolean).join(" — ");

export function ProgrammeChanges({ list, q, page }: { list: ProgrammeChangeList; q: string; page: number }) {
  const go = useQueryNav();
  const router = useRouter();
  const [undoing, setUndoing] = useState<ProgrammeChangeRow | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const pages = Math.max(1, Math.ceil(list.total / list.size));
  const nav = (patch: { q?: string; page?: number }) => {
    const qs = new URLSearchParams();
    const nq = patch.q ?? q;
    const np = patch.page ?? 1;
    if (nq) qs.set("q", nq);
    if (np > 1) qs.set("page", String(np));
    go(`/catalogue/programme-changes${qs.toString() ? "?" + qs.toString() : ""}`);
  };

  async function undo() {
    if (!undoing || reason.trim().length < 10) return;
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue/programme-code-changes/${undoing.id}/undo`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Programme code correction undone: ${reason.trim()}`) },
        body: JSON.stringify({ reason: reason.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(`${undoing.new_code} is ${undoing.old_code} again: ${undoing.name}`);
      setUndoing(null); setReason("");
      router.refresh();
    } finally { setBusy(false); }
  }

  const HEAD = ["S/N", "Old code", "New code", "Programme", "Department", "Students", "Reason", "Ticket", "Changed by", "Office", "Changed", "State"];
  async function exportRows() {
    const r = await fetch(`/api/bff/api/v1/catalogue/programme-code-changes?${q ? `q=${encodeURIComponent(q)}&` : ""}size=2000`, { cache: "no-store" });
    const j = (await r.json().catch(() => null)) as ProgrammeChangeList | null;
    const rows = r.ok && j ? j.rows : list.rows;
    const body = rows.map((x, i) => [i + 1, x.old_code, x.new_code, x.name, x.dept_name ?? "", x.students, why(x), x.ticket ?? "", x.changed_by, x.changed_office, at(x.changed_at),
      x.undone_at ? `Undone ${at(x.undone_at)} by ${x.undone_by ?? ""}: ${x.undo_reason ?? ""}` : "In force"]);
    downloadBlob(await brandedXlsx("Programme code changes", HEAD, body, { sheetName: "Programme code changes", serial: docSerial("PCC"), sub: q ? `search “${q}”` : undefined }), "programme-code-changes.xlsx");
  }

  return (
    <>
      <PageHead title="Programme code changes" description="Every correction of a programme's code — the same programme before and after, every student and record following, the old code kept as an alias — with why, on which ticket, by whom and when. Kept as written."
        actions={<><LinkBtn href="/catalogue/structure/programmes">Programmes</LinkBtn><Btn kind="secondary" size="sm" disabled={!list.rows.length} onClick={() => void exportRows()}>Excel</Btn></>} />
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); nav({ q: String(new FormData(e.currentTarget).get("q") ?? "") }); }}>
        <div className="row">
          <Field id="pc-q" label="Search" style={{ flex: "2 1 260px" }}><input id="pc-q" name="q" className="ctl" type="search" defaultValue={q} placeholder="Old or new code, programme, department, ticket, remarks" /></Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
            <Btn kind="primary" type="submit">Search</Btn>
            {q ? <Btn kind="ghost" onClick={() => go("/catalogue/programme-changes")}>Clear</Btn> : null}
          </div>
        </div>
      </form>
      <Panel title="Corrections" right={<span className="sub2">{list.total.toLocaleString()} in all</span>}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Code", "Programme", "Students|num", "Reason", "By", "When|mid", "State|mid", ""]}
            texts={list.rows.map((r) => `${r.old_code} ${r.new_code} ${r.name} ${r.ticket ?? ""} ${r.remarks ?? ""}`)}
            rows={list.rows.map((r, i) => [
              <span key="n" className="tnum sub2">{(list.page - 1) * list.size + i + 1}</span>,
              <span key="c" className="tnum"><s className="sub2">{r.old_code}</s> → <b>{r.new_code}</b></span>,
              <span key="p">{r.name}<div className="sub2">{r.dept_name ?? ""}{r.category === "POST GRADUATE" ? " · Postgraduate" : ""}</div></span>,
              <span key="s" className="tnum">{r.students}</span>,
              <span key="r" className="sub2">{why(r)}{r.ticket ? <div className="tnum">ticket {r.ticket}</div> : null}</span>,
              <span key="b" className="sub2">{r.changed_by}<div>{r.changed_office}</div></span>,
              <span key="w" className="sub2 tnum">{at(r.changed_at)}</span>,
              r.undone_at ? <span key="st"><Pil kind="grey">Undone</Pil><div className="sub2">{at(r.undone_at)} · {r.undone_by ?? r.undone_office}<br />{r.undo_reason}</div></span> : <Pil key="st" kind="ok">In force</Pil>,
              !r.undone_at && list.may ? <Btn key="u" kind="ghost" size="sm" onClick={() => { setUndoing(r); setReason(""); }}>Undo</Btn> : <span key="u" />,
            ])} />
        ) : <PBody><div className="sub2">{q ? "No correction matches." : "No programme's code has been corrected yet."}</div></PBody>}
        {pages > 1 ? (
          <PBody>
            <div className="row row--inline" style={{ gap: "var(--s-2)" }}>
              <Btn kind="ghost" disabled={page <= 1} onClick={() => nav({ page: page - 1 })}>Previous</Btn>
              <span className="sub2">Page {page} of {pages}</span>
              <Btn kind="ghost" disabled={page >= pages} onClick={() => nav({ page: page + 1 })}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>
      {undoing ? (
        <Modal title={`Undo the correction of ${undoing.old_code} to ${undoing.new_code}`} sub={undoing.name} onClose={() => setUndoing(null)}
          foot={<><Btn kind="ghost" disabled={busy} onClick={() => setUndoing(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy || reason.trim().length < 10} onClick={() => void undo()}>{busy ? "Undoing…" : "Undo the correction"}</Btn></>}>
          <div className="sub2 mb-2">Every student and record goes back to {undoing.old_code}, which is in use again; {undoing.new_code} is archived (the record of the correction names it) and may be taken by a later correction. {undoing.students_now !== undoing.students ? `${undoing.students_now.toLocaleString()} student(s) are on ${undoing.new_code} now; those written since the correction stay on it.` : ""}</div>
          <Field id="pc-why" label="Reason" required hint="Ten characters or more">
            <textarea id="pc-why" className="ctl" rows={2} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
