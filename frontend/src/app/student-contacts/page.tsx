import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ContactUpload, type ContactSummary } from "./ContactUpload";

export const dynamic = "force-dynamic";

/** t/contactupload — Student contacts upload (V572): the students the University holds no phone or e-mail for within the office's
 *  reach, a template of them to fill, and the filled file previewed and loaded — only empty contacts filled */
export default async function StudentContactsPage() {
  const [me, summary] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ContactSummary>("/api/v1/student-contacts")]);
  return (
    <Shell route="t/contactupload" me={me.ok ? me.data : null}>
      {summary.ok ? <ContactUpload summary={summary.data} /> : <ProblemNotice problem={summary.problem} />}
    </Shell>
  );
}
