import { PgPortal } from "./PgPortal";

export const dynamic = "force-dynamic";

/** /pg/portal — the postgraduate applicant's own portal: their application, its status, and paying the fee online. */
export default function Page() {
  return <PgPortal />;
}
