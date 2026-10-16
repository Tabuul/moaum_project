import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Docket, RegistrationView } from "@/lib/student-portal";
import type { PermitState } from "@/lib/gst-eps-permit";
import type { ExamCardState } from "@/lib/exam-card";
import { semesterName } from "@/lib/student-portal";
import { Exams } from "../Screens5";

/** s/exams — the papers the approved registration carries, when the scheme releases them */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/exams" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const d = await api<Docket>("/api/v1/me/docket");
  // V491: the registration of the semester open now — its examination card is offered as soon as it is approved
  let current: RegistrationView | null = null;
  if (d.ok) {
    const first = await api<RegistrationView>(`/api/v1/me/registration?session=${encodeURIComponent(d.data.session)}&semester=1`);
    current = first.ok ? first.data : null;
    const open = current?.openSemester ?? 1;
    if (current && open > 1) {
      const now = await api<RegistrationView>(`/api/v1/me/registration?session=${encodeURIComponent(d.data.session)}&semester=${open}`);
      current = now.ok && now.data.registration ? now.data : current;
    }
  }
  // V492: the GST & EPS permit of each semester shown here — the registration's, and any examination session's released
  const shown = d.ok ? [...new Set([current?.semester, ...d.data.examSessions.filter((x) => x.papers.length && x.session === d.data.session).map((x) => x.semester)]
    .filter((x): x is number => typeof x === "number"))].sort() : [];
  const permits = (await Promise.all((shown.length ? shown : [undefined]).map((n) => api<PermitState>(`/api/v1/me/gst-eps-permit${n ? `?semester=${n}` : ""}`))))
    .flatMap((r) => (r.ok ? [r.data] : []));
  // V501: the examination card of the same semesters, by its own rule — every registered course, beside the GST & EPS permit
  const cards = d.ok ? (await Promise.all((shown.length ? shown : [undefined]).map((n) =>
      api<ExamCardState>(`/api/v1/me/exam-card?session=${encodeURIComponent(d.data.session)}${n ? `&semester=${n}` : ""}`))))
    .flatMap((r) => (r.ok ? [r.data] : [])) : [];
  // a live subtitle for the header — the exam sitting the examination card actually shows, not a fixed month
  let sub: string | undefined;
  if (d.ok) {
    const sits = d.data.examSessions;
    const shown = sits.find((x) => x.papers.length) ?? sits[0];
    sub = shown
      ? `${shown.session} · ${semesterName(shown.semester)} semester · ${shown.kind === "MAIN" ? "main" : shown.kind.toLowerCase()} examinations`
      : `${d.data.session} · no open sitting`;
  }
  return (
    <Shell route="s/exams" me={loaded.me} sub={sub}>
      {d.ok ? <Exams d={d.data} s={loaded.student} current={current} permits={permits} cards={cards} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
