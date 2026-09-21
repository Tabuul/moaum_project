import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Examiners } from "./Examiners";

export const dynamic = "force-dynamic";

const EDITORS = ["pgschool", "pgsecretary", "super"];

/** External examiners of the Postgraduate School (Policy 18). */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/pgexaminers" me={me.ok ? me.data : null}>
      <Examiners mayEdit={EDITORS.includes(office ?? "")} />
    </Shell>
  );
}
