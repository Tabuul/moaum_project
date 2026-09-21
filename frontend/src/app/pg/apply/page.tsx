import { PgApply } from "./PgApply";

export const dynamic = "force-dynamic";

/** /pg/apply — the public postgraduate application, open to the world (no JAMB number). */
export default function Page() {
  return <PgApply />;
}
