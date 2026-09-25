import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Policy, Template } from "@/lib/documents";
import { Settings } from "./Settings";

export const dynamic = "force-dynamic";

/** t/documents › settings — the policy per document kind and the template versions */
export default async function DocumentSettingsPage() {
  const [me, dash, templates] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ policies: Policy[] }>("/api/v1/documents/dashboard"), api<Template[]>("/api/v1/documents/templates")]);
  return (
    <Shell route="t/documents" me={me.ok ? me.data : null}>
      {dash.ok ? <Settings policies={dash.data.policies} templates={templates.ok ? templates.data : []} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={dash.problem} />}
    </Shell>
  );
}
