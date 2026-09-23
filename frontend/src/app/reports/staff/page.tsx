import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Pil } from "@/components/proto/ui";
import { RegisterDesk } from "../RegisterDesk";
import {
  STAFF_FILTERS, STAFF_HEADERS, STAFF_KEYS, registerQuery, words,
  type RegisterPage, type StaffOptions, type StaffRow,
} from "@/lib/registers";

export const dynamic = "force-dynamic";

type Summary = { total: number; academic: number; female: number; male: number; active: number };

const rankCase = (r: string | null) => (r ? r.toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase()).replace(/\bIi\b/g, "II").replace(/\bI\b/g, "I") : "—");

/** the staff register, whole: every person with a staff number, with what HR holds (V069, V137) */
export default async function StaffRegister({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = registerQuery(p, STAFF_KEYS);
  const page = typeof p.page === "string" && /^\d+$/.test(p.page) ? Number(p.page) : 1;
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<RegisterPage<StaffRow, StaffOptions> & { summary: Summary; scope?: { label: string } | null }>(`/api/v1/reports/registers/staff?${q}${q ? "&" : ""}page=${page}&size=100`),
  ]);
  if (!data.ok) return <Shell route="t/regstaff" me={me.ok ? me.data : null}><ProblemNotice problem={data.problem} /></Shell>;
  const d = data.data;
  const initial: Record<string, string> = {};
  for (const k of STAFF_KEYS) if (typeof p[k] === "string") initial[k] = p[k] as string;
  const s = d.summary;

  return (
    <Shell route="t/regstaff" me={me.ok ? me.data : null}>
      <RegisterDesk
        kind="staff" title={d.scope?.label ? `Staff register · ${d.scope.label}` : "Staff register"} filters={STAFF_FILTERS} options={d.options as unknown as Record<string, unknown>}
        initial={initial} total={Number(d.total)} page={Number(d.page)} size={Number(d.size)}
        headers={STAFF_HEADERS}
        tiles={[
          ["Matched", Number(s.total).toLocaleString(), null, "members of staff"],
          ["Academic", Number(s.academic).toLocaleString(), null, `${(Number(s.total) - Number(s.academic)).toLocaleString()} non-teaching`],
          ["Active", Number(s.active).toLocaleString(), "var(--green-ink)", "in service"],
          ["Female / Male", `${Number(s.female).toLocaleString()} / ${Number(s.male).toLocaleString()}`, null, "where the record states it"],
        ]}
        cols={["Staff no.", "Name", "Rank", "Faculty / department", "Category|mid", "Status|mid", "Offices held", "Contact"]}
        rows={d.rows.map((r) => [
          <span key="n" className="tnum">{r.staff_number}</span>,
          <span key="nm"><strong>{r.surname}</strong>, {r.given_names}</span>,
          <span key="r">{rankCase(r.rank)}{r.conuass_step != null ? <div className="sub2 tnum">Step {r.conuass_step}</div> : r.grade ? <div className="sub2 tnum">{r.grade} · step {r.step}</div> : null}</span>,
          <span key="f">{r.faculty ?? "—"}<div className="sub2">{r.department ?? (r.department_code ?? "")}</div></span>,
          <Pil key="c" kind={r.category === "ACADEMIC" ? "info" : "grey"}>{r.category === "ACADEMIC" ? "Academic" : "Non-teaching"}</Pil>,
          <Pil key="st" kind={r.status === "ACTIVE" ? "ok" : r.status === "SUSPENDED" ? "warn" : "grey"}>{words(r.status)}</Pil>,
          <span key="o" className="sub2">{r.offices ?? "—"}</span>,
          <span key="ct" className="sub2">{r.email ?? ""}{r.email && r.phone ? " · " : ""}{r.phone ?? ""}</span>,
        ])}
        texts={d.rows.map((r) => `${r.staff_number} ${r.surname} ${r.given_names} ${r.rank ?? ""} ${r.department ?? ""} ${r.faculty ?? ""} ${r.email ?? ""}`)}
      />
    </Shell>
  );
}
