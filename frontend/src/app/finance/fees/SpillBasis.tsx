"use client";

/** V571: on the Bursary's fee page, who is charged the spillover fee lines — a level above the programme's final level (V088,
 *  the rule in force until the Bursary changes it), or the cohort engine's spillover (SP1, SP2 … and the limit reached, by the
 *  sessions past the programme's length). The change is previewed first — each student who would move, with the session's charges
 *  under each basis — and made with a reason. V580: a session that lacks the spillover lines of the last one that states them has
 *  them copied on their own from here, previewed first. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { spilloverWord } from "@/lib/student-query";
import { COPY_ACTION, copyScope, type CopyLine } from "@/lib/fee-copy";

interface Basis {
  basis: "LEVEL" | "COHORT"; set_at?: string | null; set_by?: string | null; reason?: string | null;
  into_spill: number; out_of_spill: number; spillLines: number;
}
interface Move {
  student_id: string; name: string; number: string | null; programme: string | null; faculty: string | null; level: number | null; spillover_state: string | null;
  by_level: boolean; by_cohort: boolean; by_level_due: number; by_cohort_due: number;
}
/** V576: for the current session and the next, the spillover lines stated and the spillover students with none, by each basis */
interface Ready {
  session: string; lines: number; byLevel?: { students: number; groups: number }; byCohort?: { students: number; groups: number };
  /** V580: the last earlier session that states spillover lines, and how many of them this one does not state */
  copyFrom?: string; toCopy?: number;
}
interface Copied { from: string; to: string; copy: number; kept: number; applied: boolean; lines: CopyLine[] }
interface Preview {
  session: string; students: number; intoSpill: number; outOfSpill: number; dueByLevel: number; dueByCohort: number; nothingStatedByCohort: number; rows: Move[];
}

const count = (n: number) => Number(n).toLocaleString("en-NG");
const naira = (n: number) => `₦${Number(n).toLocaleString("en-NG", { maximumFractionDigits: 2 })}`;
const WORD = { LEVEL: "By level — a level above the programme's final level", COHORT: "By cohort — the sessions past the programme's length (SP1, SP2 …)" };

export function SpillBasis({ session, may, mayFees }: { session: string; may: boolean; mayFees: boolean }) {
  const router = useRouter();
  const [basis, setBasis] = useState<Basis | null>(null);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tick, setTick] = useState(0);
  const [ready, setReady] = useState<Ready[] | null>(null);
  const [copying, setCopying] = useState<Copied | null>(null);

  useEffect(() => {
    let alive = true;
    void fetch("/api/bff/api/v1/finance/spillover-basis", { cache: "no-store" }).then(async (r) => { if (alive && r.ok) setBasis((await r.json()) as Basis); });
    // the readiness is read after the panel (a second or two): it never holds the page
    void fetch("/api/bff/api/v1/finance/spillover-basis/readiness", { cache: "no-store" }).then(async (r) => { if (alive && r.ok) setReady((await r.json()) as Ready[]); });
    return () => { alive = false; };
  }, [tick]);

  if (!basis) return null;
  const other = basis.basis === "LEVEL" ? "COHORT" : "LEVEL";

  async function load(all = false): Promise<Preview | null> {
    const r = await fetch(`/api/bff/api/v1/finance/spillover-basis/preview?session=${encodeURIComponent(session)}${all ? "&all=true" : ""}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The preview could not be read just now." }); return null; }
    return j as Preview;
  }

  async function excel() {
    const p = await load(true);
    if (!p) return;
    const head = ["S/N", "Student", "Number", "Faculty", "Programme", "Level", "Cohort engine", "Spillover lines by level", "Spillover lines by cohort", `Charged ${p.session} by level`, `Charged ${p.session} by cohort`];
    const rows = p.rows.map((m, i) => [i + 1, m.name, m.number ?? "", m.faculty ?? "", m.programme ?? "", m.level ?? "", spilloverWord(m.spillover_state)?.long ?? "",
      m.by_level ? "Yes" : "No", m.by_cohort ? "Yes" : "No", m.by_level_due, m.by_cohort_due]);
    downloadBlob(await brandedXlsx("Spillover Fee Basis", head, rows, { sub: `${p.session}: who moves`, serial: docSerial("SPILL") }), `spillover-fee-basis-${p.session.replace("/", "-")}.xlsx`);
  }

  async function save() {
    setBusy("save");
    setProblem(null);
    const r = await fetch("/api/bff/api/v1/finance/spillover-basis", {
      method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Spillover fee lines charged ${other === "COHORT" ? "by the cohort" : "by the level"}: ${reason.trim()}`) },
      body: JSON.stringify({ basis: other, reason: reason.trim() }),
    });
    const j = await r.json().catch(() => null);
    setBusy(null);
    if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
    notify(`The spillover lines are now charged ${other === "COHORT" ? "by the cohort" : "by the level"}`);
    setPreview(null);
    setReason("");
    setTick((n) => n + 1);
    router.refresh();
  }

  /** V580: the spillover lines of the last session that states them, previewed for a session that lacks them */
  async function lookCopy(r: Ready) {
    setBusy(`look:${r.session}`);
    try {
      const x = await fetch(`/api/bff/api/v1/finance/sessions/${r.session}/schedule/copy-spillover?from=${encodeURIComponent(r.copyFrom ?? "")}`, { cache: "no-store" });
      const j = await x.json().catch(() => null);
      if (!x.ok) { notifyProblem(j ?? { status: x.status, title: "The spillover lines could not be read just now." }); return; }
      setCopying(j as Copied);
    } finally { setBusy(null); }
  }

  async function copySpill() {
    if (!copying) return;
    setBusy("copy");
    try {
      const x = await fetch(`/api/bff/api/v1/finance/sessions/${copying.to}/schedule/copy-spillover`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Spillover fee lines of ${copying.from} copied into ${copying.to}`) },
        body: JSON.stringify({ from: copying.from }),
      });
      const j = await x.json().catch(() => null);
      if (!x.ok) { notifyProblem(j ?? { status: x.status, title: x.statusText }); return; }
      const c = j as Copied;
      notify(`${c.copy.toLocaleString()} spillover line${c.copy === 1 ? "" : "s"} of ${c.from} copied into ${c.to}`);
      setCopying(null);
      setTick((n) => n + 1);
      router.refresh();
    } finally { setBusy(null); }
  }

  const moving = basis.basis === "LEVEL" ? basis.into_spill : basis.out_of_spill;
  return (
    <Panel title="Who is charged the spillover lines" right={<Pil kind={basis.basis === "COHORT" ? "info" : "grey"}>{basis.basis === "COHORT" ? "By cohort" : "By level"}</Pil>}>
      <PBody>
        <div className="stack">
          <div className="sub2">
            {WORD[basis.basis]}{basis.set_at ? ` — since ${new Date(basis.set_at).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" })}${basis.set_by ? `, ${basis.set_by}` : ""}${basis.reason ? `: ${basis.reason}` : ""}` : " (the rule since the spillover lines began)."}
            {" "}{count(basis.spillLines)} spillover line{basis.spillLines === 1 ? "" : "s"} on the schedule.
          </div>
          {ready?.length ? (
            <div className="stack" style={{ gap: 2 }}>
              {ready.map((r) => {
                const now = basis.basis === "COHORT" ? r.byCohort : r.byLevel;
                const other = basis.basis === "COHORT" ? r.byLevel : r.byCohort;
                return (
                  <div key={r.session} className="sub2">
                    <b className="tnum">{r.session}</b>: {count(r.lines)} spillover line{r.lines === 1 ? "" : "s"} stated ·{" "}
                    <span style={now?.students ? { color: "var(--red-ink)" } : undefined}>{count(now?.students ?? 0)} spillover student{now?.students === 1 ? "" : "s"} with no line {basis.basis === "COHORT" ? "by the cohort" : "by the level"}</span>
                    {" "}· {count(other?.students ?? 0)} {basis.basis === "COHORT" ? "by the level" : "by the cohort"}
                    {now?.students || other?.students ? " — state the spillover lines (the /SP column of the approved structure) before charging by that basis" : ""}
                    {r.copyFrom && r.toCopy ? (mayFees
                      ? <> <Btn kind="ghost" size="sm" busy={busy === `look:${r.session}`} onClick={() => void lookCopy(r)}>{`Copy ${count(r.toCopy)} spillover line${r.toCopy === 1 ? "" : "s"} from ${r.copyFrom}`}</Btn></>
                      : <> · {count(r.toCopy)} spillover line{r.toCopy === 1 ? "" : "s"} of {r.copyFrom} not stated here</>) : null}
                  </div>
                );
              })}
            </div>
          ) : null}
          {moving ? (
            <Note kind="info" title={`${count(moving)} current student${moving === 1 ? "" : "s"} would be charged differently ${other === "COHORT" ? "by the cohort" : "by the level"}`}
              action={<Btn kind="secondary" busy={busy === "preview"} onClick={async () => { setBusy("preview"); setPreview(await load()); setBusy(null); }}>Preview the change</Btn>}>
              {other === "COHORT"
                ? "The cohort engine reads these students as spillover by the sessions past their programme's length, but their record's level is not above the final level, so the spillover lines are not charged to them."
                : "These students are charged the spillover lines by the cohort, but their level is not above the programme's final level."}
            </Note>
          ) : (
            <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
              <span className="sub2">Both bases charge the same students: nothing would move.</span>
              {!preview ? <Btn kind="ghost" busy={busy === "preview"} onClick={async () => { setBusy("preview"); setPreview(await load()); setBusy(null); }}>Change the basis</Btn> : null}
            </div>
          )}
          {preview ? (
            <>
              <Tiles cls="grid--4" items={[
                ["Students who move", count(preview.students), null, preview.intoSpill ? `${count(preview.intoSpill)} onto the spillover lines` : `${count(preview.outOfSpill)} off them`],
                [`Charged ${preview.session} now`, naira(basis.basis === "LEVEL" ? preview.dueByLevel : preview.dueByCohort), null, "these students, as charged now"],
                [`Charged ${preview.session} after`, naira(basis.basis === "LEVEL" ? preview.dueByCohort : preview.dueByLevel), null, "these students, after the change"],
                ["Nothing stated after", count(preview.nothingStatedByCohort), preview.nothingStatedByCohort ? "var(--amber-ink)" : null, "no line matches them by the cohort"],
              ]} />
              {preview.rows.length ? <DTable noPrint title={`The first ${count(preview.rows.length)} of ${count(preview.students)}`} pageSize={10}
                cols={["Student", "Programme", "Level|num", "Cohort engine", "Charged now|num", "After|num"]} rows={preview.rows.map((m) => [
                  <span key="n">{m.name}<div className="sub2 tnum">{m.number ?? ""}</div></span>,
                  <span key="p" className="sub2">{m.programme ?? "—"}<div>{m.faculty ?? ""}</div></span>,
                  <span key="l" className="tnum">{m.level ?? "—"}</span>,
                  <span key="s">{spilloverWord(m.spillover_state)?.short ?? "—"}</span>,
                  <span key="a" className="tnum">{naira(basis.basis === "LEVEL" ? m.by_level_due : m.by_cohort_due)}</span>,
                  <span key="b" className="tnum">{naira(basis.basis === "LEVEL" ? m.by_cohort_due : m.by_level_due)}</span>,
                ])} /> : null}
              {preview.rows.length ? <div className="row" style={{ gap: 8 }}><Btn kind="ghost" busyLabel="Preparing Excel..." onClick={excel}>Excel of every student who moves</Btn></div> : null}
              {may ? (
                <div className="stack">
                  <Field id="sb-why" label="Reason (required)" hint="Who decided, and why: it is kept with the setting.">
                    <textarea id="sb-why" className="ctl" rows={2} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)}
                      placeholder="Bursary decision: spillover students charged the spillover lines by their years past the programme's length" />
                  </Field>
                  <div className="row" style={{ gap: 8 }}>
                    <Btn kind="urgent" busy={busy === "save"} disabled={reason.trim().length < 10} onClick={save}>
                      {other === "COHORT" ? "Charge the spillover lines by the cohort" : "Charge the spillover lines by the level"}
                    </Btn>
                    <span className="sub2">Charges, balances and clearance follow at once; the Bursary summaries within five minutes.</span>
                  </div>
                </div>
              ) : <div className="sub2">The Bursar changes the basis.</div>}
            </>
          ) : null}
          {problem ? <ProblemNotice problem={problem} /> : null}
        </div>
      </PBody>
      {copying ? (
        <Modal title={`Copy the spillover lines of ${copying.from} into ${copying.to}`} sub={`${count(copying.copy)} to copy · ${count(copying.kept)} already stated, kept`}
          onClose={() => { if (!busy) setCopying(null); }}
          foot={<><Btn kind="ghost" disabled={!!busy} onClick={() => setCopying(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={!!busy || !copying.copy} busy={busy === "copy"} busyLabel="Copying…" onClick={() => void copySpill()}>
              {`Copy ${count(copying.copy)} line${copying.copy === 1 ? "" : "s"}`}</Btn></>}>
          <div className="sub2">
            Only the spillover lines are copied, with {copying.from}&rsquo;s amounts; a line {copying.to} already states for the same students is kept, never overwritten.
            The spillover students are charged them at once{basis.basis === "COHORT" ? " (by the cohort)" : " (by the level)"}; adjust any amount on the list of charges.
          </div>
          <DTable pageSize={10} cols={["Item", "Applies to", "Amount|num", `In ${copying.to}|num`, ""]} rows={copying.lines.map((l) => [
            <strong key="i">{l.item}</strong>,
            <span key="a" className="sub2">{copyScope(l)}</span>,
            <span key="m" className="tnum">{money(Number(l.amount))}</span>,
            <span key="t" className="tnum sub2">{l.target_amount != null ? money(Number(l.target_amount)) : "—"}</span>,
            <Pil key="p" kind={COPY_ACTION[l.action][1]}>{COPY_ACTION[l.action][0]}</Pil>,
          ])} />
        </Modal>
      ) : null}
    </Panel>
  );
}
