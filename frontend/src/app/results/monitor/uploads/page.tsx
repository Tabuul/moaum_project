import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { Uploads } from "./Uploads";

export const dynamic = "force-dynamic";

/** t/resultuploads — V700: the uploads of marks */
export default async function ResultUploadsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/resultuploads" me={me.ok ? me.data : null}>
      <Uploads scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} />
    </Shell>
  );
}
