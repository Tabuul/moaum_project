import { cookies } from "next/headers";
import { api } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { ApplicationClosed } from "@/components/ApplicationClosed";
import { AuthLayout } from "@/components/auth/AuthLayout";
import { LinkBtn, Note } from "@/components/proto/ui";
import { IUT_COOKIE, publicWindowOf, windowIsOpen, type PublicOptions } from "@/lib/transfer-application";
import { TransferApply } from "./TransferApply";

export const dynamic = "force-dynamic";
export const metadata = { title: "Inter-university transfer application" };

/** /transfer/apply — V766: the public inter-university transfer application, open to anyone (proxy.ts names this path exactly, so
 *  the applicant's portal under /transfer/portal and the desks under /transfers stay signed-in). It offers only the programmes and
 *  levels the Academic Office opened for the session's window; while the window is not open, the Academic Office's closed message.
 *  A transfer applicant already signed in is sent to their application rather than shown a second form. */
export default async function Page() {
  if ((await cookies()).get(IUT_COOKIE)?.value && (await sessionToken())) {
    return (
      <AuthLayout eyebrow="Inter-university transfer" lead={<>Your application is open on this device.</>}>
        <div className="login-card stack">
          <Note kind="info" title="You already have an application">Your inter-university transfer application is open: pay, upload, submit and follow it there.</Note>
          <LinkBtn kind="primary" size="md" href="/transfer/portal">Open it</LinkBtn>
        </div>
      </AuthLayout>
    );
  }
  const r = await api<PublicOptions>("/api/v1/public/inter-university-transfer", { anonymous: true });
  if (!r.ok || !windowIsOpen(r.data.window)) {
    return <ApplicationClosed title="The inter-university transfer application" eyebrow="Inter-university transfer" window={r.ok ? publicWindowOf(r.data) : null} />;
  }
  return <TransferApply options={r.data} />;
}
