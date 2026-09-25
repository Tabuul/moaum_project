"use client";

/** The student statistics screen (V257): the filter bar, the five figures as doors, the payment and registration
 *  donuts, grouped bars by faculty, department and programme, the tables behind them, and the quick actions —
 *  every number counted on the server from the same rows the detail list pages. Clicking a figure, an arc, a bar
 *  or a row opens the students behind it with every filter carried forward. */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { Donut, GroupBars, VZ, vzNum, type LegendKey } from "@/components/proto/vz";
import { DEGREE_WORD, SEMESTER_WORD, detailHref, statQuery, type StatCounts, type StatFilters, type StatSummary, type Which } from "@/lib/stats";

const KEYS: LegendKey[] = [{ l: "Total", c: VZ.axis }, { l: "Paid", c: VZ.s3 }, { l: "Registered", c: VZ.s1 }, { l: "Paid not registered", c: VZ.s4 }, { l: "Not paid", c: VZ.crit }];
const naira = (n: number | undefined) => (n == null ? "—" : "₦" + Number(n).toLocaleString("en-NG", { maximumFractionDigits: 0 }));
const pct = (n: number, of: number) => (of ? `${Math.round((100 * n) / of)}%` : "—");

/** the five figures as tiles that open their rows */
export function StatTiles({ t, f, compact }: { t: StatCounts; f: StatFilters; compact?: boolean }) {
  const tiles: [string, Which, number, string | null, string][] = [
    ["Total students", "ALL", t.total, null, "In study within the scope"],
    ["School fees paid", "PAID", t.paid, t.paid ? "var(--green-ink)" : null, pct(t.paid, t.total) + " of students"],
    ["Course registered", "REGISTERED", t.registered, t.registered ? "var(--chrome)" : null, pct(t.registered, t.total) + " of students"],
    ["Paid not registered", "PAID_NOT_REGISTERED", t.paid_not_registered, t.paid_not_registered ? "var(--amber-ink)" : null, "Paid, yet to register"],
    ["Not paid", "NOT_PAID", t.not_paid, t.not_paid ? "var(--red-ink)" : null, t.no_charge ? `${vzNum(t.no_charge)} with no charge stated` : "Expected to pay"],
  ];
  return (
    <div className={`grid ${compact ? "grid--5" : "grid--5"}`}>
      {tiles.map(([label, which, v, colour, caption]) => (
        <Link key={which} href={detailHref(f, which)} className="tile stat-tile" title={`Open the ${label.toLowerCase()}`}>
          <div className="eyebrow">{label}</div>
          <div className="n" style={colour ? { color: colour } : undefined}>{vzNum(v)}</div>
          <div className="c">{caption}</div>
        </Link>
      ))}
    </div>
  );
}

export function StudentStats({ data, filters, basePath, title }: { data: StatSummary; filters: StatFilters; basePath: string; title?: string }) {
  const queryNav = useQueryNav();
  const f: StatFilters = { ...filters, session: data.session, semester: data.semester == null ? "" : String(data.semester) };
  const t = data.totals;
  const money = data.scope.money;
  const opts = data.options;
  const faculties = [...new Map(opts.programmes.map((p) => [p.faculty_code, p.faculty])).entries()].sort((a, b) => a[1].localeCompare(b[1]));
  const depts = [...new Map(opts.programmes.filter((p) => !f.fac || p.faculty_code === f.fac).map((p) => [p.dept_code, p.department])).entries()].sort((a, b) => a[1].localeCompare(b[1]));
  const progs = opts.programmes.filter((p) => (!f.fac || p.faculty_code === f.fac) && (!f.dept || p.dept_code === f.dept));
  const scopeWords = [data.scope.label, data.session, SEMESTER_WORD(data.semester),
    f.fac ? faculties.find((x) => x[0] === f.fac)?.[1] : null, f.dept ? depts.find((x) => x[0] === f.dept)?.[1] : null,
    f.prog ? opts.programmes.find((x) => x.programme_code === f.prog)?.programme : null, f.level ? `${f.level} Level` : null,
    f.status ? f.status.charAt(0) + f.status.slice(1).toLowerCase() : null, f.degree ? DEGREE_WORD[f.degree] : null].filter(Boolean).join(" · ");
  const open = data.window.find((w) => w.state === "OPEN");

  function go(next: Partial<StatFilters>) {
    const n = { ...f, ...next };
    if (next.fac !== undefined) { n.dept = ""; n.prog = ""; }
    if (next.dept !== undefined) { n.prog = ""; }
    queryNav(`${basePath}?${statQuery(n)}`);
  }
  const counts = (c: StatCounts) => [c.total, c.paid, c.registered, c.paid_not_registered, c.not_paid];
  const showFac = data.scope.kind !== "FACULTY" && data.scope.kind !== "DEPARTMENT" && !f.fac;
  const showDept = data.scope.kind !== "DEPARTMENT" && !f.dept;

  const table = (rows: (StatCounts & { key: string; label: string; sub?: string; next: Partial<StatFilters> })[], what: string) => (
    rows.length ? (
      <DTable pageSize={0} cols={["S/N|num", what, "Total|num", "Paid|num", "Registered|num", "Paid not registered|num", "Not paid|num", ...(money ? ["Outstanding|num"] : []), "|num"]}
        rows={rows.map((r, i) => [
          <span key="sn" className="tnum sub2">{i + 1}</span>,
          <button key="l" type="button" className="lnk b600" style={{ background: "none", border: 0, padding: 0, font: "inherit", cursor: "pointer", textAlign: "left" }} onClick={() => go(r.next)} title={`Narrow to ${r.label}`}>{r.label}{r.sub ? <div className="sub2" style={{ fontWeight: 400 }}>{r.sub}</div> : null}</button>,
          <Link key="t" className="lnk tnum" href={detailHref(f, "ALL", r.next)}>{vzNum(r.total)}</Link>,
          <Link key="p" className="lnk tnum ink-green" href={detailHref(f, "PAID", r.next)}>{vzNum(r.paid)}</Link>,
          <Link key="r" className="lnk tnum" href={detailHref(f, "REGISTERED", r.next)}>{vzNum(r.registered)}</Link>,
          <Link key="pn" className={`lnk tnum${r.paid_not_registered ? " ink-amber" : ""}`} href={detailHref(f, "PAID_NOT_REGISTERED", r.next)}>{vzNum(r.paid_not_registered)}</Link>,
          <Link key="np" className={`lnk tnum${r.not_paid ? " ink-red b600" : ""}`} href={detailHref(f, "NOT_PAID", r.next)}>{vzNum(r.not_paid)}</Link>,
          ...(money ? [<span key="o" className="tnum">{naira(r.outstanding)}</span>] : []),
          <LinkBtn key="a" href={detailHref(f, "ALL", r.next)} size="sm">Students</LinkBtn>,
        ])} texts={rows.map((r) => `${r.label} ${r.sub ?? ""}`)} />
    ) : <PBody><div className="sub2">No students match the selected academic session, semester and filters.</div></PBody>
  );
  const facRows = data.byFaculty.map((x) => ({ ...x, key: x.faculty_code, label: x.faculty, next: { fac: x.faculty_code } as Partial<StatFilters> }));
  const deptRows = data.byDepartment.map((x) => ({ ...x, key: x.dept_code, label: x.department, sub: showFac ? x.faculty : undefined, next: { fac: x.faculty_code, dept: x.dept_code } as Partial<StatFilters> }));
  const progRows = data.byProgramme.map((x) => ({ ...x, key: x.programme_code, label: x.programme, sub: showDept ? x.department : undefined, next: { fac: x.faculty_code, dept: x.dept_code, prog: x.programme_code } as Partial<StatFilters> }));
  const degRows = data.byDegreeType.map((x) => ({ ...x, key: x.degree_type, label: DEGREE_WORD[x.degree_type] ?? x.degree_type, next: { degree: x.degree_type } as Partial<StatFilters> }));

  return (
    <>
      <PageHead title={title ?? "Student Statistics"} description={`${scopeWords}. Every figure is counted from the register as it stands; click a figure, an arc, a bar or a row to open the students behind it.`}
        actions={<><LinkBtn kind="primary" href={detailHref(f, "PAID_NOT_REGISTERED")}>Paid Not Registered</LinkBtn><LinkBtn href={detailHref(f, "NOT_PAID")}>Not Paid</LinkBtn><LinkBtn href={detailHref(f, "ALL")}>All Students</LinkBtn></>} />

      <div className="scope">
        <div className="scope__f"><Field id="st-session" label="Academic session">
          <select id="st-session" className="ctl" value={f.session} onChange={(e) => go({ session: e.target.value, semester: "" })}>
            {(opts.sessions.includes(f.session) ? opts.sessions : [f.session, ...opts.sessions]).map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="st-sem" label="Semester">
          <select id="st-sem" className="ctl" value={f.semester} onChange={(e) => go({ semester: e.target.value })}>
            <option value="">Whole session</option>
            {(opts.semesters.length ? opts.semesters : [1, 2]).map((n) => <option key={n} value={String(n)}>{SEMESTER_WORD(n)}</option>)}
          </select>
        </Field></div>
        {data.scope.kind === "FACULTY" || data.scope.kind === "DEPARTMENT" ? null : (
          <div className="scope__f"><Field id="st-fac" label={data.scope.kind === "COLLEGE" ? "Faculty / School" : "Faculty"}>
            <select id="st-fac" className="ctl" value={f.fac} onChange={(e) => go({ fac: e.target.value })}>
              <option value="">All</option>{faculties.map(([c, n]) => <option key={c} value={c}>{n}</option>)}
            </select>
          </Field></div>
        )}
        {data.scope.kind === "DEPARTMENT" ? null : (
          <div className="scope__f"><Field id="st-dept" label="Department">
            <select id="st-dept" className="ctl" value={f.dept} onChange={(e) => go({ dept: e.target.value })}>
              <option value="">All</option>{depts.map(([c, n]) => <option key={c} value={c}>{n}</option>)}
            </select>
          </Field></div>
        )}
        <div className="scope__f"><Field id="st-prog" label="Programme">
          <select id="st-prog" className="ctl" value={f.prog} onChange={(e) => go({ prog: e.target.value })}>
            <option value="">All</option>{progs.map((p) => <option key={p.programme_code} value={p.programme_code}>{p.programme}</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="st-level" label="Level">
          <select id="st-level" className="ctl" value={f.level} onChange={(e) => go({ level: e.target.value })}>
            <option value="">All</option>{opts.levels.map((l) => <option key={l} value={String(l)}>{l} Level</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="st-status" label="Student status">
          <select id="st-status" className="ctl" value={f.status} onChange={(e) => go({ status: e.target.value })}>
            <option value="">In study (active, probation, admitted)</option>{opts.statuses.map((s) => <option key={s} value={s}>{s.charAt(0) + s.slice(1).toLowerCase()}</option>)}
          </select>
        </Field></div>
        {opts.degreeTypes.length ? (
          <div className="scope__f"><Field id="st-degree" label="Degree type">
            <select id="st-degree" className="ctl" value={f.degree} onChange={(e) => go({ degree: e.target.value })}>
              <option value="">All</option>{opts.degreeTypes.map((d) => <option key={d} value={d}>{DEGREE_WORD[d] ?? d}</option>)}
            </select>
          </Field></div>
        ) : null}
      </div>

      <StatTiles t={t} f={f} />

      {t.total === 0 ? (
        <Note kind="info" title="No students found">No students match the selected academic session, semester and filters.</Note>
      ) : (
        <>
          <div className="grid grid--2">
            <Panel title="Payment status" right={open ? `${SEMESTER_WORD(open.number)} open${open.registration_closes ? ` · registration closes ${new Date(open.registration_closes).toLocaleDateString("en-GB", { day: "numeric", month: "short" })}` : ""}` : SEMESTER_WORD(data.semester)}>
              <PBody>
                <Donut capLabel="Students" capValue={vzNum(t.total)} onPick={(i) => queryNav(detailHref(f, i.l === "Paid" ? "PAID" : i.l === "Not paid" ? "NOT_PAID" : "NO_CHARGE"))}
                  items={[{ l: "Paid", v: t.paid, c: VZ.s3 }, { l: "Not paid", v: t.not_paid, c: VZ.crit }, ...(t.no_charge ? [{ l: "No charge stated", v: t.no_charge, c: VZ.axis }] : [])]} />
                <div className="sub2 mt-2">Paid means the charge for the period is covered in full by confirmed school-fee payments; a student with no fee row for their level and programme is counted apart, not as unpaid.</div>
              </PBody>
            </Panel>
            <Panel title="Registration status" right={`${pct(t.registered, t.total)} registered`}>
              <PBody>
                <Donut capLabel="Students" capValue={vzNum(t.total)} onPick={(i) => queryNav(detailHref(f, i.l === "Registered" ? "REGISTERED" : i.l === "Paid not registered" ? "PAID_NOT_REGISTERED" : i.l === "Not paid" ? "NOT_PAID" : "NOT_REGISTERED"))}
                  items={[{ l: "Registered", v: t.registered, c: VZ.s1 }, { l: "Paid not registered", v: t.paid_not_registered, c: VZ.s4 }, { l: "Not paid", v: Math.max(0, t.total - t.registered - t.paid_not_registered), c: VZ.crit }]} />
                <div className="sub2 mt-2">Registered means a course registration submitted, approved or locked for the period on the student&rsquo;s own register: the University form, the Postgraduate School&rsquo;s form or the College&rsquo;s enrolment.</div>
              </PBody>
            </Panel>
          </div>

          {showFac && data.byFaculty.length > 1 ? (
            <Panel title={data.scope.kind === "COLLEGE" ? "Students by faculty / school" : "Students by faculty"} right="Click a faculty to narrow every figure to it">
              <PBody><GroupBars keys={KEYS} rows={data.byFaculty.map((x) => ({ l: x.faculty, v: counts(x), key: x.faculty_code }))} onPick={(_, i) => go({ fac: data.byFaculty[i].faculty_code })} /></PBody>
            </Panel>
          ) : null}
          {showDept && data.byDepartment.length > 1 ? (
            <Panel title="Students by department" right="Click a department to narrow every figure to it">
              <PBody><GroupBars keys={KEYS} rows={data.byDepartment.map((x) => ({ l: x.department, v: counts(x), key: x.dept_code }))} onPick={(_, i) => go({ fac: data.byDepartment[i].faculty_code, dept: data.byDepartment[i].dept_code })} /></PBody>
            </Panel>
          ) : null}
          {data.byProgramme.length > 1 ? (
            <Panel title="Students by programme" right="Click a programme to narrow every figure to it">
              <PBody><GroupBars keys={KEYS} rows={data.byProgramme.map((x) => ({ l: x.programme, v: counts(x), key: x.programme_code }))} onPick={(_, i) => go({ fac: data.byProgramme[i].faculty_code, dept: data.byProgramme[i].dept_code, prog: data.byProgramme[i].programme_code })} /></PBody>
            </Panel>
          ) : null}
          {data.byDegreeType.length ? (
            <Panel title="Postgraduates by degree type" right="Click a degree type to narrow every figure to it">
              <PBody><GroupBars keys={KEYS} rows={data.byDegreeType.map((x) => ({ l: DEGREE_WORD[x.degree_type] ?? x.degree_type, v: counts(x), key: x.degree_type }))} onPick={(_, i) => go({ degree: data.byDegreeType[i].degree_type })} /></PBody>
            </Panel>
          ) : null}

          {showFac ? <Panel title="By faculty" right={`${data.byFaculty.length} facult${data.byFaculty.length === 1 ? "y" : "ies"}`}>{table(facRows, "Faculty")}</Panel> : null}
          {showDept ? <Panel title="By department" right={`${data.byDepartment.length} department${data.byDepartment.length === 1 ? "" : "s"}`}>{table(deptRows, "Department")}</Panel> : null}
          <Panel title="By programme" right={`${data.byProgramme.length} programme${data.byProgramme.length === 1 ? "" : "s"}`}>{table(progRows, "Programme")}</Panel>
          {data.byDegreeType.length ? <Panel title="By degree type" right="Postgraduates">{table(degRows, "Degree type")}</Panel> : null}

          <Panel title="Quick actions" right={money ? `Payable ${naira(t.payable)} · paid ${naira(t.paid_amount)} · outstanding ${naira(t.outstanding)}` : scopeWords}>
            <PBody>
              <div className="row">
                <LinkBtn kind="primary" href={detailHref(f, "PAID")}>View Paid Students</LinkBtn>
                <LinkBtn kind="urgent" href={detailHref(f, "NOT_PAID")}>View Unpaid Students</LinkBtn>
                <LinkBtn kind="primary" href={detailHref(f, "PAID_NOT_REGISTERED")}>View Paid Not Registered</LinkBtn>
                <LinkBtn href={detailHref(f, "REGISTERED")}>View Registered Students</LinkBtn>
                <LinkBtn href={detailHref(f, "ALL")}>Export Report</LinkBtn>
              </div>
              <div className="sub2 mt-2">The detail list carries these filters, searches on the server, pages the rows, and downloads them as a branded Excel workbook or PDF with S/N first and names A–Z.</div>
            </PBody>
          </Panel>
        </>
      )}
      {t.total > 0 && !open && data.semester != null ? <div className="sub2"><Pil kind="grey">{SEMESTER_WORD(data.semester)} is not open</Pil> The figures are for the period chosen; registration for it may be closed or not yet open.</div> : null}
    </>
  );
}
