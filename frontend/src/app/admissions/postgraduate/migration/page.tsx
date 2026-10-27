import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import type { BatchLine, Summary } from "@/lib/pg-migration";
import { PgMigration, type Figures, type ListPage } from "./PgMigration";

export const dynamic = "force-dynamic";

const VIEWS = ["migrated", "offered", "accepted", "screened", "students", "pending", "duplicates", "conflicts", "review", "errors", "documents", "fees"];

/** t/pgmigration — old-portal PG applicants migrated (V675): the templates, the uploads checked before they are imported, the old
 *  programmes mapped, the old portal's fees and documents, the history; ?batch= opens a batch, ?view= the records behind a figure. */
export default async function PgMigrationPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const batchId = typeof p.batch === "string" && /^[0-9a-f-]{36}$/i.test(p.batch) ? p.batch : null;
  const view = typeof p.view === "string" && VIEWS.includes(p.view) ? p.view : null;
  const page = typeof p.page === "string" && /^\d{1,5}$/.test(p.page) ? Number(p.page) : 0;
  const [me, figures, batches, batch, list] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Figures>("/api/v1/pg/migration/figures"),
    api<BatchLine[]>("/api/v1/pg/migration/batches"),
    batchId ? api<Summary>(`/api/v1/pg/migration/batches/${batchId}`) : Promise.resolve(null),
    view ? api<ListPage>(`/api/v1/pg/migration/list?view=${view}&page=${page}&size=50`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/pgmigration" me={me.ok ? me.data : null}>
      <PgMigration
        office={me.ok ? me.data.activeOffice ?? null : null}
        figures={figures.ok ? figures.data : null}
        problem={figures.ok ? null : figures.problem}
        batches={batches.ok ? batches.data : []}
        batch={batch && batch.ok ? batch.data : null}
        view={view}
        list={list && list.ok ? list.data : null}
      />
    </Shell>
  );
}
