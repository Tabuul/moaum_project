import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { whenAt } from "@/lib/cbt";

export const dynamic = "force-dynamic";

interface MySitting { sitting_id: string; label: string; venue: string; starts_at: string; ends_at: string; capacity: number; chief: boolean; exam_id: string; reference: string; title: string;
  course_code: string; state: string; live_state: string; duration_minutes: number; late_entry_minutes: number | null; seated: number; phase: "NOW" | "TO_COME" | "ENDED" }

const PHASE: Record<MySitting["phase"], [string, "ok" | "info" | "grey"]> = { NOW: ["Now", "ok"], TO_COME: ["To come", "info"], ENDED: ["Ended", "grey"] };

/** t/invigilate — the CBT sittings the signed-in member of staff invigilates (V374): those to come, and those of the last fortnight */
export default async function Page() {
  const [me, mine] = await Promise.all([api<Me>("/api/v1/iam/me"), api<MySitting[]>("/api/v1/cbt/invigilation")]);
  const word = (x: MySitting) => PHASE[x.phase] ?? PHASE.TO_COME;
  return (
    <Shell route="t/invigilate" me={me.ok ? me.data : null}>
      {!mine.ok ? <ProblemNotice problem={mine.problem} /> : mine.data.length ? (
        <Panel title="Your sittings" right={<span className="sub2">Open a sitting to see its seats</span>}>
          <DTable cols={["When", "Examination", "Sitting", "Seated|num", "|mid", "|mid"]} rows={mine.data.map((x) => [
            <span key="w">{whenAt(x.starts_at)}<div className="sub2">to {new Date(x.ends_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}</div></span>,
            <span key="e"><b className="tnum">{x.course_code}</b> {x.title}<div className="sub2 tnum">{x.reference} · {x.duration_minutes} minutes</div></span>,
            <span key="s">{x.label}<div className="sub2">{x.venue}{x.chief ? " · you are the chief invigilator" : ""}</div></span>,
            <span key="n" className="tnum">{x.seated}</span>,
            <Pil key="p" kind={word(x)[1]}>{word(x)[0]}</Pil>,
            <LinkBtn key="o" kind={x.phase === "NOW" ? "primary" : "secondary"} href={`/cbt/invigilate/${x.sitting_id}`}>Open</LinkBtn>,
          ])} />
        </Panel>
      ) : (
        <Panel title="Your sittings">
          <PBody>
            <Note kind="info" title="No sitting to invigilate">You are told by email when you are named.</Note>
          </PBody>
        </Panel>
      )}
    </Shell>
  );
}
