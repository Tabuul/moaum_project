import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { EditSearch } from "./EditSearch";

export const dynamic = "force-dynamic";

/** /students/edit — V642: find the student whose record the Academic Office corrects */
export default async function StudentEditSearchPage() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/studentedit" me={me.ok ? me.data : null}>
      <EditSearch />
    </Shell>
  );
}
