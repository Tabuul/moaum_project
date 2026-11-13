import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { MIGRATION_API } from "@/lib/prelim-migration";
import { PrelimMigration, type Access, type Tab } from "./PrelimMigration";

export const dynamic = "force-dynamic";

const VIEWS: Tab[] = ["upload", "history", "fees", "corrections"];

/** t/prelimmigration — old-portal preliminary applicants migrated (V737): a template and an upload for each preliminary programme,
 *  checked before anything is imported; the history of uploads; the old-portal application fees the Bursary verifies; the
 *  programme corrected by ICT. ?batch= opens an upload's preview (the screen is keyed by it, so a batch opened from the history
 *  shows on the Upload tab), ?view= a tab (fees for the Bursary's menu entry), ?sheet= the sheet the upload just read (V745). */
export default async function PrelimMigrationPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const batchId = typeof p.batch === "string" && /^[0-9a-f-]{36}$/i.test(p.batch) ? p.batch : null;
  const view = typeof p.view === "string" && (VIEWS as string[]).includes(p.view) ? (p.view as Tab) : null;
  const app = typeof p.app === "string" && /^[0-9a-f-]{36}$/i.test(p.app) ? p.app : null;
  /* V745: the sheet of the file the upload was read from, as the upload names it (a sheet name is at most 31 characters) */
  const sheet = batchId && typeof p.sheet === "string" && p.sheet.trim() ? p.sheet.trim().slice(0, 31) : null;
  const [me, access, batch] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Access>(`${MIGRATION_API}/access`),
    batchId ? api<Record<string, unknown>>(`${MIGRATION_API}/batches/${batchId}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/prelimmigration" me={me.ok ? me.data : null}>
      {!access.ok ? <ProblemNotice problem={access.problem} /> : (
        <PrelimMigration key={batchId ?? "none"} access={access.data} office={me.ok ? me.data.activeOffice ?? null : null} actorId={me.ok ? me.data.actorId ?? null : null}
          batch={batch && batch.ok ? batch.data : null} batchProblem={batch && !batch.ok ? batch.problem : null} view={view} app={app} sheet={sheet} />
      )}
    </Shell>
  );
}
