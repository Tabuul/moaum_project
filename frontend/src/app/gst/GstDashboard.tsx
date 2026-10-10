"use client";
/** The GST and EPS office dashboards (V314): the figures in all and by level, faculty, department and programme, the payment and
 *  result shares, the quick questions, the courses — every number counted in the database from the one population, scoped by
 *  the filters in the address so a view is a link. The GST office sees General Studies; the EPS office sees Entrepreneurship
 *  Studies, whose entitlement is the GST payment. Click a bar to drill from faculty to department to programme to the students.
 *  V366: the figures are of the students a GST/EPS course concerns — the programme's offering at their level, a carryover — and
 *  the rest are counted as not applicable, never as unpaid. */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { Donut, GroupBars, HBars, VZ } from "@/components/proto/vz";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notifyProblem } from "@/components/proto/Toast";
import { OFFICE_WORD, QUICK, STAGE_WORD, dayOf, gstQuery, naira, num, pct, type GstDashboardData, type GstFilters, type GstGroup } from "@/lib/gst";
import { EXAM_WORD, whenAt, type CbtSummary } from "@/lib/cbt";
import { GstGapsNote } from "@/components/gst/GstGapsNote";

const SEM = (n: number | string | null | undefined) => (n == null || n === "" ? "Whole session" : n === 1 || n === "1" ? "First semester" : n === 2 || n === "2" ? "Second semester" : "Third semester");

export function GstDashboard({ data, filters, base, actingOffice, cbt }: { data: GstDashboardData; filters: GstFilters; base: string; actingOffice: string | null; cbt?: CbtSummary | null }) {
  const go = useQueryNav();
  const [busy, setBusy] = useState(false);
  const o = data.office;
  const eps = o === "EPS";
  const word = eps ? "EPS" : "GST";
  const f: GstFilters = { ...filters, session: data.session, semester: data.semester == null ? "" : String(data.semester) };
  const withFilter = (patch: GstFilters): string => {
    const n: GstFilters = { ...f, ...patch };
    if ("fac" in patch) { delete n.dept; delete n.prog; }
    if ("dept" in patch) delete n.prog;
    for (const k of Object.keys(n) as (keyof GstFilters)[]) if (!n[k]) delete n[k];
    return `${base}/dashboard?${gstQuery(n)}`;
  };
  const t = data.totals;
  const r = data.results;
  const rules = data.fee.rules;
  const general = rules.find((x) => !x.level && !x.entry_mode && !x.faculty_code && !x.programme_code) ?? rules[0] ?? null;
  const filtered = (["fac", "dept", "prog", "level", "sex", "status", "course", "payment", "registration"] as const).some((k) => f[k]);
  const opts = data.options;
  const departments = opts.departments.filter((d) => !f.fac || d.faculty_code === f.fac);
  const programmes = opts.programmes.filter((p) => !f.dept || p.dept_code === f.dept);
  const facultyOf = (code: string | undefined) => opts.faculties.find((x) => x.code === code)?.name ?? code ?? "";
  const scopeWords = [OFFICE_WORD[o], data.session, SEM(data.semester), f.fac ? facultyOf(f.fac) : null, f.dept ? departments.find((d) => d.code === f.dept)?.name ?? f.dept : null,
    f.prog ? programmes.find((p) => p.code === f.prog)?.name ?? f.prog : null, f.level ? `${f.level} Level` : null, f.sex ? (f.sex === "F" ? "Female" : "Male") : null,
    f.payment ? `Payment: ${f.payment.replace("_", " ").toLowerCase()}` : null, f.registration ? `${word} ${f.registration.replace("_", " ").toLowerCase()}` : null, f.course ? `Course ${f.course}` : null]
    .filter(Boolean).join(" · ");

  /* the drill-down: faculties, then the departments of one, then the programmes of one */
  const level = f.dept ? "programme" : f.fac ? "department" : "faculty";
  const groups: GstGroup[] = level === "programme" ? data.byProgramme : level === "department" ? data.byDepartment : data.byFaculty;
  const nameOf = (g: GstGroup) => (level === "programme" ? g.programme : level === "department" ? g.department : g.faculty) ?? "";
  const codeOf = (g: GstGroup) => (level === "programme" ? g.programme_code : level === "department" ? g.dept_code : g.faculty_code) ?? "";
  const keyOf = (): "prog" | "dept" | "fac" => (level === "programme" ? "prog" : level === "department" ? "dept" : "fac");
  const keys = [{ l: "Students", c: VZ.axis }, { l: eps ? "Entitled (GST paid)" : "GST paid", c: VZ.s3 }, { l: `${word} registered`, c: VZ.s1 }];
  const rows = groups.map((g) => ({ l: nameOf(g), v: [Number(g.total), Number(g.paid), Number(g.registered)], key: codeOf(g) }));

  const HEAD = [`S/N`, level === "programme" ? "Programme" : level === "department" ? "Department" : "Faculty", "Students", "Eligible", "Carryover", "Not applicable", "GST paid", "GST not paid", `${word} registered`, `${word} not registered`, "Completed", "Paid, not registered", "Male", "Female", ...(eps ? [] : ["Revenue (₦)", "Outstanding (₦)"])];
  const body = () => groups.map((g, i) => [i + 1, nameOf(g), Number(g.total), Number(g.required), Number(g.carryover ?? 0), Number(g.not_applicable ?? 0), Number(g.paid), Number(g.unpaid), Number(g.registered), Number(g.not_registered), Number(g.completed ?? 0), Number(g.paid_not_registered), Number(g.male), Number(g.female), ...(eps ? [] : [Number(g.revenue), Number(g.outstanding)])]);
  const sub = `${scopeWords}`;
  const exportAs = async (kind: "xlsx" | "pdf") => {
    setBusy(true);
    try {
      const title = `${word} ${level === "programme" ? "Programme" : level === "department" ? "Department" : "Faculty"} Summary`;
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, HEAD, body(), { sheetName: "Summary", serial: docSerial(word === "EPS" ? "EPS" : "GST"), sub }), `${word.toLowerCase()}-${level}-summary-${data.session.replace("/", "-")}.xlsx`);
      else brandedPrint(title, sub, HEAD, body());
    } catch (e) { notifyProblem({ status: 500, title: "The export could not be built", detail: e instanceof Error ? e.message : String(e) }); }
    finally { setBusy(false); }
  };
  const studentsHref = (extra: GstFilters = {}) => `${base}/students?${gstQuery({ ...f, ...extra })}`;

  const sel = (id: string, label: string, k: keyof GstFilters, options: [string, string][], all = "All") => (
    <Field id={id} label={label}>
      <select id={id} className="ctl" value={f[k] ?? ""} onChange={(e) => go(withFilter({ [k]: e.target.value }))}>
        <option value="">{all}</option>
        {options.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
      </select>
    </Field>
  );

  const tiles: [React.ReactNode, React.ReactNode, string | null | undefined, React.ReactNode?][] = eps ? [
    ["TOTAL EPS ELIGIBLE STUDENTS", num(t.required), null, `${num(t.carryover)} through a carryover · ${num(t.population)} undergraduates in view`],
    ["EPS PAID (GST PAYMENT)", num(t.paid), "var(--green-ink)", `${pct(t.paid, t.required)} of the eligible${Number(t.exempt) ? ` · ${num(t.exempt)} with no fee` : ""}`],
    ["EPS UNPAID", num(t.unpaid), t.unpaid ? "var(--red-ink)" : null, `${num(t.pending)} with a reference open · ${num(t.not_stated)} with no fee stated`],
    ["EPS REGISTERED", num(t.registered), null, `${num(t.course_registrations)} course registrations`],
    ["EPS NOT REGISTERED", num(t.not_registered), t.not_registered ? "var(--red-ink)" : null, `${num(t.paid_not_registered)} entitled but not yet registered`],
    ["EPS CARRYOVER STUDENTS", num(t.carryover), t.carryover ? "var(--red-ink)" : null, "A failed EPS course run again this session"],
    ["EPS COMPLETED", num(t.completed), "var(--green-ink)", `${num(t.outstanding_students)} still owing an EPS course`],
    ["NOT APPLICABLE", num(t.not_applicable), null, "No EPS course offered to them at their level, none carried over — never counted unpaid"],
    ["ACTIVE EPS COURSES", num(r.activeCourses), null, `${num(r.totalCourses)} offered ${SEM(data.semester).toLowerCase()}`],
    ["RESULTS", `${num(r.pending)} · ${num(r.submitted)} · ${num(r.published)}`, null, "Pending · submitted · published"],
  ] : [
    ["TOTAL GST ELIGIBLE STUDENTS", num(t.required), null, `${num(t.carryover)} through a carryover · ${num(t.population)} undergraduates in view`],
    ["GST PAID", num(t.paid), "var(--green-ink)", `${pct(t.paid, t.required)} of the eligible${Number(t.exempt) ? ` · ${num(t.exempt)} with no fee` : ""}`],
    ["GST UNPAID", num(t.unpaid), t.unpaid ? "var(--red-ink)" : null, `${num(t.pending)} with a reference open · ${num(t.not_stated)} with no fee stated`],
    ["GST REGISTERED", num(t.registered), null, `${num(t.course_registrations)} course registrations`],
    ["GST NOT REGISTERED", num(t.not_registered), t.not_registered ? "var(--red-ink)" : null, `${num(t.paid_not_registered)} paid but not registered · ${num(t.registered_unpaid)} registered without paying`],
    ["GST CARRYOVER STUDENTS", num(t.carryover), t.carryover ? "var(--red-ink)" : null, "A failed GST course run again this session"],
    ["GST COMPLETED", num(t.completed), "var(--green-ink)", `${num(t.outstanding_students)} still owing a GST course`],
    ["NOT APPLICABLE", num(t.not_applicable), null, "No GST course offered to them at their level, none carried over — never counted unpaid"],
    ["GST REVENUE", naira(t.revenue), null, `${naira(t.outstanding)} outstanding${Number(t.review) ? ` · ${num(t.review)} paid though not required` : ""}`],
    ["RESULTS", `${num(r.pending)} · ${num(r.submitted)} · ${num(r.published)}`, null, "Pending · submitted · published"],
  ];

  return (
    <>
      <PageHead title={`${word} Office dashboard`} description={eps
        ? "Entrepreneurship Studies · the GST payment covers EPS; there is no separate EPS fee."
        : "General Studies · one payment covers GST and EPS."}
        actions={<span className="row row--inline row--tight">
          <label htmlFor="gd-session" className="sub2">Session</label>
          <select id="gd-session" className="ctl" value={data.session} onChange={(e) => go(withFilter({ session: e.target.value }))}>{data.sessions.map((x) => <option key={x.name} value={x.name}>{x.name}</option>)}</select>
          <label htmlFor="gd-sem" className="sub2">Semester</label>
          <select id="gd-sem" className="ctl" value={f.semester ?? ""} onChange={(e) => go(withFilter({ semester: e.target.value }))}><option value="">Whole session</option><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select>
        </span>} />
      {!rules.length ? (
        <Note kind="bad" title={`No GST fee is stated for ${data.session}`}>
          Until the Bursar states it on Fee Setup, nothing is owed and nothing gates {word} registration.
        </Note>
      ) : general ? (
        <Note kind="info" title={`GST fee for ${data.session}: ${naira(general.amount)}${rules.length > 1 ? ` (${rules.length} rules; the most specific prices a student)` : ""}`}>
          Stated by the Bursary{general.stated_by ? ` · ${general.stated_by}` : ""} · effective {dayOf(general.effective_from)}. {data.fee.setting.covers_eps ? "One payment covers GST and EPS." : "EPS is not covered by the GST payment."}
          {data.fee.setting.required_for_gst_eps ? " GST/EPS course registration is held until it is paid." : " Registration is not held on it."}{data.fee.setting.required_for_all ? " The whole registration is held on it." : ""}
        </Note>
      ) : null}
      <GstGapsNote gaps={data.gaps} session={data.session} office={o} may={actingOffice === o.toLowerCase() || actingOffice === "super"} />
      {data.reach && (!data.reach.length || data.reach.some((r) => !r.email && !r.phone)) ? (
        <Note kind="bad" title={data.reach.length ? `${data.reach.filter((r) => !r.email && !r.phone).length} of the ${o} office's ${data.reach.length} holder${data.reach.length === 1 ? "" : "s"} cannot be told of course moves or requests` : `Nobody holds the ${o} office, so nobody is told of course moves or requests`}>
          {data.reach.length
            ? <>No email or phone is on the record of {data.reach.filter((r) => !r.email && !r.phone).map((r) => r.name).join(", ")}. Add contact details on Users &amp; Roles.</>
            : <>Post a holder of the {o} office on Users &amp; Roles, with an email or a phone.</>}
        </Note>
      ) : null}
      {data.waiting && (Number(data.waiting.moves_to_confirm) > 0 || Number(data.waiting.requests_to_answer) > 0) ? (
        <Note kind="info" title="Waiting on the courses page" action={<LinkBtn kind="secondary" href={`${base}/courses`}>Open {o} Courses</LinkBtn>}>
          {[
            Number(data.waiting.moves_to_confirm) > 0 ? `${num(Number(data.waiting.moves_to_confirm))} course move${Number(data.waiting.moves_to_confirm) === 1 ? "" : "s"} someone else made to or from this office, to confirm` : null,
            Number(data.waiting.requests_to_answer) > 0 ? `${num(Number(data.waiting.requests_to_answer))} request${Number(data.waiting.requests_to_answer) === 1 ? "" : "s"} from the ${o === "GST" ? "EPS" : "GST"} office for a course this office holds, to answer` : null,
          ].filter(Boolean).join("; ")}.
        </Note>
      ) : null}
      <Tiles items={tiles} />
      {data.legacy && (Number(data.legacy.legacy_rows) > 0 || t.paid_legacy) ? (
        <Panel title={`OLD-PORTAL GST PAYMENTS · ${data.session}`} right={<LinkBtn kind="ghost" size="sm" href={`/finance/legacy-gst?session=${encodeURIComponent(data.session)}`}>Reconciliation desk</LinkBtn>}>
          <Tiles items={[
            ["PAID IN THIS PORTAL", num(t.paid_current), null, "Gateway, bank or Bursary desk"],
            ["PAID IN THE OLD PORTAL", num(t.paid_legacy), "var(--green-ink)", "Reconciled onto the ledger"],
            ["RECONCILED RECORDS", num(data.legacy.reconciled), null, `of ${num(data.legacy.gst_rows)} old-portal GST rows`],
            ["NOT PAID", num(t.unpaid), t.unpaid ? "var(--red-ink)" : null, "No payment on either portal"],
            ["REQUIRES REVIEW", num(data.legacy.requires_review), data.legacy.requires_review ? "var(--red-ink)" : null, "Waiting on a Finance officer"],
            ["UNMATCHED LEGACY PAYMENTS", num(data.legacy.unmatched), data.legacy.unmatched ? "var(--red-ink)" : null, "No reliable student"],
            ["DUPLICATES", num(data.legacy.duplicates), null, "Entitlement already held"],
            ["VARIANCE", naira(Number(data.legacy.variance)), Number(data.legacy.variance) ? "var(--red-ink)" : "var(--green-ink)", `${naira(Number(data.legacy.reconciled_amount))} of ${naira(Number(data.legacy.legacy_successful_amount))} reconciled`],
          ]} />
        </Panel>
      ) : null}
      {cbt ? (
        <Panel title={`${word} CBT EXAMINATIONS · ${cbt.session}`} right={<span className="row row--inline row--tight"><LinkBtn kind="ghost" size="sm" href={`${base}/question-bank`}>Question bank</LinkBtn><LinkBtn kind="primary" size="sm" href={`${base}/cbt?session=${encodeURIComponent(cbt.session)}`}>CBT examinations</LinkBtn></span>}>
          <Tiles items={[
            ["UPCOMING CBT EXAMS", num(cbt.summary.upcoming), null, `${num(cbt.summary.draft)} in draft`],
            ["ACTIVE CBT EXAMS", num(cbt.summary.open), cbt.summary.open ? "var(--green-ink)" : null, "Open now"],
            ["COMPLETED CBT EXAMS", num(cbt.summary.completed), null, `${num(cbt.summary.exams)} in all`],
            ["STUDENTS WRITING NOW", num(cbt.summary.writing), cbt.summary.writing ? "var(--green-ink)" : null, "Attempts in progress"],
            ["SCORES RECEIVED", num(cbt.summary.scores), null, "Automatic, at submission"],
            ["RESULTS PENDING", num(cbt.summary.results_pending), cbt.summary.results_pending ? "var(--red-ink)" : null, "Completed, not yet published"],
            ["RESULTS PUBLISHED", num(cbt.summary.results_published), "var(--green-ink)", "Visible to students"],
            ["CBT CANDIDATES", num(cbt.summary.candidates), null, "Registered on examined offerings"],
          ]} />
          {cbt.next.length ? (
            <DTable cols={["Reference", "Examination", "Course", "Window", "State|mid", "Writing|num", "|num"]} rows={cbt.next.map((x) => [
              <span key="r" className="tnum">{x.reference}</span>, <b key="t">{x.title}</b>, <span key="c" className="tnum">{x.course_code}</span>,
              <span key="w" className="sub2 tnum">{x.starts_at ? `${whenAt(x.starts_at)} → ${whenAt(x.ends_at)}` : "Not dated"}</span>,
              <Pil key="s" kind={(EXAM_WORD[x.live_state] ?? ["", "grey"])[1]}>{(EXAM_WORD[x.live_state] ?? [x.live_state])[0]}</Pil>,
              <span key="n" className="tnum">{num(x.writing)}</span>,
              <span key="a" className="row row--inline row--tight">{x.live_state === "OPEN" ? <LinkBtn kind="go" size="sm" href={`${base}/cbt/${x.id}/monitor`}>Live monitor</LinkBtn> : null}<LinkBtn kind="ghost" size="sm" href={`${base}/cbt/${x.id}`}>Open</LinkBtn></span>,
            ])} />
          ) : <PBody><div className="sub2">No examination scheduled or open for {cbt.session}.</div></PBody>}
        </Panel>
      ) : null}

      <Panel title="FILTERS" right={<span className="row row--inline row--tight">{filtered ? <Btn kind="ghost" size="sm" onClick={() => go(withFilter({ fac: "", dept: "", prog: "", level: "", sex: "", status: "", course: "", payment: "", registration: "" }))}>Clear the filters</Btn> : null}<LinkBtn kind="primary" size="sm" href={studentsHref()}>Students found: {num(t.total)}</LinkBtn></span>}>
        <PBody>
          <div className="grid grid--4">
            {sel("gd-fac", "Faculty", "fac", opts.faculties.map((x) => [x.code, x.name]))}
            {sel("gd-dept", "Department", "dept", departments.map((x) => [x.code, x.name]))}
            {sel("gd-prog", "Programme", "prog", programmes.map((x) => [x.code, x.name]))}
            {sel("gd-level", "Level", "level", opts.levels.map((x) => [String(x), `${x} Level`]))}
            {sel("gd-sex", "Gender", "sex", [["F", "Female"], ["M", "Male"]])}
            {sel("gd-status", "Student status", "status", [["ACTIVE", "Active"], ["PROBATION", "Probation"], ["ADMITTED", "Admitted"]])}
            {sel("gd-pay", "GST payment", "payment", [["PAID", "Paid"], ["NOT_PAID", "Not paid"], ["PENDING", "Reference open"], ["NOT_STATED", "No fee stated"]])}
            {sel("gd-reg", `${word} registration`, "registration", [["REGISTERED", "Registered"], ["NOT_REGISTERED", "Not registered"]])}
            {sel("gd-course", `${word} course`, "course", opts.courses.map((x) => [x.code, `${x.code} — ${x.title}`]))}
          </div>
          <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
            <span className="sub2">Quick questions:</span>
            {QUICK.map((q) => <Btn key={q.key} kind="secondary" size="sm" onClick={() => go(q.filters.eligibility ? studentsHref(q.filters) : withFilter(q.filters))}>{eps ? q.label.replace("paid GST", "are entitled").replace("have not paid", "are not entitled") : q.label}</Btn>)}
            {!eps && Number(t.review) ? <Btn kind="secondary" size="sm" onClick={() => go(studentsHref({ eligibility: "REVIEW" }))}>Paid, not required ({num(t.review)})</Btn> : null}
            <Btn kind="secondary" size="sm" onClick={() => go(withFilter({ fac: "", dept: "", prog: "" }))}>By faculty</Btn>
          </div>
        </PBody>
      </Panel>

      {t.total === 0 ? <Note kind="info" title={`No ${word} students found for the selected filters`}>Widen the filters, or choose another session{data.semester ? " or the whole session" : ""}.</Note> : null}

      <div className="grid grid--2">
        <Panel title={`${word} REGISTRATION BY LEVEL`} right={<span className="sub2">click a level to filter</span>}>
          <PBody>{data.byLevel.length ? <GroupBars rows={data.byLevel.map((g) => ({ l: `${g.level} Level`, v: [Number(g.total), Number(g.paid), Number(g.registered)], key: String(g.level) }))} keys={keys} onPick={(row) => go(withFilter({ level: row.key ?? "" }))} /> : <div className="sub2">Nothing to show.</div>}</PBody>
        </Panel>
        <Panel title={eps ? "ENTITLEMENT THROUGH GST PAYMENT" : "GST PAYMENT STATUS"} right={<span className="sub2">click a slice to filter</span>}>
          <PBody>
            <Donut items={[{ l: "Paid", v: Number(t.paid), c: VZ.good }, { l: "Not paid", v: Number(t.unpaid) - Number(t.pending), c: VZ.crit }, { l: "Reference open", v: Number(t.pending), c: VZ.warn }, { l: "No fee stated", v: Number(t.not_stated), c: VZ.axis }]}
              capLabel="eligible" capValue={num(t.required)}
              onPick={(item) => go(withFilter({ payment: item.l === "Paid" ? "PAID" : item.l === "Not paid" ? "NOT_PAID" : item.l === "Reference open" ? "PENDING" : "NOT_STATED" }))} />
          </PBody>
        </Panel>
      </div>

      <Panel title={`${word} STUDENTS BY ${level.toUpperCase()}`} right={<span className="row row--inline row--tight">
        {f.fac ? <Btn kind="ghost" size="sm" onClick={() => go(withFilter(f.dept ? { dept: "" } : { fac: "" }))}>Back to {f.dept ? "departments" : "faculties"}</Btn> : null}
        <Btn kind="secondary" size="sm" disabled={busy || !groups.length} onClick={() => void exportAs("xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" disabled={busy || !groups.length} onClick={() => void exportAs("pdf")}>PDF</Btn></span>}>
        <PBody>
          <div className="sub2">{level === "faculty" ? "Click a faculty to see its departments, a department to see its programmes, a programme to see its students." : level === "department" ? `${facultyOf(f.fac)} · click a department for its programmes.` : `${departments.find((d) => d.code === f.dept)?.name ?? f.dept} · click a programme for its students.`}</div>
          {rows.length ? <GroupBars rows={rows} keys={keys} onPick={(row) => { if (level === "programme") go(studentsHref({ prog: row.key })); else go(withFilter({ [keyOf()]: row.key ?? "" })); }} /> : <div className="sub2">Nothing to show for these filters.</div>}
        </PBody>
        {groups.length ? <DTable pageSize={20} cols={["S/N|num", level === "programme" ? "Programme" : level === "department" ? "Department" : "Faculty", "Eligible|num", "Carryover|num", "Not applicable|num", "GST paid|num", "Not paid|num", `${word} registered|num`, "Paid, not registered|num", ...(eps ? [] : ["Revenue|num"]), "Open|mid"]} rows={groups.map((g, i) => [
          <span key="n" className="tnum sub2">{i + 1}</span>, <b key="l">{nameOf(g)}</b>, <span key="t" className="tnum">{num(g.required)}</span>, <span key="c" className="tnum">{num(g.carryover)}</span>,
          <span key="na" className="tnum sub2">{num(g.not_applicable)}</span>, <span key="p" className="tnum ink-green">{num(g.paid)}</span>,
          <span key="u" className="tnum ink-red">{num(g.unpaid)}</span>, <span key="r" className="tnum">{num(g.registered)}</span>, <span key="x" className="tnum">{num(g.paid_not_registered)}</span>,
          ...(eps ? [] : [<span key="v" className="tnum">{naira(g.revenue)}</span>]),
          <LinkBtn key="o" kind="ghost" size="sm" href={level === "programme" ? studentsHref({ prog: codeOf(g) }) : withFilter({ [keyOf()]: codeOf(g) })}>{level === "programme" ? "Students" : "Open"}</LinkBtn>,
        ])} /> : null}
      </Panel>

      <div className="grid grid--2">
        <Panel title={`${word} COURSES · REGISTRATIONS`} right={<LinkBtn kind="ghost" size="sm" href={`${base}/courses?session=${encodeURIComponent(data.session)}`}>Manage courses</LinkBtn>}>
          <PBody>{data.courses.length ? <HBars items={data.courses.map((c) => ({ l: c.course_code, v: Number(c.registered) }))} colour={VZ.s1} onPick={(item) => go(withFilter({ course: item.l }))} /> : <div className="sub2">No {word} course is offered {SEM(data.semester).toLowerCase()} of {data.session}.</div>}</PBody>
        </Panel>
        <Panel title={`${word} RESULTS`} right={<LinkBtn kind="ghost" size="sm" href={`/results/sheets?session=${encodeURIComponent(data.session)}`}>Score sheets</LinkBtn>}>
          <PBody>
            <Donut items={[{ l: "Pending", v: Number(r.pending), c: VZ.warn }, { l: "Submitted", v: Number(r.submitted), c: VZ.s1 }, { l: "Published", v: Number(r.published), c: VZ.good }]} capLabel="courses" capValue={num(r.totalCourses)} />
            <KvGrid cls="grid--3" pairs={[["Gender", `${num(t.male)} male · ${num(t.female)} female`], ["Course registrations", num(r.registrations)], ["Acting office", actingOffice ?? "—"]]} />
          </PBody>
        </Panel>
      </div>

      <Panel title={`${word} COURSES · ${data.session}${data.semester ? ` · ${SEM(data.semester)}` : ""}`}>
        {data.courses.length ? <DTable pageSize={25} cols={["S/N|num", "Course", "Level|mid", "Semester|mid", "Lecturer", "Registered|num", "Entitled|num", "Scores entered|num", "Sheet|mid"]} rows={data.courses.map((c, i) => [
          <span key="n" className="tnum sub2">{i + 1}</span>, <span key="c"><b>{c.course_code}</b><div className="sub2">{c.title} · {c.units} units{c.state === "ENDED" ? " · deactivated" : ""}</div></span>,
          <span key="l" className="tnum">{c.level}</span>, <span key="s" className="tnum">{c.semester}</span>, <span key="t" className="sub2">{c.lecturer ?? "—"}</span>,
          <span key="r" className="tnum">{num(c.registered)}</span>, <span key="e" className="tnum">{num(c.entitled)}</span>, <span key="g" className="tnum">{num(c.graded)}</span>,
          c.sheet_id ? <LinkBtn key="h" kind="ghost" size="sm" href={`/results/sheets/${c.sheet_id}`}>{(STAGE_WORD[c.stage ?? ""] ?? [c.stage ?? "—"])[0]}</LinkBtn> : <Pil key="h" kind="grey">No sheet</Pil>,
        ])} /> : <PBody><div className="sub2">No {word} course is offered for these filters.</div></PBody>}
      </Panel>
    </>
  );
}
