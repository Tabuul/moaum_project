/** sCourses — proto/part8.html: one card per course, the material read, the assignments due — counted from the record (V035). */
import Link from "next/link";
import type { SpaceRow } from "@/lib/lms";
import { Note, Pil } from "@/components/proto/ui";
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
              <div style={{ display: "flex", justifyContent: "space-between", gap: 10, alignItems: "flex-start" }}>
                <div><div style={{ fontWeight: 700, fontSize: 15 }} className="tnum">{s.course_code}</div><div className="sub2">{s.title}</div><div className="sub2">{s.lecturer ?? "No lecturer allocated yet"}</div></div>
                {s.due ? <Pil kind="bad">{s.due} due</Pil> : <Pil kind="ok">Up to date</Pil>}
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 10 }}><Bar pct={pct} /><span className="sub2 tnum">{s.materials ? `${pct}% of material read` : "Nothing published yet"}</span></div>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                <Link href={`/student/courses/${s.offering_id}`} className="btn btn--ghost btn--sm">Materials{s.weeks ? ` (${s.weeks} week${s.weeks === 1 ? "" : "s"})` : ""}</Link>
                {s.due ? <Link href={`/student/courses/${s.offering_id}#assignments`} className="btn btn--primary btn--sm">Open assignment</Link> : null}
              </div>
            </div></div>
          );
        })}
      </div>
    </>
  );
}
