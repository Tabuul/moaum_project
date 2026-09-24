import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short" }) + ", " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

/** s/notifications — every notice the portal sent, and how it reaches you */
export default async function Page() {
  const loaded = await loadStudent();
  const s = loaded.student;
  return (
    <Shell route="s/notifications" me={loaded.me}>
      {!s ? <ProblemNotice problem={loaded.problem} /> : (
        <>
          <Panel title="Notifications" right="Transactional messages are always delivered — results, payments and admission decisions cannot be switched off">
            {s.notices.length ? (
              <div className="card__body" style={{ gap: 0, padding: 0 }}>
                {s.notices.map((n, i) => (
                  <div key={n.id} className="row row--top" style={{ padding: "var(--s-3) var(--s-4)", gap: "var(--s-3)", borderBottom: i < s.notices.length - 1 ? "1px solid var(--line-2)" : undefined }}>
                    <span className="dot" style={{ background: n.state === "FAILED" ? "var(--red)" : n.state === "SENT" ? "var(--green)" : "var(--sky)", marginTop: 7 }} />
                    <div className="grow"><div className="b600">{n.subject}</div><div className="sub2" style={{ lineHeight: 1.5 }}>{n.body}</div></div>
                    <span className="sub2" style={{ whiteSpace: "nowrap" }}>{when(n.created_at)}</span>
                  </div>
                ))}
              </div>
            ) : <PBody><div className="sub2">Nothing sent to you yet. Every notice the portal sends is listed here as well, so nothing depends on a message reaching your phone.</div></PBody>}
          </Panel>
          <Panel title="How we reach you">
            <DTable cols={["Channel", "Transactional|mid", "Announcements|mid"]} rows={[
              [<span key="e">Email · {s.contact.email ?? s.contact.reach_email ?? "none on file"}</span>, <Pil kind="ok" key="t">Always on</Pil>, <Pil kind={s.contact.email || s.contact.reach_email ? "ok" : "bad"} key="a">{s.contact.email || s.contact.reach_email ? "On" : "No address"}</Pil>],
              [<span key="s">SMS · {s.contact.phone ?? s.contact.reach_phone ?? "none on file"}</span>, <Pil kind="ok" key="t">Always on</Pil>, <Pil kind={s.contact.phone || s.contact.reach_phone ? "ok" : "bad"} key="a">{s.contact.phone || s.contact.reach_phone ? "On" : "No number"}</Pil>],
              [<span key="i">In-app</span>, <Pil kind="ok" key="t">Always on</Pil>, <Pil kind="ok" key="a">On</Pil>],
            ]} />
            <PBody><div className="sub2">Change the address and number on your profile. Results, payments and admission decisions are always sent — you cannot switch those off, because the University must be able to reach you about them.</div></PBody>
          </Panel>
        </>
      )}
    </Shell>
  );
}
