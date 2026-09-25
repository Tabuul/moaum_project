import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note } from "@/components/proto/ui";
import { api } from "@/lib/api";
import { loadStudent } from "../load";
import { Coursework } from "./Coursework";

export const dynamic = "force-dynamic";

/** s/pgcourses — postgraduate course registration & results (V211); postgraduates only. */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/pgcourses" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  if (loaded.student.entryMode !== "POSTGRADUATE") {
    return <Shell route="s/pgcourses" me={loaded.me}><Note kind="info" title="Postgraduate coursework">This page is for postgraduate students.</Note></Shell>;
  }
  // the School of Postgraduate Studies keeps its own calendar (V224): the coursework opens on its session in progress
  const pg = await api<{ session?: string }>("/api/v1/pg/coursework/summary");
  const current = pg.ok && pg.data.session ? pg.data.session : loaded.student.entrySession;
  return (
    <Shell route="s/pgcourses" me={loaded.me}>
      <Coursework initialSession={current} />
    </Shell>
  );
}
