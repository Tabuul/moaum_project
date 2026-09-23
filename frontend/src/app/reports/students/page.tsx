import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Pil } from "@/components/proto/ui";
import { RegisterDesk } from "../RegisterDesk";
import {
  STUDENT_FILTERS, STUDENT_HEADERS, STUDENT_KEYS, registerQuery, studentSheetRow, words,
  type RegisterPage, type StudentOptions, type StudentRow,
} from "@/lib/registers";

export const dynamic = "force-dynamic";

const STATUS_PILL: Record<string, "ok" | "info" | "warn" | "bad" | "grey"> = {
  ACTIVE: "ok", ADMITTED: "info", PROBATION: "warn", GRADUATED: "grey", DORMANT: "grey", DEFERRED: "info",
  SUSPENDED: "bad", RUSTICATED: "bad", EXPELLED: "bad", WITHDRAWN: "grey", TRANSFERRED_OUT: "grey", DECEASED: "grey",
};

type Summary = { total: number; female: number; male: number; active: number; postgraduate: number };

/** the student register, whole: every student on the books, filtered and searched (V013) */
export default async function StudentsRegister({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = registerQuery(p, STUDENT_KEYS);
  const page = typeof p.page === "string" && /^\d+$/.test(p.page) ? Number(p.page) : 1;
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<RegisterPage<StudentRow, StudentOptions> & { summary: Summary }>(`/api/v1/reports/registers/students?${q}${q ? "&" : ""}page=${page}&size=100`),
  ]);
  if (!data.ok) return <Shell route="t/regstudents" me={me.ok ? me.data : null}><ProblemNotice problem={data.problem} /></Shell>;
  const d = data.data;
  const initial: Record<string, string> = {};
  for (const k of STUDENT_KEYS) if (typeof p[k] === "string") initial[k] = p[k] as string;
  const s = d.summary;

  return (
    <Shell route="t/regstudents" me={me.ok ? me.data : null}>
      <RegisterDesk
        kind="students" title="Student register" filters={STUDENT_FILTERS} options={d.options as unknown as Record<string, unknown>}
        initial={initial} total={Number(d.total)} page={Number(d.page)} size={Number(d.size)}
        headers={STUDENT_HEADERS} sheetRow={studentSheetRow as (r: never) => (string | number | null)[]}
        tiles={[
          ["Matched", Number(s.total).toLocaleString(), null, "students on the register"],
          ["Active", Number(s.active).toLocaleString(), "var(--green-ink)", "active or on probation"],
          ["Female / Male", `${Number(s.female).toLocaleString()} / ${Number(s.male).toLocaleString()}`, null, s.total ? `${Math.round((100 * Number(s.female)) / Number(s.total))}% female` : ""],
          ["Postgraduate", Number(s.postgraduate).toLocaleString(), null, "of those matched"],
        ]}
        cols={["Matric / admission no.", "Name", "Sex|mid", "Faculty", "Programme", "Level|num", "Status|mid", "Entry"]}
        rows={d.rows.map((r) => [
          <span key="n" className="tnum">{r.matric_no ?? r.admission_no ?? "—"}</span>,
          <span key="nm"><strong>{r.surname}</strong>, {r.other_names}</span>,
          <span key="s">{r.sex ?? "—"}</span>,
          <span key="f">{r.faculty}<div className="sub2">{r.department ?? ""}</div></span>,
          <span key="p">{r.programme}</span>,
          <span key="l" className="tnum">{r.level}</span>,
          <Pil key="st" kind={STATUS_PILL[r.status] ?? "grey"}>{words(r.status)}</Pil>,
          <span key="e" className="sub2">{words(r.entry_mode)} · {r.entry_session}</span>,
        ])}
        texts={d.rows.map((r) => `${r.matric_no ?? ""} ${r.admission_no ?? ""} ${r.surname} ${r.other_names} ${r.programme} ${r.faculty}`)}
      />
    </Shell>
  );
}
