import { api } from "@/lib/api";
import { loadScope, scopeParams } from "@/lib/scope-data";
import type { SheetListing } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Approvals } from "./Approvals";
import { RegistrationApprovals, type RegistrationRow } from "@/app/registration/RegistrationApprovals";

export const dynamic = "force-dynamic";

export default async function ApprovalsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const [me, listing, courses] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SheetListing>(`/api/v1/results/sheets?${scopeParams(scope)}`),
    api<{ code: string; title: string; semester: number }[]>(`/api/v1/ref/courses${scope.dept ? `?dept=${encodeURIComponent(scope.dept)}` : ""}`),
  ]);
  /* the department's registration desk (V027) sits above the result sets for the offices that approve registrations */
  const office = me.ok ? me.data.activeOffice : null;
  const departmental = ["hod", "lecturer", "dean", "facultyofficer", "academic", "registrar", "dregistrar", "super"].includes(office ?? "");
  const registrations = departmental
    ? await api<RegistrationRow[]>(`/api/v1/registration/course-registrations?session=${encodeURIComponent(scope.session)}&semester=${scope.sem || "1"}${scope.dept ? `&dept=${encodeURIComponent(scope.dept)}` : ""}&status=SUBMITTED`)
    : null;
  return (
    <Shell route="t/approvals" me={me.ok ? me.data : null}>
      {registrations && registrations.ok ? <RegistrationApprovals rows={registrations.data} session={scope.session} semester={Number(scope.sem || "1")} actingOffice={office} /> : null}
      {listing.ok ? (
        <Approvals
          scope={scope}
          structure={structure}
          sessions={sessions}
          courses={courses.ok ? courses.data : []}
          listing={listing.data}
          actingOffice={me.ok ? me.data.activeOffice : null}
        />
      ) : (
        <ProblemNotice problem={listing.problem} />
      )}
    </Shell>
  );
}
