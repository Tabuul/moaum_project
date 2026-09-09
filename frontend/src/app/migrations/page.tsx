import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Migrations, type Ledger } from "./Migrations";

export const dynamic = "force-dynamic";

/** t/migration — the migration ledger: what has been applied to this database. */
export default async function MigrationsPage() {
  const [me, ledger] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Ledger>("/api/v1/platform/migrations")]);
  return (
    <Shell route="t/migration" me={me.ok ? me.data : null}>
      {ledger.ok ? <Migrations d={ledger.data} /> : <ProblemNotice problem={ledger.problem} />}
    </Shell>
  );
}
