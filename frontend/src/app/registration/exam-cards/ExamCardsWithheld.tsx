"use client";

/**
 * Examination cards withheld (V505): every approved registration whose examination card the card's own rule refuses — not
 * cleared by the Bursary, cards not yet released, no course on the registration, not in study — by faculty and department, the
 * figures by reason, the list to Excel or PDF, and a reminder to those students (once a day at most). The server decides it all.
 */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { semesterWord } from "@/lib/registration-approval";
import { WITHHELD_REASONS, countedAt, reasonLabel, type Withheld, type WithheldRow } from "@/lib/exam-cards-withheld";

const vz = (n: number | null | undefined) => Number(n ?? 0).toLocaleString("en-GB");

export function ExamCardsWithheld({ w, code, faculty, q, mayRemind }: { w: Withheld; code: string; faculty: string; q: string; mayRemind: boolean }) {
  const router = useRouter();
  const go = useQueryNav();
  const nav = (patch: Record<string, string | number | null>) => {
    const next: Record<string, string> = { session: w.session, semester: w.semester ? String(w.semester) : "", code, faculty, q, page: "0" };
    for (const [k, v] of Object.entries(patch)) next[k] = v == null ? "" : String(v);
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "page" && v === "0")) qs.set(k, v);
    go(`/registration/exam-cards?${qs.toString()}`);
  };
  const [search, setSearch] = useState(q);
  const [remind, setRemind] = useState<string | null>(null);
  const pages = Math.max(1, Math.ceil(w.total / w.size));
  const sub = `${w.session}${w.semester ? ` · ${semesterWord(w.semester)}` : ""}`;
  const totalAll = Object.values(w.counts).reduce((a, b) => a + b, 0);

  const HEAD = ["S/N", "Student", "Matriculation No.", "Faculty", "Department", "Programme", "Level", "Semester", "Reason"];
  async function allRows(): Promise<(string | number)[][] | null> {
    const qs = new URLSearchParams({ session: w.session, page: "0", size: "5000" });
    if (w.semester) qs.set("semester", String(w.semester));
    if (code) qs.set("code", code);
    if (faculty) qs.set("faculty", faculty);
    if (q) qs.set("q", q);
    const r = await fetch(`/api/bff/api/v1/registration/exam-cards/withheld?${qs.toString()}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
    return (j.rows as WithheldRow[]).map((x, i) => [i + 1, x.full_name, x.matric_no ?? "", x.faculty_code ?? "", x.dept_code ?? "", x.programme ?? "", x.level ?? "", x.semester, reasonLabel(x.code)]);
  }

  async function sendReminder() {
    const r = await fetch("/api/bff/api/v1/registration/exam-cards/withheld/remind", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Students whose examination cards are withheld reminded (${remind === "ALL" ? "all reasons" : reasonLabel(remind ?? "")})`) },
      body: JSON.stringify({ session: w.session, semester: w.semester, code: remind === "ALL" ? null : remind }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setRemind(null);
    notify(`${vz(j.told)} student${j.told === 1 ? "" : "s"} told why their examination card is not yet available.`);
  }

  return (
    <>
      <PageHead title="Examination cards withheld" eyebrow="Examinations"
        description="Every student whose course registration is approved but whose examination card cannot be issued yet, and why. Clear what can be cleared before the examination week, not at the hall door." />

      <div className="row" style={{ flexWrap: "wrap", gap: 12, alignItems: "flex-end" }}>
        <Field id="ew-session" label="Academic session"><select id="ew-session" className="ctl" value={w.session} onChange={(e) => nav({ session: e.target.value })}>
          {w.sessions.map((s) => <option key={s} value={s}>{s}{s === w.current ? " (current)" : ""}</option>)}
        </select></Field>
        <Field id="ew-semester" label="Semester"><select id="ew-semester" className="ctl" value={w.semester ? String(w.semester) : ""} onChange={(e) => nav({ semester: e.target.value || null })}>
          <option value="">All semesters</option><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option>
        </select></Field>
        <form className="row row--inline" style={{ gap: 8 }} onSubmit={(e) => { e.preventDefault(); nav({ q: search.trim() }); }}>
          <input className="ctl" aria-label="Search by name or matriculation number" placeholder="Name or matriculation number" value={search} onChange={(e) => setSearch(e.target.value)} />
          <Btn kind="ghost" type="submit">Search</Btn>
        </form>
        <span className="grow" />
        <span className="sub2">{countedAt(w.computedAt)}{w.refreshing ? " · a newer count is being worked out" : ""}</span>
        <Btn kind="ghost" size="sm" onClick={() => { nav({ refresh: 1 }); router.refresh(); }}>Refresh</Btn>
      </div>

      <div className="grid grid--4" role="group" aria-label="Examination cards withheld, by reason">
        {WITHHELD_REASONS.map((r) => (
          <button key={r.code} type="button" className="tile stat-tile" aria-pressed={code === r.code} onClick={() => nav({ code: code === r.code ? null : r.code })}
            style={{ textAlign: "left", font: "inherit", border: code === r.code ? "2px solid var(--chrome)" : undefined }}>
            <div className="eyebrow">{r.label}</div>
            <div className="n tnum" style={w.counts[r.code] ? { color: "var(--red-ink)" } : undefined}>{vz(w.counts[r.code])}</div>
            <div className="c">{r.who}</div>
          </button>
        ))}
      </div>

      {!totalAll ? <Note kind="ok" title="No examination card is withheld">Every approved registration of {sub} has its examination card.</Note> : null}

      <Panel title={code ? reasonLabel(code) : "Every reason"} right={`${vz(w.total)}${pages > 1 ? ` · page ${w.page + 1} of ${pages}` : ""}`}>
        <PBody>
          <div className="row row--between" style={{ flexWrap: "wrap", gap: 8 }}>
            <span className="sub2">{faculty ? <>Faculty <b>{faculty}</b> · <button type="button" className="lnk" onClick={() => nav({ faculty: null })}>all faculties</button></> : "Choose a faculty from a row to narrow the list."}</span>
            <span className="row row--inline row--tight">
              {mayRemind ? <Btn kind="secondary" size="sm" disabled={!w.total} onClick={() => setRemind(code || "ALL")}>Remind these students</Btn> : null}
              <Btn kind="secondary" size="sm" disabled={!w.total} onClick={async () => { const rows = await allRows(); if (rows) downloadBlob(await brandedXlsx("Examination Cards Withheld", HEAD, rows, { sheetName: "Withheld", serial: docSerial("EXC"), sub }), "examination-cards-withheld.xlsx"); }}>Excel</Btn>
              <Btn kind="ghost" size="sm" disabled={!w.total} onClick={async () => { const rows = await allRows(); if (rows) brandedPrint("Examination Cards Withheld", sub, HEAD, rows, docSerial("EXC")); }}>PDF</Btn>
            </span>
          </div>
        </PBody>
        {w.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Faculty|mid", "Department|mid", "Programme", "Level|mid", "Semester|mid", "Reason"]}
            rows={w.rows.map((r, i) => [
              <span key="n" className="tnum sub2">{w.page * w.size + i + 1}</span>,
              <span key="s"><Link className="lnk" href={`/students/${r.student_id}`}>{r.full_name}</Link><div className="sub2 tnum">{r.matric_no ?? ""}</div></span>,
              <button key="f" type="button" className="lnk" onClick={() => nav({ faculty: r.faculty_code })}>{r.faculty_code ?? "—"}</button>,
              <span key="d">{r.dept_code ?? "—"}</span>,
              <span key="p" className="sub2">{r.programme ?? "—"}</span>,
              <span key="l" className="tnum">{r.level ?? "—"}</span>,
              <span key="m" className="tnum">{r.semester}</span>,
              <Pil key="c" kind={r.code === "EXAM_CARD_NOT_CLEARED" ? "bad" : r.code === "EXAM_CARD_NOT_RELEASED" ? "info" : "warn"}>{reasonLabel(r.code)}</Pil>,
            ])} />
        ) : <PBody><div className="sub2">None.</div></PBody>}
        {pages > 1 ? (
          <PBody><div className="row row--between">
            <Btn kind="ghost" disabled={w.page === 0} onClick={() => nav({ page: w.page - 1 })}>Previous</Btn>
            <Btn kind="ghost" disabled={w.page + 1 >= pages} onClick={() => nav({ page: w.page + 1 })}>Next</Btn>
          </div></PBody>
        ) : null}
      </Panel>

      {remind ? (
        <Modal title="REMIND THESE STUDENTS" onClose={() => setRemind(null)}
          foot={<><Btn kind="ghost" onClick={() => setRemind(null)}>Cancel</Btn><Btn kind="primary" busyLabel="Sending…" onClick={() => sendReminder()}>Send the reminder</Btn></>}>
          <div className="stack">
            <div>Each student whose examination card for <b>{sub}</b> is withheld{remind === "ALL" ? "" : <> because it is <b>{reasonLabel(remind).toLowerCase()}</b></>} is told why, by email, text and in the portal — once a day at most. The notice names no amount.</div>
            <div className="sub2">Students not in study are not reminded.</div>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
