import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Board } from "./Board";

export const dynamic = "force-dynamic";

const EDITORS = ["pgschool", "pgsecretary", "super"];

/** School Board & awards (Policy 33–34): cleared → recommend to Senate → award. */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/pgboard" me={me.ok ? me.data : null}>
      <Board mayEdit={EDITORS.includes(office ?? "")} />
    </Shell>
  );
}
