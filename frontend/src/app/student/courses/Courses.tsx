/** sCourses — proto/part8.html: one card per course, the material read, the assignments due — counted from the record (V035). */
import type { SpaceRow } from "@/lib/lms";
import { LinkBtn, Note, Pil } from "@/components/proto/ui";
import { Bar } from "@/components/proto/blocks";

export function Courses({ session, spaces }: { session: string; spaces: SpaceRow[] }) {
  const due = spaces.reduce((n, s) => n + s.due, 0);
  return (
    <>
      {spaces.length === 0 ? (
        <Note kind="info" title={`No course space for ${session} yet`}>A course space opens for every course on your approved registration. Register, have it approved, and the spaces appear here with whatever the lecturer has published.</Note>
      ) : due ? (
        <Note kind="bad" title={`${due} assignment${due === 1 ? "" : "s"} open and not yet submitted`}>Late submission is accepted within the window each assignment states, at the penalty it states. A marked submission is not replaced.</Note>
      ) : (
        <Note kind="ok" title="Nothing due">Every open assignment has your submission on it.</Note>
      )}
      <div className="grid grid--2">
        {spaces.map((s) => {
          const pct = s.materials ? Math.round((100 * s.accessed) / s.materials) : 0;
          return (
            <div className="card" key={s.offering_id}><div className="card__body">
              <div className="row row--between row--top">
                <div><div className="tnum b700 t-md">{s.course_code}</div><div className="sub2">{s.title}</div><div className="sub2">{s.lecturer ?? "No lecturer allocated yet"}</div></div>
                {s.due ? <Pil kind="bad">{s.due} due</Pil> : <Pil kind="ok">Up to date</Pil>}
              </div>
              <div className="row"><Bar pct={pct} /><span className="sub2 tnum">{s.materials ? `${pct}% of material read` : "Nothing published yet"}</span></div>
              <div className="row">
                <LinkBtn kind="ghost" href={`/student/courses/${s.offering_id}`}>Materials{s.weeks ? ` (${s.weeks} week${s.weeks === 1 ? "" : "s"})` : ""}</LinkBtn>
                {s.due ? <LinkBtn kind="primary" href={`/student/courses/${s.offering_id}#assignments`}>Open assignment</LinkBtn> : null}
              </div>
            </div></div>
          );
        })}
      </div>
    </>
  );
}
