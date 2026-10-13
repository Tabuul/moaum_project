import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { StudentRecord } from "@/lib/student";
import { loadStudent } from "../load";
import { Biodata, type BioLists } from "@/app/students/[id]/Biodata";
import { BiodataGatePanel } from "./BiodataGatePanel";

export const dynamic = "force-dynamic";

/** the lists the University holds (V273): each state with its local governments, and the countries */
async function lists(): Promise<BioLists | undefined> {
  const [states, countries] = await Promise.all([
    api<{ name: string; lgas: string | string[] }[]>("/api/v1/ref/states"),
    api<string[]>("/api/v1/ref/countries"),
  ]);
  if (!states.ok || !countries.ok || !states.data.length) return undefined;
  return {
    states: states.data.map((x) => {
      let lgas: string[] = [];
      try { lgas = Array.isArray(x.lgas) ? x.lgas : (JSON.parse(x.lgas) as string[]); } catch { lgas = []; }
      return { name: x.name, lgas };
    }),
    countries: countries.data,
  };
}

/** s/biodata — the student's own record, in full: read from JAMB, self-service, or on evidence. V423: with the biodata gate,
 *  the one page a student held by it opens on — what is required, what is missing, and the form that completes it. */
export default async function Page() {
  const loaded = await loadStudent({ gateOpen: true });
  if (!loaded.student) {
    return <Shell route="s/biodata" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  }
  const [rec, ls] = await Promise.all([api<StudentRecord>("/api/v1/me/biodata"), lists()]);
  const gate = loaded.gate;
  const missing = gate?.completion.missing.map((m) => m.item) ?? [];
  // open the form on the first section that still misses a required field
  const first = rec.ok ? rec.data.biodata.filter((f) => missing.includes(f.field)).sort((a, b) => a.ord - b.ord)[0]?.section : undefined;
  return (
    <Shell route="s/biodata" me={loaded.me}>
      {gate ? <BiodataGatePanel gate={gate} student={loaded.student} /> : null}
      {rec.ok ? <Biodata record={rec.data} may base="/api/bff/api/v1/me" required={gate?.requiredItems} missing={missing} lists={ls} startAt={first} />
        : <ProblemNotice problem={rec.problem} />}
    </Shell>
  );
}
