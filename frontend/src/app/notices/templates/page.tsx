import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Templates, type Template, type Settings, type Job } from "./Templates";

export const dynamic = "force-dynamic";

/** t/templates — the words every message the portal sends comes from, the engine's settings and the jobs it ran (V425). */
export default async function TemplatesPage() {
  const [me, templates, settings, jobs] = await Promise.all([
    api<Me>("/api/v1/iam/me"), api<Template[]>("/api/v1/notices/templates"), api<Settings>("/api/v1/notices/settings"), api<Job[]>("/api/v1/notices/jobs"),
  ]);
  return (
    <Shell route="t/templates" me={me.ok ? me.data : null}>
      {templates.ok ? (
        <Templates templates={templates.data} settings={settings.ok ? settings.data : null} jobs={jobs.ok ? jobs.data : []} actingOffice={me.ok ? me.data.activeOffice : null} />
      ) : <ProblemNotice problem={templates.problem} />}
    </Shell>
  );
}
