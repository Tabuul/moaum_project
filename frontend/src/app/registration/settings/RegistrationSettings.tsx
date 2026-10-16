"use client";

/**
 * Course registration settings (V495): the minimum course registration load of each curriculum (CCMAS, BMAS) — the standing rule,
 * or a session's or semester's own — set by the Directorate of ICT with a reason, confirmed before it is saved; the undergraduate
 * maxima it may not pass (kept on Session & Semester Setup); every rule set and every change, with the value before and after; the
 * registrations of the session below the minimum that binds them. The server decides and checks every part of it.
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
import { APPLIES_WORD, changeWord, minimumProblem, type BelowRow, type InForce, type LoadRules } from "@/lib/registration-load";

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const vz = (n: number | null | undefined) => Number(n ?? 0).toLocaleString("en-GB");
const scopeWord = (session: string | null, semester: number | null) =>
  session ? `${session}${semester ? ` · ${semesterWord(semester)}` : " · every semester"}` : "Every session (the standing rule)";

type Scope = "STANDING" | "SESSION" | "SEMESTER";
interface Pending { kind: "SET" | "REMOVE"; curriculum: string; current: number | null; next: number | null; session: string | null; semester: number | null }

export function RegistrationSettings({ rules, session, semester, below, mayChange }: {
  rules: LoadRules; session: string; semester: number | null; below: { total: number; page: number; size: number; rows: BelowRow[] } | null; mayChange: boolean;
}) {
  const router = useRouter();
  const go = useQueryNav();
  const nav = (patch: Record<string, string | number | null>) => {
    const next: Record<string, string> = { session, semester: semester ? String(semester) : "", page: "0" };
    for (const [k, v] of Object.entries(patch)) next[k] = v == null ? "" : String(v);
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "page" && v === "0")) qs.set(k, v);
    go(`/registration/settings?${qs.toString()}`);
  };
  const ceiling = rules.maxima.length ? Math.min(...rules.maxima.map((m) => m.max_units)) : null;
  const ceilingLevel = rules.maxima.find((m) => m.max_units === ceiling)?.level;
  const defaultScope = (f: InForce): Scope => (f.applies_as === "SEMESTER" && semester ? "SEMESTER" : f.applies_as === "SESSION" ? "SESSION" : "STANDING");
  const [draft, setDraft] = useState<Record<string, { value: string; scope: Scope }>>(
    Object.fromEntries(rules.inForce.map((f) => [f.curriculum, { value: f.min_units != null ? String(f.min_units) : "", scope: defaultScope(f) }])));
  const [pending, setPending] = useState<Pending | null>(null);
  const [reason, setReason] = useState("");

  const scopeOf = (s: Scope) => ({ session: s === "STANDING" ? null : session, semester: s === "SEMESTER" ? semester : null });
  /** the minimum that the chosen scope holds now: its own row, or nothing yet (the wider rule then applies) */
  const heldAt = (curriculum: string, s: Scope) => {
    const sc = scopeOf(s);
    return rules.rules.find((r) => r.curriculum === curriculum && r.session === sc.session && (r.semester ?? null) === (sc.semester ?? null))?.min_units ?? null;
  };

  function ask(f: InForce) {
    const d = draft[f.curriculum];
    const sc = scopeOf(d.scope);
    setReason("");
    setPending({ kind: "SET", curriculum: f.curriculum, current: heldAt(f.curriculum, d.scope) ?? f.min_units, next: Number(d.value.trim()), ...sc });
  }

  async function confirm() {
    if (!pending) return;
    const set = pending.kind === "SET";
    const r = await fetch(`/api/bff/api/v1/registration/load/${set ? "rules" : "rules/remove"}`, {
      method: set ? "PUT" : "POST",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Minimum course registration load of ${pending.curriculum}${set ? ` set to ${pending.next}` : " removed"} for ${scopeWord(pending.session, pending.semester)}: ${reason.trim()}`) },
      body: JSON.stringify(set
        ? { curriculum: pending.curriculum, session: pending.session, semester: pending.semester, minUnits: pending.next, reason: reason.trim() }
        : { curriculum: pending.curriculum, session: pending.session, semester: pending.semester, reason: reason.trim() }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setPending(null);
    notify("Course registration settings updated successfully.");
    router.refresh();
  }

  const HEAD = ["S/N", "Student", "Matriculation No.", "Programme", "Level", "Semester", "Curriculum", "Min CU", "Registered CU", "Max CU", "Status"];
  const body = () => (below?.rows ?? []).map((r, i) => [(below!.page * below!.size) + i + 1, r.full_name, r.matric_no ?? "", r.programme ?? "", r.level, r.semester,
    r.curriculum ?? (r.basis === "CCE" ? "CCE load" : "Level"), r.min_units, r.units, r.max_units, r.status]);
  const sub = `${session}${semester ? ` · ${semesterWord(semester)}` : ""}`;
  const pages = below ? Math.max(1, Math.ceil(below.total / below.size)) : 1;

  return (
    <>
      <PageHead title="Course registration settings" eyebrow="Academic settings"
        description="The least number of credit units a student's course registration must carry, by curriculum. A submission, an add or a drop below it is refused, and automatic approval never approves one. A change applies to the next submission at once; a registration already made is not rewritten." />

      <div className="row" style={{ flexWrap: "wrap", gap: 12 }}>
        <Field id="rs-session" label="Academic session"><select id="rs-session" className="ctl" value={session} onChange={(e) => nav({ session: e.target.value })}>
          {rules.sessions.map((s) => <option key={s} value={s}>{s}{s === rules.current ? " (current)" : ""}</option>)}
        </select></Field>
        <Field id="rs-semester" label="Semester"><select id="rs-semester" className="ctl" value={semester ? String(semester) : ""} onChange={(e) => nav({ semester: e.target.value || null })}>
          <option value="">All semesters</option><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option>
        </select></Field>
      </div>

      <Panel title="Minimum credit units" right={sub}>
        <PBody>
          <div className="grid grid--2">
            {rules.inForce.map((f) => {
              const d = draft[f.curriculum] ?? { value: "", scope: "STANDING" as Scope };
              const problem = minimumProblem(d.value, ceiling);
              const unchanged = !problem && Number(d.value) === (heldAt(f.curriculum, d.scope) ?? (d.scope === "STANDING" ? f.min_units : null));
              return (
                <div key={f.curriculum} className="card"><div className="card__body stack">
                  <div className="row row--between">
                    <span className="b700" style={{ fontSize: "var(--t-lg)" }}>{f.curriculum}</span>
                    <Pil kind={f.applies_as === "STANDING" ? "grey" : "info"}>{APPLIES_WORD[f.applies_as]}</Pil>
                  </div>
                  <div className="row row--base">
                    <span className="tnum b700" style={{ fontSize: "var(--t-3xl)" }}>{f.min_units ?? "—"}</span>
                    <span className="ink-muted">credit units minimum · {vz(f.students)} undergraduate{f.students === 1 ? "" : "s"} in study</span>
                  </div>
                  {f.reason ? <div className="sub2">{f.reason}{f.set_by ? ` — ${f.set_by}` : ""}{f.set_at ? `, ${when(f.set_at)}` : ""}</div> : null}
                  {mayChange ? (
                    <div className="row" style={{ flexWrap: "wrap", gap: 12, alignItems: "flex-end" }}>
                      <Field id={`rs-min-${f.curriculum}`} label="Minimum credit units" error={d.value.trim() && problem ? problem : undefined}>
                        <input id={`rs-min-${f.curriculum}`} className="ctl tnum" inputMode="numeric" style={{ width: 96 }} value={d.value}
                          onChange={(e) => setDraft({ ...draft, [f.curriculum]: { ...d, value: e.target.value } })} />
                      </Field>
                      <Field id={`rs-scope-${f.curriculum}`} label="Applies to">
                        <select id={`rs-scope-${f.curriculum}`} className="ctl" value={d.scope} onChange={(e) => setDraft({ ...draft, [f.curriculum]: { ...d, scope: e.target.value as Scope } })}>
                          <option value="STANDING">Every session (the standing rule)</option>
                          {session ? <option value="SESSION">{session} only</option> : null}
                          {session && semester ? <option value="SEMESTER">{session} · {semesterWord(semester)} only</option> : null}
                        </select>
                      </Field>
                      <Btn kind="primary" disabled={!!problem || unchanged} onClick={() => ask(f)}>Save settings</Btn>
                    </div>
                  ) : null}
                </div></div>
              );
            })}
          </div>
          <div className="sub2 mt-1">
            A minimum is a whole number from 1 up to the lowest undergraduate maximum{ceiling != null ? <> (<b className="tnum">{ceiling}</b> credit units at {ceilingLevel} level)</> : null}.
            The maximum of each level is kept on Session &amp; Semester Setup. A student&rsquo;s curriculum is read from their record. A postgraduate keeps their level&rsquo;s load, and a CCE student the Centre&rsquo;s load where it stated one.
          </div>
        </PBody>
      </Panel>

      <div className="grid grid--2">
        <Panel title="The rules set" right={`${rules.rules.length}`}>
          <DTable pageSize={0} cols={["Curriculum", "Applies to", "Minimum|num", "Set", "|num"]} rows={rules.rules.map((x) => [
            <b key="c">{x.curriculum}</b>,
            <span key="a">{x.session ? scopeWord(x.session, x.semester) : <b>The standing rule</b>}</span>,
            <span key="m" className="tnum b600">{x.min_units}</span>,
            <span key="s" className="sub2">{x.set_by ?? "—"}{x.set_office ? ` (${x.set_office})` : ""}<div>{when(x.set_at)}</div><div>{x.reason}</div></span>,
            mayChange && x.session ? <Btn key="x" kind="ghost" size="sm" onClick={() => { setReason(""); setPending({ kind: "REMOVE", curriculum: x.curriculum, current: x.min_units, next: null, session: x.session, semester: x.semester }); }}>Remove</Btn> : <span key="x" />,
          ])} />
        </Panel>
        <Panel title="Maximum credit units" right="Session & Semester Setup">
          <DTable pageSize={0} cols={["Level|num", "Applies to", "Level minimum|num", "Maximum|num"]} rows={rules.maxima.map((m) => [
            <span key="l" className="tnum">{m.level}</span>, <span key="a" className="sub2">{m.applies_to}</span>,
            <span key="n" className="tnum">{m.min_units}</span>, <span key="x" className="tnum b600">{m.max_units}</span>,
          ])} />
          <PBody><div className="sub2">The level minimum binds a student with no curriculum recorded. The curriculum&rsquo;s minimum binds every undergraduate who has one.</div></PBody>
        </Panel>
      </div>

      <Panel title="Changes" right={`${rules.history.length}${rules.history.length === 100 ? " (latest)" : ""}`}>
        {rules.history.length ? (
          <DTable pageSize={10} cols={["When", "Curriculum", "Applies to", "Change", "Minimum|num", "By", "Reason"]}
            texts={rules.history.map((h) => `${h.curriculum} ${h.session ?? "standing"} ${h.changed_by ?? ""} ${h.reason ?? ""}`)}
            rows={rules.history.map((h) => [
              <span key="w" className="sub2">{when(h.changed_at)}</span>,
              <b key="c">{h.curriculum}</b>,
              <span key="a" className="sub2">{scopeWord(h.session, h.semester)}</span>,
              <Pil key="e" kind={h.event.endsWith("REMOVED") ? "warn" : h.event.endsWith("CHANGED") ? "info" : "grey"}>{changeWord(h.event)}</Pil>,
              <span key="m" className="tnum">{h.before_units ?? "—"} → {h.after_units ?? "—"}</span>,
              <span key="b" className="sub2">{h.changed_by ?? "—"}{h.changed_office ? ` (${h.changed_office})` : ""}</span>,
              <span key="r" className="sub2">{h.reason ?? "—"}</span>,
            ])} />
        ) : <PBody><div className="sub2">No change yet.</div></PBody>}
      </Panel>

      {below ? (
        <Panel title="Registrations below the minimum" right={`${vz(below.total)}${pages > 1 ? ` · page ${below.page + 1} of ${pages}` : ""}`}>
          <PBody>
            <div className="row row--between">
              <span className="sub2">Course registrations of {sub} carrying fewer credit units than the minimum that binds the student: a draft that cannot be submitted yet, or one approved before the minimum changed (kept as it was).</span>
              <span className="row row--inline row--tight">
                <Btn kind="secondary" size="sm" disabled={!below.rows.length} onClick={async () => downloadBlob(await brandedXlsx("Course Registrations Below the Minimum Credit Load", HEAD, body(), { sheetName: "Below minimum", serial: docSerial("REG"), sub }), "registrations-below-minimum.xlsx")}>Excel</Btn>
                <Btn kind="ghost" size="sm" disabled={!below.rows.length} onClick={() => brandedPrint("Course Registrations Below the Minimum Credit Load", sub, HEAD, body(), docSerial("REG"))}>PDF</Btn>
              </span>
            </div>
          </PBody>
          {below.rows.length ? (
            <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Level|mid", "Semester|mid", "Curriculum|mid", "Min CU|num", "Registered CU|num", "Status|mid"]}
              rows={below.rows.map((r, i) => [
                <span key="n" className="tnum sub2">{below.page * below.size + i + 1}</span>,
                <span key="s"><Link className="lnk" href={`/students/${r.student_id}`}>{r.full_name}</Link><div className="sub2 tnum">{r.matric_no ?? ""}</div></span>,
                <span key="p" className="sub2">{r.programme ?? "—"}</span>,
                <span key="l" className="tnum">{r.level}</span>,
                <span key="m" className="tnum">{r.semester}</span>,
                <span key="c">{r.curriculum ?? (r.basis === "CCE" ? "CCE load" : "Level")}</span>,
                <span key="mn" className="tnum">{r.min_units}</span>,
                <span key="u" className="tnum ink-red b600">{r.units}</span>,
                <Pil key="st" kind={r.status === "APPROVED" || r.status === "LOCKED" ? "ok" : r.status === "SUBMITTED" ? "warn" : "grey"}>{r.status}</Pil>,
              ])} />
          ) : <PBody><div className="sub2">None.</div></PBody>}
          {pages > 1 ? (
            <PBody><div className="row row--between">
              <Btn kind="ghost" disabled={below.page === 0} onClick={() => nav({ page: below.page - 1 })}>Previous</Btn>
              <Btn kind="ghost" disabled={below.page + 1 >= pages} onClick={() => nav({ page: below.page + 1 })}>Next</Btn>
            </div></PBody>
          ) : null}
        </Panel>
      ) : null}

      {!mayChange ? <Note kind="info" title="Read only">The Directorate of ICT sets the minimum course registration load.</Note> : null}

      {pending ? (
        <Modal title={pending.kind === "SET" ? "CHANGE MINIMUM CREDIT UNIT" : "REMOVE THIS MINIMUM"} onClose={() => setPending(null)}
          foot={<>
            <Btn kind="ghost" onClick={() => setPending(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={reason.trim().length < 10} busyLabel="SAVING SETTINGS..." onClick={() => confirm()}>{pending.kind === "SET" ? "Confirm change" : "Remove"}</Btn>
          </>}>
          <div className="stack">
            <div className="grid grid--2">
              <div><div className="eyebrow">Curriculum</div><div className="b700">{pending.curriculum}</div></div>
              <div><div className="eyebrow">Applies to</div><div>{scopeWord(pending.session, pending.semester)}</div></div>
              <div><div className="eyebrow">Current</div><div className="tnum b600">{pending.current != null ? `${pending.current} CU` : "—"}</div></div>
              <div><div className="eyebrow">New</div><div className="tnum b600">{pending.kind === "SET" ? `${pending.next} CU` : "The wider rule applies again"}</div></div>
            </div>
            <Field id="rs-reason" label="Reason" required hint="Ten characters or more; kept with the change">
              <input id="rs-reason" className="ctl" value={reason} maxLength={2000} autoFocus onChange={(e) => setReason(e.target.value)} placeholder="e.g. Senate approved a higher minimum load from this session" />
            </Field>
            <div className="sub2">Registrations already made are not changed. The next submission, add or drop reads the new minimum.</div>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
