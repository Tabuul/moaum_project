import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Clearance, type ClearView } from "./Clearance";

export const dynamic = "force-dynamic";

const CLEARERS = ["pgsecretary", "pgschool", "super"];

/** The Secretary's thesis clearance desk (Policy 31–32). */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const view = await api<ClearView>("/api/v1/pg/secretary/clearance");
  return (
    <Shell route="t/pgclearance" me={me.ok ? me.data : null}>
      <Clearance view={view.ok ? view.data : null} problem={view.ok ? null : view.problem} mayClear={CLEARERS.includes(office ?? "")} />
    </Shell>
  );
}
