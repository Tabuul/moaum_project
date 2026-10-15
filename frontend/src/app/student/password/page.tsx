import { redirect } from "next/navigation";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { StudentPassword, type PasswordStatus } from "./StudentPassword";

export const dynamic = "force-dynamic";

/** s/password — the forced password change (V485): a student whose password must change reaches this page alone until it is
 *  changed — after a reset by ICT Support, a temporary password, or the first sign-in. It reads only the account's state. */
export default async function StudentPasswordPage() {
  const [me, status] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PasswordStatus>("/api/v1/student-auth/password-status")]);
  if (me.ok && me.data.activeOffice !== "student") redirect("/");
  if (status.ok && !status.data.mustChange) redirect("/student");
  return (
    // the contact and privacy prompts write to the portal, which waits until the password is changed: they come back after it
    <Shell route="s/password" me={me.ok ? { ...me.data, contactPrompt: null, privacyPrompt: null } : null}>
      {status.ok ? <StudentPassword status={status.data} /> : <ProblemNotice problem={status.problem} />}
    </Shell>
  );
}
