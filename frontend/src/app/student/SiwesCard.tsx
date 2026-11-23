import { LinkBtn, Note } from "@/components/proto/ui";
import { courseWords, dateWord, isCourseMode, naira, ownCourseList, ownCourses, siwesCardShown, siwesCourseOf, siwesNext, type MySiwes } from "@/lib/siwes";

/** V752: SIWES on the dashboard — read only where the menu carries the SIWES page (GET /me siwesArea): the session, the course, the
 *  fee and where the student stands, the step to take next, and the page that takes it. Shown only while SIWES binds the student's
 *  session or they have paid or registered it: a student who registered SIWES in an earlier session keeps the SIWES page in the menu,
 *  never a card saying they are not in SIWES, and a draft period shows nothing.
 *  V777: and while a SIWES course is theirs to pay for (every SIWES course carries the fee): the card names the courses with the
 *  level and semester each is taught in, never "300 Level, Second Semester" for a course that is not */
export function SiwesCard({ d }: { d: MySiwes | null }) {
  if (!d || !siwesCardShown(d)) return null;
  const n = siwesNext(d);
  const closes = d.period?.registrationCloses;
  const fee = d.fee?.state === "PUBLISHED" ? naira(d.fee.amount) : null;
  const byCourse = isCourseMode(d);
  // once registered, the course registered, whatever the programme is mapped to since
  const course = siwesCourseOf(d);
  // the COURSE shape: each SIWES course of theirs, with where it is taught
  const mine = byCourse ? ownCourses(d) : [];
  const own = ownCourseList(mine);
  return (
    <Note kind={n.tone} title={`SIWES${d.session ? ` ${d.session}` : ""}${byCourse ? "" : " · 300 Level, Second Semester"}`}
          action={n.link ? <LinkBtn kind="primary" href={n.link.href}>{n.link.label}</LinkBtn>
            : <LinkBtn kind={n.pay || n.register ? "primary" : "ghost"} href="/student/siwes">{n.pay ? "Pay the SIWES fee" : n.register ? "Register SIWES course" : "View details"}</LinkBtn>}>
      <b>{n.title}.</b> {byCourse ? (own ? `${mine.length === 1 ? "Course" : "Courses"}: ${own}.` : "") : course ? `Course: ${courseWords(course)}.` : ""}{fee && !d.paid ? ` Fee: ${fee}.` : ""}{d.paid ? ` Fee paid${d.paid.amount != null ? ` (${naira(d.paid.amount)})` : ""}.` : ""}
      {!byCourse && !d.registration && closes && n.step !== "NOT_ELIGIBLE" ? ` Registration closes on ${dateWord(closes)}.` : ""}
    </Note>
  );
}
