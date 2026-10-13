import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Privacy, type AdminList, type DraftDoc, type HistoryRow } from "./Privacy";

export const dynamic = "force-dynamic";

/** t/privacy — the Privacy Policy and the other legal documents: the published version and who accepted it, the draft and its
 *  review points, the privacy contact, the providers the text names, every version kept, and who changed what (V441). */
export default async function PrivacyPage() {
  const [me, list, history] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<AdminList>("/api/v1/privacy/admin/documents"),
    api<{ rows: HistoryRow[] }>("/api/v1/privacy/admin/history?limit=60"),
  ]);
  const draftRow = list.ok ? list.data.rows.find((r) => r.kind === "PRIVACY_POLICY" && r.status === "DRAFT") : null;
  const draft = draftRow ? await api<DraftDoc>(`/api/v1/privacy/admin/documents/${draftRow.id}`) : null;
  return (
    <Shell route="t/privacy" me={me.ok ? me.data : null}>
      {list.ok ? (
        <Privacy list={list.data} draft={draft && draft.ok ? draft.data : null} history={history.ok ? history.data.rows : []}
          actingOffice={me.ok ? me.data.activeOffice : null} />
      ) : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
