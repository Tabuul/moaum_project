"use client";

/** The Admissions Office's eligibility register (V266): every submitted applicant against the session's admission settings —
 *  the verdict on the programme applied for, the failed requirements, the suggested programmes — searched and filtered on
 *  the server; the matching details side by side; recalculation for one or all; the programme-change queue decided here;
 *  the three reports as Excel or PDF with S/N first and names A–Z. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { VERDICT, headline, parseChecks, whenAt, type ChangeRequest, type Detail, type ResultRow } from "@/lib/eligibility";
import { CheckTables, Mark, ReasonList, VerdictPil } from "@/lib/eligibility-view";
import type { EligibilityList } from "./page";

export interface DeskFilters { session: string; q: string; fac: string; dept: string; prog: string; status: string; recommended: string; mode: string }
const OFFICE = ["academic", "registrar", "dregistrar", "super"];

export function EligibilityDesk({ list, changes, filters, actingOffice }: { list: EligibilityList; changes: ChangeRequest[]; filters: DeskFilters; actingOffice: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const may = OFFICE.includes(actingOffice ?? "");
  const [q, setQ] = useState(filters.q);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [open, setOpen] = useState<Detail | null>(null);
  const [viewing, setViewing] = useState<ResultRow | null>(null);
  const [showAll, setShowAll] = useState(false);
  const [deciding, setDeciding] = useState<{ c: ChangeRequest; kind: "approve" | "reject" } | null>(null);
  const [note, setNote] = useState("");
  const [requesting, setRequesting] = useState<ResultRow | null>(null);
  const t = list.stats;
  const rows = list.rows;
  const base = `/api/bff/api/v1/admissions/sessions/${filters.session}/eligibility`;
  const go = (next: Partial<DeskFilters>) => { const f = { ...filters, ...next }; if (next.fac !== undefined) { f.dept = ""; f.prog = ""; } if (next.dept !== undefined) f.prog = ""; const qs = new URLSearchParams(); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/admissions/eligibility?${qs}`); };
  const faculties = [...new Map(list.options.map((o) => [o.faculty_code, o.faculty])).entries()];
  const depts = [...new Map(list.options.filter((o) => !filters.fac || o.faculty_code === filters.fac).filter((o) => o.dept_code).map((o) => [o.dept_code as string, o.department as string])).entries()];
  const progs = [...new Map(list.options.filter((o) => (!filters.fac || o.faculty_code === filters.fac) && (!filters.dept || o.dept_code === filters.dept)).map((o) => [o.programme_code, o.programme])).entries()];

  async function call<T>(path: string, body: unknown, label: string, key: string): Promise<T | null> {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`${base}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return null; }
      notify(label); return j as T;
    } finally { setBusy(null); }
  }
  async function openOne(id: string) {
    setBusy(id);
    try {
      const r = await fetch(`${base}/${id}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setOpen(j as Detail); setShowAll(false);
    } finally { setBusy(null); }
  }
  const recalc = async (id: string) => { const d = await call<Detail>(`/${id}/recalculate`, {}, "Eligibility recalculated", id); if (d) { setOpen(d); router.refresh(); } };
  const recalcAll = async (onlyMissing: boolean) => { const r = await call<{ evaluated: number }>(`/recalculate-all?onlyMissing=${onlyMissing}`, {}, onlyMissing ? "Unevaluated applications evaluated" : "Every application re-evaluated", "all"); if (r) { notify(`${r.evaluated} application(s) evaluated`); router.refresh(); } };
  const decide = async () => {
    if (!deciding) return;
    if (deciding.kind === "reject" && !note.trim()) { const pr: Problem = { status: 422, title: "A rejection carries its reason." }; setProblem(pr); notifyProblem(pr); return; }
    const d = await call<Detail>(`/changes/${deciding.c.id}/${deciding.kind}`, { note: note.trim() || null }, deciding.kind === "approve" ? `Programme change approved: ${deciding.c.to_programme}` : `Programme change rejected`, deciding.c.id);
    if (d) { setDeciding(null); setNote(""); setOpen(null); router.refresh(); }
  };
  const officeRequest = async () => {
    if (!open || !requesting) return;
    const d = await call<Detail>(`/${open.application.id}/change`, { programmeCode: requesting.programme_code, note: note.trim() || null }, `Change to ${requesting.programme} requested for ${open.application.surname}`, "req");
    if (d) { setOpen(d); setRequesting(null); setNote(""); router.refresh(); }
  };

  const verdict = (v: string | null) => (v ? VERDICT[v as keyof typeof VERDICT]?.[0] ?? v : "NOT EVALUATED");
  const HEAD1 = ["S/N", "Applicant", "JAMB No.", "Application No.", "Applied Programme", "Faculty", "Department", "Mode", "Eligibility", "Failed Requirements", "Alternatives", "Suggested Programmes", "Change Request"];
  const body1 = () => rows.map((r, i) => [i + 1, `${r.surname}, ${r.other_names}`, r.jamb_reg_no, r.application_no, r.programme, r.faculty ?? "", r.department ?? "", r.entry_mode, verdict(r.applied_result), (r.reasons ?? []).join("; "), r.alternatives ?? "", r.top_alternatives ?? "", r.change_state ? `${r.change_to} · ${r.change_state}` : ""]);
  const sub = [filters.status, filters.fac, filters.dept, filters.prog, filters.recommended, filters.mode, filters.q ? `search “${filters.q}”` : ""].filter(Boolean).join(" · ") || "Every submitted application";
  const excel = async (title: string, head: string[], body: (string | number)[][], file: string) => { const blob = await brandedXlsx(title, head, body, { sheetName: "Eligibility", serial: docSerial("ELG"), sub: `${filters.session} · ${sub}` }); downloadBlob(blob, file); };
  const notEligible = rows.filter((r) => r.applied_result === "NOT_ELIGIBLE");
  const HEAD2 = ["S/N", "Applicant", "Applied Programme", "Reason", "Alternatives"];
  const body2 = () => notEligible.map((r, i) => [i + 1, `${r.surname}, ${r.other_names}`, r.programme, (r.reasons ?? []).join("; "), r.top_alternatives ?? (r.alternatives ? String(r.alternatives) : "None")]);
  const HEAD3 = ["S/N", "Applicant", "Original Programme", "Suggested Programme", "Eligibility"];
  const body3 = () => notEligible.filter((r) => r.top_alternatives).flatMap((r) => (r.top_alternatives ?? "").split(" · ").map((p) => [`${r.surname}, ${r.other_names}`, r.programme, p, "Eligible"])).map((x, i) => [i + 1, ...x]);

  const openChanges = changes.filter((c) => c.state === "REQUESTED");
  const applied = open?.applied ?? null;
  const alts = open ? (showAll ? open.alternatives : open.alternatives.filter((a) => a.result === "ELIGIBLE" || a.result === "ELIGIBLE_SCREENING")) : [];

  return (
    <>
      <PageHead title="Programme Eligibility" description={`${filters.session} · every submitted applicant read against the session's admission settings — the applied programme first, then every other active, open programme when it is refused. Rule-based, explained check by check, kept under the policy version it was read under. Nothing here admits anybody or changes a programme by itself.`}
        actions={<><LinkBtn kind="ghost" href={`/admissions?session=${encodeURIComponent(filters.session)}`}>Admissions</LinkBtn><LinkBtn kind="ghost" href={`/admissions/settings?session=${encodeURIComponent(filters.session)}`}>Admission Settings</LinkBtn>
          {may ? <><Btn kind="secondary" disabled={busy !== null} onClick={() => void recalcAll(true)}>Evaluate the unevaluated{t.not_evaluated ? ` (${t.not_evaluated})` : ""}</Btn><Btn kind="ghost" disabled={busy !== null} onClick={() => void recalcAll(false)}>Recalculate all</Btn></> : null}
          <Btn kind="secondary" onClick={() => void excel("Programme Eligibility Register", HEAD1, body1(), "eligibility-register.xlsx")} disabled={!rows.length}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Programme Eligibility Register", `${filters.session} · ${sub}`, HEAD1, body1(), docSerial("ELG"))} disabled={!rows.length}>PDF</Btn></>} />
      {problem ? <Note kind="bad" title={problem.title}>{problem.detail ?? ""}</Note> : null}
      <Tiles items={[
        ["Applicants evaluated", String(t.evaluated), null, t.not_evaluated ? `${t.not_evaluated} submitted, not yet evaluated` : "Every submitted application"],
        ["Eligible", String(Number(t.eligible) + Number(t.eligible_screening)), "var(--green-ink)", t.eligible_screening ? `${t.eligible_screening} need additional screening` : "For the programme applied for"],
        ["Not eligible", String(t.not_eligible), t.not_eligible ? "var(--red-ink)" : null, "On the current admission policy"],
        ["Alternatives available", String(t.with_alternatives), t.with_alternatives ? "var(--chrome)" : null, "Not eligible, with an eligible programme"],
        ["No eligible alternative", String(t.without_alternatives), null, "Not eligible, nothing found"],
        ["Pending verification", String(t.unverified), t.unverified ? "var(--amber-ink)" : null, "A result the rules need is not on record"],
        ["Change requests open", String(t.change_requests_open), t.change_requests_open ? "var(--amber-ink)" : null, "Awaiting the Office"],
        ["Stale evaluations", String(t.stale), t.stale ? "var(--amber-ink)" : null, "Record changed since; re-read on open"],
      ]} />

      <div className="scope">
        <div className="scope__f"><Field id="el-status" label="Eligibility"><select id="el-status" className="ctl" value={filters.status} onChange={(e) => go({ status: e.target.value })}><option value="">Every status</option><option value="ELIGIBLE">Eligible</option><option value="NOT_ELIGIBLE">Not eligible</option><option value="ALTERNATIVES">Alternatives available</option><option value="NO_ALTERNATIVES">No alternatives</option><option value="UNVERIFIED">Pending verification</option><option value="PENDING_CHANGE">Change requested</option><option value="NOT_EVALUATED">Not evaluated</option></select></Field></div>
        <div className="scope__f"><Field id="el-fac" label="Faculty"><select id="el-fac" className="ctl" value={filters.fac} onChange={(e) => go({ fac: e.target.value })}><option value="">All</option>{faculties.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="el-dept" label="Department"><select id="el-dept" className="ctl" value={filters.dept} onChange={(e) => go({ dept: e.target.value })}><option value="">All</option>{depts.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="el-prog" label="Programme applied"><select id="el-prog" className="ctl" value={filters.prog} onChange={(e) => go({ prog: e.target.value })}><option value="">All</option>{progs.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="el-rec" label="Recommended programme"><select id="el-rec" className="ctl" value={filters.recommended} onChange={(e) => go({ recommended: e.target.value })}><option value="">Any</option>{list.recommendable.map((p) => <option key={p.programme_code} value={p.programme_code}>{p.programme}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="el-mode" label="Mode"><select id="el-mode" className="ctl" value={filters.mode} onChange={(e) => go({ mode: e.target.value })}><option value="">Both</option><option value="UTME">UTME</option><option value="DIRECT_ENTRY">Direct Entry</option></select></Field></div>
        <div className="scope__f grow"><Field id="el-q" label="Search" hint="Applicant name, JAMB number, application number, programme, faculty or department">
          <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}><input id="el-q" className="ctl" placeholder="Search candidates…" value={q} onChange={(e) => setQ(e.target.value)} /><Btn kind="primary" type="submit">Search</Btn><Btn kind="ghost" onClick={() => { setQ(""); queryNav(`/admissions/eligibility?session=${encodeURIComponent(filters.session)}`); }}>Reset</Btn></form>
        </Field></div>
      </div>

      <Panel title="Applicant eligibility" right={`${rows.length} · names A–Z${rows.length >= 500 ? " · first 500; narrow the search" : ""}`}>
        {rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Applicant", "Applied programme", "Eligibility|mid", "Failed requirements", "Suggested programmes", "Change", "|num"]} rows={rows.map((r, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>,
            <span key="a"><strong>{r.surname}, {r.other_names}</strong><div className="sub2 tnum">{r.jamb_reg_no} · {r.application_no} · {r.entry_mode === "UTME" ? "UTME" : "Direct Entry"}</div></span>,
            <span key="p">{r.programme}<div className="sub2">{r.faculty ?? ""}{r.department ? ` · ${r.department}` : ""}</div></span>,
            <span key="v"><VerdictPil v={r.applied_result} />{r.stale ? <div><Pil kind="warn">Stale</Pil></div> : null}</span>,
            <span key="f" className="sub2">{(r.reasons ?? []).slice(0, 3).map((x, k) => <div key={k}>✕ {x}</div>)}{(r.reasons ?? []).length > 3 ? <div>… {(r.reasons ?? []).length - 3} more</div> : null}</span>,
            <span key="s" className="sub2">{r.applied_result === "NOT_ELIGIBLE" ? (r.top_alternatives ? <>{r.top_alternatives}{(r.alternatives ?? 0) > 3 ? ` … ${r.alternatives} in all` : ""}</> : <span className="ink-red">None found</span>) : "—"}</span>,
            <span key="c">{r.change_state ? <Pil kind={r.change_state === "REQUESTED" ? "warn" : r.change_state === "APPROVED" ? "ok" : "grey"}>{r.change_to} · {r.change_state}</Pil> : null}</span>,
            <span key="x" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}><Btn kind="primary" size="sm" disabled={busy === r.id} onClick={() => void openOne(r.id)}>View Matching Details</Btn>{may ? <Btn kind="ghost" size="sm" disabled={busy === r.id} onClick={() => void recalc(r.id)}>Recalculate</Btn> : null}</span>,
          ])} texts={rows.map((r) => `${r.surname} ${r.other_names} ${r.jamb_reg_no} ${r.application_no} ${r.programme} ${r.faculty ?? ""} ${r.top_alternatives ?? ""}`)} />
        ) : <PBody><Note kind="info" title="No applicant matches">No submitted application matches the filters{t.not_evaluated ? `; ${t.not_evaluated} are not yet evaluated — press Evaluate the unevaluated` : ""}.</Note></PBody>}
      </Panel>

      <div className="grid grid--2">
        <Panel title="Programme change requests" right={openChanges.length ? <Pil kind="warn">{openChanges.length} awaiting decision</Pil> : `${changes.length} in all`}>
          {changes.length ? (
            <DTable pageSize={20} cols={["Applicant", "From → To", "Eligibility|mid", "Requested|mid", "State|mid", "|num"]} rows={changes.map((c) => [
              <span key="a"><strong>{c.surname}, {c.other_names}</strong><div className="sub2 tnum">{c.jamb_reg_no} · {c.application_no} · by {c.requested_by_kind === "APPLICANT" ? "the applicant" : "the Office"}</div></span>,
              <span key="p">{c.from_programme}<div>→ <b>{c.to_programme}</b></div>{c.note ? <div className="sub2">{c.note}</div> : null}</span>,
              <VerdictPil key="v" v={c.eligibility_at_decision ?? c.eligibility_at_request} />,
              <span key="r" className="tnum sub2">{whenAt(c.requested_at)}</span>,
              <span key="s"><Pil kind={c.state === "REQUESTED" ? "warn" : c.state === "APPROVED" ? "ok" : c.state === "REJECTED" ? "bad" : "grey"}>{c.state}</Pil>{c.decided_at ? <div className="sub2">{whenAt(c.decided_at)}{c.decided_officer ? ` · ${c.decided_officer}` : ""}{c.decision_note ? ` · ${c.decision_note}` : ""}</div> : null}</span>,
              <span key="x" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>{c.state === "REQUESTED" && may ? <><Btn kind="go" size="sm" disabled={busy !== null} onClick={() => { setNote(""); setDeciding({ c, kind: "approve" }); }}>Approve</Btn><Btn kind="urgent" size="sm" disabled={busy !== null} onClick={() => { setNote(""); setDeciding({ c, kind: "reject" }); }}>Reject</Btn></> : null}<Btn kind="ghost" size="sm" onClick={() => void openOne(c.application_id)}>Details</Btn></span>,
            ])} />
          ) : <PBody><div className="sub2">No change of programme has been requested this session.</div></PBody>}
        </Panel>
        <Panel title="Reports" right="Excel and PDF · S/N first · names A–Z">
          <PBody>
            <div className="stack">
              <div className="row row--between"><span><b>Candidates not eligible for the applied programme</b><div className="sub2">{notEligible.length} in the current view</div></span><span className="row row--inline row--tight"><Btn kind="secondary" size="sm" disabled={!notEligible.length} onClick={() => void excel("Candidates Not Eligible for Applied Programme", HEAD2, body2(), "not-eligible.xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" disabled={!notEligible.length} onClick={() => brandedPrint("Candidates Not Eligible for Applied Programme", `${filters.session} · ${sub}`, HEAD2, body2(), docSerial("ELG"))}>PDF</Btn></span></div>
              <div className="row row--between"><span><b>Alternative programme suggestions</b><div className="sub2">One line per suggested programme (the first three per candidate)</div></span><span className="row row--inline row--tight"><Btn kind="secondary" size="sm" disabled={!body3().length} onClick={() => void excel("Alternative Programme Suggestions", HEAD3, body3(), "suggestions.xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" disabled={!body3().length} onClick={() => brandedPrint("Alternative Programme Suggestions", `${filters.session} · ${sub}`, HEAD3, body3(), docSerial("ELG"))}>PDF</Btn></span></div>
              <div className="row row--between"><span><b>Programme eligibility statistics</b><div className="sub2">The tiles above, as a sheet</div></span><span className="row row--inline row--tight"><Btn kind="secondary" size="sm" onClick={() => void excel("Programme Eligibility Statistics", ["S/N", "Measure", "Count"], [["Applicants evaluated", t.evaluated], ["Eligible", Number(t.eligible) + Number(t.eligible_screening)], ["Eligible — additional screening required", t.eligible_screening], ["Not eligible", t.not_eligible], ["Alternatives available", t.with_alternatives], ["No eligible alternative", t.without_alternatives], ["Pending verification", t.unverified], ["Change requests open", t.change_requests_open], ["Not yet evaluated", t.not_evaluated]].map((x, i) => [i + 1, x[0], Number(x[1])]), "eligibility-statistics.xlsx")}>Excel</Btn></span></div>
            </div>
          </PBody>
        </Panel>
      </div>

      {open ? (
        <Modal title={`${open.application.surname}, ${open.application.other_names} · ${open.application.application_no}`} sub={`${open.application.jamb_reg_no} · ${open.application.entry_mode === "UTME" ? "UTME" : "Direct Entry"} · read ${whenAt(open.run.evaluated_at)} under ${open.run.session} policy version ${open.run.rules_version ?? "?"}${open.run.policy_state && open.run.policy_state !== "IN_FORCE" ? " (draft — provisional)" : ""}`} wide onClose={() => { setOpen(null); setViewing(null); }}
          foot={<>{may ? <Btn kind="ghost" disabled={busy !== null} onClick={() => void recalc(open.application.id)}>Recalculate Eligibility</Btn> : null}<span className="grow" /><Btn kind="primary" onClick={() => { setOpen(null); setViewing(null); }}>Close</Btn></>}>
          <div className="stack">
            <Note kind={open.run.applied_result === "NOT_ELIGIBLE" ? "bad" : open.run.applied_result === "UNVERIFIED" ? "info" : "ok"} title={`Applied programme: ${applied?.programme ?? open.run.applied_programme ?? "—"} — ${VERDICT[open.run.applied_result]?.[0] ?? open.run.applied_result}`}>
              <ReasonList row={applied} />
            </Note>
            <div className="grid grid--2">
              <div><div className="eyebrow mb-1">O&rsquo;Level on record</div>{open.olevel?.length ? open.olevel.map((s, i) => { let subj: { subject: string; grade: string }[] = []; try { subj = JSON.parse(s.subjects) as { subject: string; grade: string }[]; } catch { subj = []; } return <div key={i} className="sub2"><b>{s.exam_body}{s.exam_year ? ` ${s.exam_year}` : ""}</b>{s.exam_number ? ` · ${s.exam_number}` : ""}: {subj.map((x) => `${x.subject} ${x.grade}`).join(", ")}</div>; }) : <div className="sub2">None on record.</div>}</div>
              <div><div className="eyebrow mb-1">UTME on record</div><div className="sub2">{open.utme ? <>Score <b className="tnum">{open.utme.aggregate ?? "—"}</b>{open.utme.subjects ? <> · {open.utme.subjects}</> : null}</> : "No CAPS row."}</div></div>
            </div>
            <div className="eyebrow">Matching details — the programme applied for</div>
            <CheckTables row={applied} />
            <div className="row row--between"><div className="eyebrow">Suggested programmes{open.run.applied_result !== "NOT_ELIGIBLE" ? " (searched only when the applied programme is refused)" : ""}</div>{open.alternatives.length ? <label className="sub2 row row--tight" style={{ gap: 6 }}><input type="checkbox" className="pchk" checked={showAll} onChange={(e) => setShowAll(e.target.checked)} /> Show every programme evaluated, including the ineligible (diagnostics)</label> : null}</div>
            {alts.length ? (
              <DTable pageSize={0} cols={["S/N|num", "Programme", "Faculty", "O'Level|mid", "UTME|mid", "Score|mid", "Overall", "Reasons", "|num"]} rows={alts.map((a, i) => { const h = headline(parseChecks(a)); return [
                <span key="sn" className="tnum sub2">{i + 1}</span>, <strong key="p">{a.programme}</strong>, <span key="f" className="sub2">{a.faculty ?? ""}{a.department ? ` · ${a.department}` : ""}</span>,
                <Mark key="o" s={h.olevel} />, <Mark key="u" s={h.combination} />, <Mark key="s" s={h.score} />, <VerdictPil key="v" v={a.result} />,
                <span key="r" className="sub2">{a.reasons.slice(0, 2).join("; ")}</span>,
                <span key="x" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}><Btn kind="ghost" size="sm" onClick={() => setViewing(viewing?.programme_code === a.programme_code ? null : a)}>{viewing?.programme_code === a.programme_code ? "Hide details" : "View Eligibility Details"}</Btn>{may && (a.result === "ELIGIBLE" || a.result === "ELIGIBLE_SCREENING") && !open.changes.some((c) => c.state === "REQUESTED") && !open.application.decision_released_at ? <Btn kind="secondary" size="sm" onClick={() => { setNote(""); setRequesting(a); }}>Request Change</Btn> : null}</span>,
              ]; })} />
            ) : <div className="sub2">{open.run.applied_result === "NOT_ELIGIBLE" ? "No eligible alternative programme was found based on the submitted qualifications and the current admission policy." : "—"}</div>}
            {viewing ? <div><div className="eyebrow mb-1">Matching details — {viewing.programme}</div><CheckTables row={viewing} /></div> : null}
            {open.changes.length ? <div><div className="eyebrow mb-1">Change requests</div>{open.changes.map((c) => <div key={c.id} className="sub2">{whenAt(c.requested_at)} · {c.from_programme} → <b>{c.to_programme}</b> · <Pil kind={c.state === "REQUESTED" ? "warn" : c.state === "APPROVED" ? "ok" : "grey"}>{c.state}</Pil>{c.decision_note ? ` · ${c.decision_note}` : ""}</div>)}</div> : null}
            {open.events?.length ? <div><div className="eyebrow mb-1">Trail</div><ol className="plain" style={{ display: "grid", gap: 4 }}>{open.events.slice(0, 20).map((e, i) => <li key={i} className="sub2 row row--tight" style={{ gap: 8 }}><span className="tnum" style={{ minWidth: 140 }}>{whenAt(e.at)}</span><b>{e.action.replace(/_/g, " ").toLowerCase()}</b><span>{e.detail}</span>{e.actor_office ? <Pil kind="grey">{e.actor_office}</Pil> : null}</li>)}</ol></div> : null}
          </div>
        </Modal>
      ) : null}
      {deciding ? (
        <Modal title={`${deciding.kind === "approve" ? "Approve" : "Reject"} the change to ${deciding.c.to_programme}`} sub={`${deciding.c.surname}, ${deciding.c.other_names} · from ${deciding.c.from_programme}`} onClose={() => setDeciding(null)}
          foot={<><Btn kind="ghost" onClick={() => setDeciding(null)}>Back</Btn><Btn kind={deciding.kind === "approve" ? "go" : "urgent"} disabled={busy !== null} onClick={() => void decide()}>{deciding.kind === "approve" ? "Approve and change the programme" : "Reject"}</Btn></>}>
          <p>{deciding.kind === "approve" ? "The candidate's eligibility for the programme is read again at this moment; if it still holds, the application's programme changes on the record, the evaluation is re-run and the applicant is told. This is not an offer of admission." : "The applicant is told the reason you write; the application stands as it was."}</p>
          <Field id="dc-note" label={deciding.kind === "approve" ? "Note (optional)" : "Reason (required)"}><textarea id="dc-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {requesting && open ? (
        <Modal title={`Request a change to ${requesting.programme} on the applicant's behalf`} sub={`${open.application.surname}, ${open.application.other_names}`} onClose={() => setRequesting(null)}
          foot={<><Btn kind="ghost" onClick={() => setRequesting(null)}>Back</Btn><Btn kind="primary" disabled={busy !== null} onClick={() => void officeRequest()}>Record the request</Btn></>}>
          <p>The request goes on the queue like the applicant&rsquo;s own and is decided separately; the programme does not change here.</p>
          <Field id="rq-note" label="Note"><textarea id="rq-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
