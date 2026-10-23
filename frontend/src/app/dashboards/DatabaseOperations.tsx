import Link from "next/link";
import { api } from "@/lib/api";
import { LinkBtn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { RefreshFigures } from "./RefreshFigures";
import type { ReadinessFigures } from "@/lib/exam-readiness";

interface Home {
  students: { programme_type: string; label: string; current: number; graduated: number; spillover: number; total: number }[];
  readiness: ReadinessFigures | null;
  quality: { kind: string; label: string; area: string; n: number }[];
  reports: { reference: string; kind: string; title: string; scope: string | null; row_count: number | null; generated_by: string | null; generated_at: string }[];
  at: string; refreshing: boolean; scope: string; period: { session: string; semester: number };
}

const vz = (n: number | null | undefined) => Number(n ?? 0).toLocaleString("en-GB");

/**
 * V640: the Database Operator's home — the students by programme type (current, graduated, in spillover) from the one
 * classification, the examination readiness of the current semester, the data quality, the official reports issued, and the quick
 * actions. Every figure is the server's; each opens its students.
 */
export async function DatabaseOperationsDashboard() {
  const home = await api<Home>("/api/v1/dbops/home");
  if (!home.ok) return <ProblemNotice problem={home.problem} />;
  const h = home.data;
  const type = (code: string) => h.students.find((s) => s.programme_type === code);
  const sumOf = (k: "current" | "graduated" | "spillover" | "total") => h.students.reduce((n, s) => n + Number(s[k]), 0);
  const prelim = ["PRELIMINARY", "REMEDIAL", "FOUNDATION", "PRE_DEGREE"].reduce((n, c) => n + Number(type(c)?.current ?? 0), 0);
  const r = h.readiness;
  const ready = (cat: string) => `/reports/exam-readiness?session=${encodeURIComponent(h.period.session)}&sem=${h.period.semester}&cat=${cat}`;
  const dq = (kinds: string[]) => h.quality.filter((q) => kinds.includes(q.kind)).reduce((n, q) => n + Number(q.n), 0);
  return (
    <>
      <Note kind="info" title={`Database Operations · ${h.scope}`}>
        The University&rsquo;s student data as its own engines read it: the classification, central finance and the registration engine. Read {new Date(h.at).toLocaleString("en-GB")}
        {h.refreshing ? " (a newer reading is being worked out)" : ""}. <RefreshFigures />
      </Note>
      <Panel title="Students" right={`${vz(sumOf("total"))} on record`}>
        <Tiles items={[
          ["Current students", vz(sumOf("current")), null, "in study, every programme type", "/student-query?status=CURRENT"],
          ["Undergraduate", vz(type("UNDERGRADUATE")?.current), null, "current", "/student-query?type=UNDERGRADUATE&status=CURRENT"],
          ["Postgraduate", vz(type("POSTGRADUATE")?.current), null, "current", "/student-query?type=POSTGRADUATE&status=CURRENT"],
          ["CCE", vz(type("CCE")?.current), null, "current", "/student-query?type=CCE&status=CURRENT"],
        ]} />
        <Tiles items={[
          ["JUPEB", vz(type("JUPEB")?.current), null, "current", "/student-query?type=JUPEB"],
          ["Preliminary", vz(prelim), null, "current", "/student-query?type=PRELIMINARY"],
          ["Spillover", vz(sumOf("spillover")), null, "SP1, SP2 and beyond", "/student-query?spillover=ANY"],
          ["Graduated", vz(sumOf("graduated")), null, "every programme type", "/student-query?status=GRADUATED"],
        ]} />
      </Panel>
      <Panel title="Examination readiness" right={`${h.period.session} · ${h.period.semester === 1 ? "First" : h.period.semester === 2 ? "Second" : "Third"} Semester`}>
        <Tiles items={[
          ["Paid + registered", vz(r?.paid_registered), "var(--green-ink)", `of ${vz(r?.total)} eligible`, ready("PAID_REGISTERED")],
          ["Paid + not registered", vz(r?.paid_not_registered), "var(--amber-ink)", "registration missing", ready("PAID_NOT_REGISTERED")],
          ["Not paid", vz(r?.not_paid), "var(--red-ink)", `${vz(r?.not_paid_registered)} of them registered`, ready("NOT_PAID")],
          ["Registration exceptions", vz(r?.exceptions), null, "draft, returned, empty, awaiting approval", ready("EXCEPTIONS")],
        ]} />
      </Panel>
      <Panel title="Data quality" right={<LinkBtn kind="ghost" href="/dbops/data-quality">View data quality</LinkBtn>}>
        <Tiles items={[
          ["Unclassified", vz(dq(["UNCLASSIFIED"])), null, "no programme type", "/dbops/data-quality?kind=UNCLASSIFIED"],
          ["Classification and status errors", vz(dq(["CONFLICTING_STATUS", "GRADUATED_STILL_ACTIVE", "BEYOND_MAXIMUM_PERIOD"])), null, "conflicting statuses, beyond the maximum", "/dbops/data-quality"],
          ["Academic data exceptions", vz(dq(["INVALID_PROGRAMME", "MISSING_FACULTY_DEPARTMENT", "MISSING_ENTRY_SESSION", "INVALID_LEVEL", "LEVEL_INCONSISTENT", "MISSING_MATRIC", "DUPLICATE_MATRIC", "DUPLICATE_JAMB"])), null, "structure, sessions, levels, numbers", "/dbops/data-quality"],
          ["Payment and registration", vz(dq(["PAID_NOT_REGISTERED", "REGISTERED_NOT_PAID"])), null, "paid not registered, registered not paid", "/dbops/data-quality?kind=REGISTERED_NOT_PAID"],
        ]} />
      </Panel>
      <Panel title="Quick actions">
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
            <LinkBtn kind="primary" href="/student-query">QUERY STUDENTS</LinkBtn>
            <LinkBtn kind="secondary" href="/dbops/query?preset=payments">GENERATE PAYMENT REPORT</LinkBtn>
            <LinkBtn kind="secondary" href="/dbops/query?preset=registrations">GENERATE REGISTRATION REPORT</LinkBtn>
            <LinkBtn kind="secondary" href="/reports/exam-readiness">GENERATE EXAMINATION REPORT</LinkBtn>
            <LinkBtn kind="secondary" href="/reports/exam-readiness?view=courses">GENERATE COURSE REPORT</LinkBtn>
            <LinkBtn kind="secondary" href="/dbops/data-quality">VIEW DATA QUALITY</LinkBtn>
          </div>
        </PBody>
      </Panel>
      <Panel title="Official reports issued" right={<Link className="lnk" href="/dbops/query?tab=reports">All official reports</Link>}>
        {h.reports.length ? (
          <DTable pageSize={0} noPrint cols={["Reference", "Report", "Scope", "Rows|num", "Issued"]}
            rows={h.reports.map((x) => [
              <b key="r" className="tnum">{x.reference}</b>, <span key="t">{x.title}</span>, <span key="s" className="sub2">{x.scope ?? ""}</span>,
              <span key="n" className="tnum">{x.row_count ?? ""}</span>, <span key="d" className="sub2">{x.generated_by ?? ""} · {new Date(x.generated_at).toLocaleString("en-GB")}</span>,
            ])} />
        ) : <PBody><div className="sub2">No official report issued yet. The examination readiness package and an exported query each receive a DBO reference.</div></PBody>}
      </Panel>
    </>
  );
}
