import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Projects, type Grant } from "./Projects";

export const dynamic = "force-dynamic";

/** t/projects — research grants and projects. */
export default async function ProjectsPage() {
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ rows: Grant[] }>("/api/v1/research/grants")]);
  return (
    <Shell route="t/projects" me={me.ok ? me.data : null}>
      {list.ok ? <Projects rows={list.data.rows} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
