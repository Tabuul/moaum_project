"use client";

/**
 * New appointments (V510): Human Resources makes the employment record that payroll, identity cards, the Head of Department's
 * screen and the staff registers read — one from the form, or many from an Excel upload — each checked by the database first (the
 * person linked by staff number or made, never one already in employment, a grade set up in the category, the date, the department
 * or unit), and the salary grades an appointment names. Nothing is written by a check; the upload appoints the rows that pass and
 * lists the rest with their reasons.
 */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import { readSheet } from "@/lib/jupeb";
import { ALIASES, CATEGORY_LABEL, TEMPLATE_HEAD, type AppointmentsOverview, type RowCheck } from "@/lib/appointments";
import { StaffWithoutEmployment } from "./StaffWithoutEmployment";

const vz = (n: number | null | undefined) => Number(n ?? 0).toLocaleString("en-GB");
const naira = (n: number | string) => `₦${Number(n).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const EMPTY = { staff_no: "", surname: "", given_names: "", sex: "", email: "", phone: "", category: "ACADEMIC", grade: "", step: "", appointment_date: "",
  department: "", unit: "", rank: "", bank_name: "", account_name: "", account_number: "", pension_pin: "" };

async function postJson(url: string, body: unknown, reason?: string): Promise<unknown | null> {
  const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json", ...(reason ? { "X-Reason": reasonHeader(reason) } : {}) }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
  return j;
}

function Checked({ c }: { c: RowCheck }) {
  return (
    <div className="stack" style={{ gap: 4 }}>
      {c.ok ? <Pil kind="ok">{c.action === "LINK" ? `Links ${c.name}` : `Makes ${c.name}`}</Pil> : <Pil kind="bad">Not appointed</Pil>}
      {c.problems.map((p) => <div key={p} className="sub2 ink-red">{p}</div>)}
      {(c.warnings ?? []).map((w) => <div key={w} className="sub2">{w}</div>)}
    </div>
  );
}

export function Appointments({ o, mayAppoint, maySetGrades }: { o: AppointmentsOverview; mayAppoint: boolean; maySetGrades: boolean }) {
  const router = useRouter();
  const [form, setForm] = useState({ ...EMPTY });
  const [formCheck, setFormCheck] = useState<RowCheck | null>(null);
  const [file, setFile] = useState<string | null>(null);
  const [rows, setRows] = useState<Record<string, string | number>[]>([]);
  const [checks, setChecks] = useState<RowCheck[] | null>(null);
  const [result, setResult] = useState<{ appointed: number; skipped: number; rows: { row: string; staff_no: string; name: string; appointed: boolean; problems?: string[] }[] } | null>(null);
  const [g, setG] = useState({ grade: "", step: "1", category: "ACADEMIC", basic: "", housing: "", transport: "", other: "", reason: "" });

  const gradesFor = useMemo(() => o.grades.filter((x) => x.category === form.category), [o.grades, form.category]);
  const gradeNames = Array.from(new Set(gradesFor.map((x) => x.grade)));
  const stepsFor = gradesFor.filter((x) => x.grade === form.grade).map((x) => x.step);
  const set = (k: keyof typeof EMPTY, v: string) => { setForm({ ...form, [k]: v }); setFormCheck(null); };
  const passing = (checks ?? []).filter((c) => c.ok).length;

  async function checkForm() {
    const j = await postJson("/api/bff/api/v1/hr/appointments/check", { rows: [{ ...form, row: "form" }] });
    if (j) setFormCheck((j as RowCheck[])[0]);
  }

  async function appointForm() {
    const j = await postJson("/api/bff/api/v1/hr/appointments", form, `Appointment made: ${form.staff_no.trim()}`);
    if (!j) return;
    notify(`Appointed: ${formCheck?.name ?? form.staff_no}. The employment record is active.`);
    setForm({ ...EMPTY });
    setFormCheck(null);
    router.refresh();
  }

  async function readFile(f: File) {
    setResult(null);
    setChecks(null);
    const read = await readSheet(f, ALIASES);
    setFile(f.name);
    setRows(read);
    if (!read.length) { notify("No appointment found: the sheet needs the template's headings (Staff No, Surname, Category, Grade …)."); return; }
    if (read.length > 2000) { notify("An upload holds at most 2,000 appointments; split the file."); setRows([]); return; }
    const j = await postJson("/api/bff/api/v1/hr/appointments/check", { rows: read.map((r) => ({ ...r, row: String(r.row) })) });
    if (j) setChecks(j as RowCheck[]);
  }

  async function appointUpload() {
    const j = await postJson("/api/bff/api/v1/hr/appointments/upload", { rows: rows.map((r) => ({ ...r, row: String(r.row) })) }, `Appointments uploaded from ${file}`);
    if (!j) return;
    const res = j as NonNullable<typeof result>;
    setResult(res);
    setChecks(null);
    notify(`${vz(res.appointed)} appointed${res.skipped ? `; ${vz(res.skipped)} not (listed with the reasons)` : ""}.`);
    router.refresh();
  }

  async function saveGrade() {
    const r = await fetch("/api/bff/api/v1/hr/grades", {
      method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Salary grade set: ${g.reason.trim()}`) },
      body: JSON.stringify({ grade: g.grade.trim(), step: Number(g.step), category: g.category, basic: Number(g.basic || 0), housing: Number(g.housing || 0),
        transport: Number(g.transport || 0), other: Number(g.other || 0), reason: g.reason.trim() }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    notify(`Saved: ${j.grade}`);
    setG({ ...g, reason: "" });
    router.refresh();
  }

  function template() {
    downloadBlob(buildXlsx(TEMPLATE_HEAD, [
      ["SS/0001", "ADEYEMI", "Example Lecturer", "F", "example.lecturer@example.test", "08000000000", "ACADEMIC", o.grades.find((x) => x.category === "ACADEMIC")?.grade ?? "CONUASS 3", "1", "01/10/2026",
        o.departments[0]?.code ?? "", "", "Lecturer II", "", "", "", ""],
      ["NS/0002", "OKAFOR", "Example Officer", "M", "", "", "NON_ACADEMIC", o.grades.find((x) => x.category === "NON_ACADEMIC")?.grade ?? "CONTISS 7", "1", "01/10/2026",
        "", o.units[0]?.code ?? "", "Administrative Officer", "", "", "", ""],
    ], "Appointments"), "appointments-template.xlsx");
  }

  return (
    <>
      <PageHead title="New appointments" eyebrow="Human resources"
        description="An appointment makes the employment record that payroll, identity cards, the Head of Department's screen and the staff registers read. A person already on the portal is linked by the staff number; a new one is made. Every appointment is checked before anything is written." />

      <Tiles items={[
        ["Active", vz(o.counts.active), null, "Employment records in service"],
        ["Suspended", vz(o.counts.suspended), null, "Not paid while suspended"],
        ["Ended", vz(o.counts.ended), null, "Retired, resigned or disengaged"],
        ["No employment record", vz(o.counts.without_employment), o.counts.without_employment ? "var(--red-ink)" : null, "Staff on the portal without one; appoint them here"],
      ]} />

      {!o.grades.length ? <Note kind="bad" title="No salary grade is set up">An appointment names a grade and step. Set the grades below first.</Note> : null}

      {mayAppoint ? (
        <Panel title="One appointment">
          <PBody>
            <div className="grid grid--3">
              <Field id="ap-no" label="Staff number" required><input id="ap-no" className="ctl" value={form.staff_no} maxLength={30} onChange={(e) => set("staff_no", e.target.value)} /></Field>
              <Field id="ap-sur" label="Surname" hint="Not needed for a person already on the portal"><input id="ap-sur" className="ctl" value={form.surname} maxLength={100} onChange={(e) => set("surname", e.target.value)} /></Field>
              <Field id="ap-given" label="Given names"><input id="ap-given" className="ctl" value={form.given_names} maxLength={150} onChange={(e) => set("given_names", e.target.value)} /></Field>
              <Field id="ap-cat" label="Category" required>
                <select id="ap-cat" className="ctl" value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value, grade: "", step: "" })}>
                  <option value="ACADEMIC">Academic</option><option value="NON_ACADEMIC">Non-academic</option>
                </select>
              </Field>
              <Field id="ap-grade" label="Grade" required>
                <select id="ap-grade" className="ctl" value={form.grade} onChange={(e) => setForm({ ...form, grade: e.target.value, step: "" })}>
                  <option value="">Choose…</option>{gradeNames.map((n) => <option key={n} value={n}>{n}</option>)}
                </select>
              </Field>
              <Field id="ap-step" label="Step" required>
                <select id="ap-step" className="ctl" value={form.step} onChange={(e) => set("step", e.target.value)}>
                  <option value="">Choose…</option>{stepsFor.map((n) => <option key={n} value={String(n)}>{n}</option>)}
                </select>
              </Field>
              <Field id="ap-date" label="Date of appointment" required><input id="ap-date" type="date" className="ctl" value={form.appointment_date} onChange={(e) => set("appointment_date", e.target.value)} /></Field>
              <Field id="ap-dept" label="Department" hint={form.category === "ACADEMIC" ? "Required for an academic appointment" : "Or the unit"}>
                <select id="ap-dept" className="ctl" value={form.department} onChange={(e) => set("department", e.target.value)}>
                  <option value="">—</option>{o.departments.map((d) => <option key={d.code} value={d.code}>{d.name} ({d.code})</option>)}
                </select>
              </Field>
              <Field id="ap-unit" label="Unit">
                <select id="ap-unit" className="ctl" value={form.unit} onChange={(e) => set("unit", e.target.value)}>
                  <option value="">—</option>{o.units.map((u) => <option key={u.code} value={u.code}>{u.name} ({u.code})</option>)}
                </select>
              </Field>
              <Field id="ap-rank" label="Rank"><input id="ap-rank" className="ctl" value={form.rank} maxLength={100} onChange={(e) => set("rank", e.target.value)} placeholder="e.g. Lecturer II" /></Field>
              <Field id="ap-sex" label="Sex">
                <select id="ap-sex" className="ctl" value={form.sex} onChange={(e) => set("sex", e.target.value)}><option value="">—</option><option value="F">Female</option><option value="M">Male</option></select>
              </Field>
              <Field id="ap-email" label="E-mail"><input id="ap-email" type="email" className="ctl" value={form.email} maxLength={200} onChange={(e) => set("email", e.target.value)} /></Field>
              <Field id="ap-phone" label="Phone"><input id="ap-phone" className="ctl" value={form.phone} maxLength={20} onChange={(e) => set("phone", e.target.value)} /></Field>
              <Field id="ap-bank" label="Bank"><input id="ap-bank" className="ctl" value={form.bank_name} maxLength={100} onChange={(e) => set("bank_name", e.target.value)} /></Field>
              <Field id="ap-acname" label="Account name"><input id="ap-acname" className="ctl" value={form.account_name} maxLength={150} onChange={(e) => set("account_name", e.target.value)} /></Field>
              <Field id="ap-acno" label="Account number" hint="Only the last four digits are kept"><input id="ap-acno" className="ctl" value={form.account_number} maxLength={20} inputMode="numeric" onChange={(e) => set("account_number", e.target.value)} /></Field>
              <Field id="ap-pin" label="Pension PIN"><input id="ap-pin" className="ctl" value={form.pension_pin} maxLength={20} onChange={(e) => set("pension_pin", e.target.value)} /></Field>
            </div>
            {formCheck ? <div className="mt-2"><Checked c={formCheck} /></div> : null}
            <div className="row row--tight mt-2">
              <Btn kind="secondary" disabled={!form.staff_no.trim()} busyLabel="Checking…" onClick={() => checkForm()}>Check</Btn>
              <Btn kind="primary" disabled={!formCheck?.ok} busyLabel="Appointing…" onClick={() => appointForm()}>Appoint</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}

      {mayAppoint ? (
        <Panel title="Upload appointments" right={<Btn kind="ghost" size="sm" onClick={() => template()}>Template</Btn>}>
          <PBody>
            <div className="row row--tight" style={{ flexWrap: "wrap" }}>
              <input type="file" accept=".xlsx,.csv" aria-label="Appointments file" onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = ""; }} />
              {file ? <span className="sub2">{file} · {vz(rows.length)} row{rows.length === 1 ? "" : "s"}</span> : <span className="sub2">An .xlsx or .csv with the template&rsquo;s headings; up to 2,000 rows.</span>}
            </div>
            {checks ? (
              <>
                <div className="row row--between mt-2" style={{ flexWrap: "wrap", gap: 8 }}>
                  <span><b>{vz(passing)}</b> of {vz(checks.length)} pass{checks.length - passing ? <> · <span className="ink-red">{vz(checks.length - passing)} not, each with its reason</span></> : null}</span>
                  <Btn kind="primary" disabled={!passing} busyLabel="Appointing…" onClick={() => appointUpload()}>Appoint the {vz(passing)} that pass</Btn>
                </div>
                <DTable pageSize={25} cols={["Row|num", "Staff No.", "Name", "Category", "Grade|mid", "Date|mid", "Department / unit", "Check"]}
                  rows={checks.map((c) => [
                    <span key="r" className="tnum sub2">{c.row}</span>, <span key="n" className="tnum">{c.staff_no}</span>, <span key="m">{c.name}</span>,
                    <span key="c">{CATEGORY_LABEL[c.category] ?? c.category}</span>, <span key="g" className="tnum">{c.grade}{c.step ? ` / ${c.step}` : ""}</span>,
                    <span key="d" className="tnum">{day(c.appointment_date)}</span>, <span key="p">{c.department ?? c.unit ?? "—"}</span>, <Checked key="k" c={c} />,
                  ])} />
              </>
            ) : null}
            {result ? (
              <div className="mt-2">
                <Note kind={result.skipped ? "info" : "ok"} title={`${vz(result.appointed)} appointed${result.skipped ? `, ${vz(result.skipped)} not` : ""}`}>
                  {result.rows.filter((r) => !r.appointed).map((r) => <div key={r.row} className="sub2">Row {r.row} ({r.staff_no}): {(r.problems ?? []).join(" ")}</div>)}
                </Note>
              </div>
            ) : null}
          </PBody>
        </Panel>
      ) : null}

      {/* V513: the staff on the portal without one, downloaded as the template filled in */}
      <StaffWithoutEmployment />

      <Panel title="Salary grades" right={`${vz(o.grades.length)} grade-step${o.grades.length === 1 ? "" : "s"}`}>
        {o.grades.length ? (
          <DTable pageSize={0} cols={["Grade", "Step|mid", "Category", "Basic|num", "Housing|num", "Transport|num", "Other|num", "Monthly|num", "Staff|num"]}
            rows={o.grades.map((x) => [
              <span key="g" className="b600">{x.grade}</span>, <span key="s" className="tnum">{x.step}</span>, <span key="c">{CATEGORY_LABEL[x.category]}</span>,
              <span key="b" className="tnum">{naira(x.basic)}</span>, <span key="h" className="tnum">{naira(x.housing)}</span>, <span key="t" className="tnum">{naira(x.transport)}</span>,
              <span key="o" className="tnum">{naira(x.other_allowances)}</span>, <span key="m" className="tnum b600">{naira(x.monthly)}</span>, <span key="n" className="tnum">{vz(x.staff)}</span>,
            ])} />
        ) : <PBody><div className="sub2">None set up yet.</div></PBody>}
        {maySetGrades ? (
          <PBody>
            <div className="b600 mb-2">Set a grade and step</div>
            <div className="grid grid--4">
              <Field id="gr-grade" label="Grade" hint="e.g. CONUASS 3"><input id="gr-grade" className="ctl" value={g.grade} maxLength={30} onChange={(e) => setG({ ...g, grade: e.target.value })} /></Field>
              <Field id="gr-step" label="Step"><input id="gr-step" className="ctl" type="number" min={1} max={30} value={g.step} onChange={(e) => setG({ ...g, step: e.target.value })} /></Field>
              <Field id="gr-cat" label="Category"><select id="gr-cat" className="ctl" value={g.category} onChange={(e) => setG({ ...g, category: e.target.value })}><option value="ACADEMIC">Academic</option><option value="NON_ACADEMIC">Non-academic</option></select></Field>
              <Field id="gr-basic" label="Basic (monthly)"><input id="gr-basic" className="ctl" inputMode="decimal" value={g.basic} onChange={(e) => setG({ ...g, basic: e.target.value })} /></Field>
              <Field id="gr-house" label="Housing"><input id="gr-house" className="ctl" inputMode="decimal" value={g.housing} onChange={(e) => setG({ ...g, housing: e.target.value })} /></Field>
              <Field id="gr-trans" label="Transport"><input id="gr-trans" className="ctl" inputMode="decimal" value={g.transport} onChange={(e) => setG({ ...g, transport: e.target.value })} /></Field>
              <Field id="gr-other" label="Other allowances"><input id="gr-other" className="ctl" inputMode="decimal" value={g.other} onChange={(e) => setG({ ...g, other: e.target.value })} /></Field>
              <Field id="gr-reason" label="Reason" required hint="Ten characters or more"><input id="gr-reason" className="ctl" value={g.reason} maxLength={500} onChange={(e) => setG({ ...g, reason: e.target.value })} placeholder="e.g. the 2026 salary table" /></Field>
            </div>
            <div className="mt-2"><Btn kind="primary" disabled={!g.grade.trim() || !g.basic || g.reason.trim().length < 10} busyLabel="Saving…" onClick={() => saveGrade()}>Save the grade</Btn></div>
            <div className="sub2 mt-2">The same grade and step saved again takes the new amounts. A grade held by staff keeps its category.</div>
          </PBody>
        ) : null}
      </Panel>

      <Panel title="Latest appointments" right={`${vz(o.recent.length)} shown`}>
        {o.recent.length ? (
          <DTable pageSize={0} cols={["Staff No.", "Name", "Category", "Grade|mid", "Appointed|mid", "Department / unit", "Rank", "Status"]}
            rows={o.recent.map((r) => [
              <span key="n" className="tnum">{r.staff_no}</span>, <span key="m">{r.name}</span>, <span key="c">{CATEGORY_LABEL[r.category] ?? r.category}</span>,
              <span key="g" className="tnum">{r.grade} / {r.step}</span>, <span key="d" className="tnum">{day(r.appointment_date)}</span>,
              <span key="p">{r.department ?? r.unit ?? "—"}</span>, <span key="k" className="sub2">{r.present_rank ?? "—"}</span>,
              <Pil key="s" kind={r.status === "ACTIVE" ? "ok" : r.status === "ENDED" ? "grey" : "bad"}>{r.status.charAt(0) + r.status.slice(1).toLowerCase()}</Pil>,
            ])} />
        ) : <PBody><div className="sub2">No employment record yet.</div></PBody>}
      </Panel>
    </>
  );
}
