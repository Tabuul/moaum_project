import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Structure, type ProgrammeOption, type StructureData } from "./Structure";

export const dynamic = "force-dynamic";

/** the offices that change a programme's structure; V471 adds the School of Postgraduate Studies (its postgraduate programmes)
 *  and the ICT Support Desk (what their postings grant) — the server checks each change whatever the screen shows */
const CHANGERS = ["hod", "dean", "academic", "dregistrar", "registrar", "admin", "super", "ict", "pgschool", "pgsecretary", "ictagent", "helpdeskhead"];

interface StructureAccessData { office: string; postgraduate: boolean; support: boolean; capabilities: string[]; ticket: boolean }

/** t/structure — what a programme offers at each level and semester, and the binding of a course into it */
export default async function StructurePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, programmes, access] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ProgrammeOption[]>("/api/v1/catalogue/programmes"),
    api<StructureAccessData>("/api/v1/catalogue/structure/access"),
  ]);
  const options = programmes.ok ? programmes.data.filter((x) => !x.archived) : [];
  const prog = typeof p.prog === "string" && p.prog ? p.prog : options[0]?.code ?? "";
  const ticket = typeof p.ticket === "string" ? p.ticket.slice(0, 40) : "";
  const data = prog ? await api<StructureData>(`/api/v1/catalogue/structure?prog=${encodeURIComponent(prog)}`) : null;
  const office = me.ok ? me.data.activeOffice : null;
  const caps = access.ok ? access.data.capabilities : [];
  const may = CHANGERS.includes(office ?? "") && (!access.ok || !access.data.support || caps.includes("BIND_COURSES"));
  // a course the pool does not hold is created here, owned by the programme's department: by the offices that create courses,
  // the School for its programmes, an agent whose posting carries editing courses
  const canCreate = may && caps.includes("EDIT_COURSES");
  return (
    <Shell route="t/structure" me={me.ok ? me.data : null}>
      {!programmes.ok ? <ProblemNotice problem={programmes.problem} /> : (
        <Structure programmes={options} prog={prog} data={data && data.ok ? data.data : null} problem={data && !data.ok ? data.problem : null} may={may}
          canCreate={canCreate} ticketRef={ticket} pgOffice={office === "pgschool" || office === "pgsecretary"} />
      )}
    </Shell>
  );
}
