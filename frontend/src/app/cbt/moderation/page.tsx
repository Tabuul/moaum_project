import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { num, whenAt } from "@/lib/cbt";

export const dynamic = "force-dynamic";

interface Row { bank: string; title: string; office: string | null; pending: number; for_me: number; mine_waiting: number; returned: number; returned_to_me: number; waiting_since: string | null }

const BANK_BASE: Record<string, string> = { gst: "/gst/question-bank", eps: "/eps/question-bank", jupeb: "/jupeb/question-bank" };
const MODERATORS = ["hod", "exams", "facultyexams", "dean", "gst", "eps", "super", "jupeb"];

/** t/moderation — question moderation (V375): every bank within the acting office's scope with questions waiting — how many the
 *  signed-in person may decide (they did not set them), how many were returned, and which of the setter's own wait or came back */
export default async function Page() {
  const [me, rows] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Row[]>("/api/v1/cbt/moderation/queue")]);
  const acting = me.ok ? me.data.activeOffice ?? "" : "";
  const base = BANK_BASE[acting] ?? "/exams/question-bank";
  const moderator = MODERATORS.includes(acting);
  const list = rows.ok ? rows.data : [];
  const forMe = list.reduce((n, r) => n + Number(r.for_me), 0);
  const returnedToMe = list.reduce((n, r) => n + Number(r.returned_to_me), 0);
  return (
    <Shell route="t/moderation" me={me.ok ? me.data : null}>
      {!rows.ok ? <ProblemNotice problem={rows.problem} /> : (
        <>
          <Tiles items={[
            ["BANKS WAITING", num(list.filter((r) => Number(r.pending) > 0).length), null, `${num(list.reduce((n, r) => n + Number(r.pending), 0))} questions awaiting a decision`],
            ["FOR YOU TO DECIDE", num(moderator ? forMe : 0), moderator && forMe ? "var(--amber-ink)" : null, moderator ? "Questions you did not set" : "Your office does not moderate"],
            ["RETURNED TO YOU", num(returnedToMe), returnedToMe ? "var(--red-ink)" : null, "Read the note, correct, and it goes back for moderation"],
            ["YOURS WAITING", num(list.reduce((n, r) => n + Number(r.mine_waiting), 0)), null, "Set by you, awaiting someone else"],
          ]} />
          {moderator ? <Note kind="info" title="Moderating">Approve or return questions one by one, or by sample. A question goes on a paper only once someone other than its setter has approved it.</Note> : null}
          <Panel title="Banks with questions waiting" right={<span className="sub2">Within your office&rsquo;s scope</span>}>
            {list.length ? (
              <DTable cols={["Bank", "Title", "Waiting|num", "For you|num", "Returned|num", "Waiting since", "|mid"]} rows={list.map((r) => [
                <b key="b" className="tnum">{r.bank}</b>,
                <span key="t">{r.title}{r.office ? <span className="sub2"> · {r.office}</span> : null}</span>,
                <span key="p" className="tnum">{r.pending}{Number(r.mine_waiting) ? <div className="sub2">{r.mine_waiting} yours</div> : null}</span>,
                Number(r.for_me) && moderator ? <Pil key="f" kind="warn">{r.for_me}</Pil> : <span key="f" className="sub2">—</span>,
                <span key="r" className="tnum">{r.returned}{Number(r.returned_to_me) ? <div><Pil kind="bad">{r.returned_to_me} to you</Pil></div> : null}</span>,
                <span key="w" className="sub2">{r.waiting_since ? whenAt(r.waiting_since) : "—"}</span>,
                <LinkBtn key="o" kind={Number(r.for_me) && moderator ? "primary" : "secondary"} href={`${base}?course=${encodeURIComponent(r.bank)}`}>Open the bank</LinkBtn>,
              ])} texts={list.map((r) => `${r.bank} ${r.title}`)} />
            ) : <PBody><div className="sub2">No question waits for moderation in your banks.</div></PBody>}
          </Panel>
        </>
      )}
    </Shell>
  );
}
