import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Docket, RegistrationView } from "@/lib/student-portal";
import { permitShown, type PermitState } from "@/lib/gst-eps-permit";
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
  // V728: the permit is asked for every semester of the session up to the open one too, where a carry-over may sit on an earlier
  // semester's registration; each answers whether it is shown (the examination cards keep their own semesters)
  const upTo = Array.from({ length: Math.max(1, Math.min(3, current?.openSemester ?? current?.semester ?? 1)) }, (_, i) => i + 1);
  const permitSemesters = d.ok ? [...new Set([...upTo, ...shown])].sort() : [];
  // V756: the Summer is never the open semester (it is no policy.semester), so its examination card and GST & EPS permit (semester 3)
  // are asked here too when neither a released sitting nor the open semester asked for them — read beside the others, a read that
  // fails taken as none. Each is kept only as this student's Summer (a CCE or postgraduate third semester is not) with something to show
  const summerReads = d.ok ? Promise.all([
    shown.includes(3) ? null : api<ExamCardState>(`/api/v1/me/exam-card?session=${encodeURIComponent(d.data.session)}&semester=3`).catch(() => null),
    // the permit is the examination session's (the docket's session); its endpoint takes the semester alone, as s/gstpermit asks it
    permitSemesters.includes(3) ? null : api<PermitState>("/api/v1/me/gst-eps-permit?semester=3").catch(() => null),
  ]) : null;
  const permits = (await Promise.all((permitSemesters.length ? permitSemesters : [undefined]).map((n) => api<PermitState>(`/api/v1/me/gst-eps-permit${n ? `?semester=${n}` : ""}`))))
    .flatMap((r) => (r.ok ? [r.data] : []));
  // V501: the examination card of the same semesters, by its own rule — every registered course, beside the GST & EPS permit
  const cards = d.ok ? (await Promise.all((shown.length ? shown : [undefined]).map((n) =>
      api<ExamCardState>(`/api/v1/me/exam-card?session=${encodeURIComponent(d.data.session)}${n ? `&semester=${n}` : ""}`))))
    .flatMap((r) => (r.ok ? [r.data] : [])) : [];
  const [summerCardRead, summerPermitRead] = (await summerReads) ?? [null, null];
  const summerCard = summerCardRead?.ok ? summerCardRead.data : null;
  const summerPermit = summerPermitRead?.ok ? summerPermitRead.data : null;
  // V756: a Summer registration still a DRAFT (courses the Academic Office is entering after a payment) shows no card: its card would
  // say to submit the courses and pay the school fees, which is not the student's to do
  if (summerCard?.summer && summerCard.registration && summerCard.registration.status !== "DRAFT" && !cards.some((c) => c.session === summerCard.session && c.semester === summerCard.semester)) cards.push(summerCard);
  if (summerPermit?.summer && permitShown(summerPermit) && !permits.some((p) => p.session === summerPermit.session && p.semester === summerPermit.semester)) permits.push(summerPermit);
  // V756: whether a session's semester is this student's Summer, as its examination card or GST & EPS permit answers (absent: not)
  const summerOf = (session: string, semester: number) =>
    [...cards, ...permits, summerCard, summerPermit].some((x) => !!x?.summer && x.session === session && x.semester === semester);
  // a live subtitle for the header — the exam sitting the examination card actually shows, not a fixed month
  let sub: string | undefined;
  if (d.ok) {
    const sits = d.data.examSessions;
    const shown = sits.find((x) => x.papers.length) ?? sits[0];
    sub = shown
      ? `${shown.session} · ${semesterName(shown.semester, summerOf(shown.session, shown.semester))} semester · ${shown.kind === "MAIN" ? "main" : shown.kind.toLowerCase()} examinations`
      : `${d.data.session} · no open sitting`;
  }
  return (
    <Shell route="s/exams" me={loaded.me} sub={sub}>
      {d.ok ? <Exams d={d.data} s={loaded.student} current={current} permits={permits} cards={cards} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
