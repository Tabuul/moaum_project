"use client";

/**
 * Student Password Reset (V485): the student found by the server within the agent's reach — by matriculation number first, or the
 * JAMB number, the application number, the name or the phone — and opened on the one reset screen. Nothing is loaded until a
 * search is made, and only the page of matches the server returns.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { PasswordReset } from "@/components/support/PasswordReset";
import { failureWords } from "@/lib/password-reset";

interface Row {
  id: string; surname: string; other_names: string; matric_no: string | null; jamb_reg_no: string | null; application_no: string | null;
  programme: string | null; department: string | null; current_level: number | null; status: string;
}

export function PasswordResetDesk({ q: q0, student: student0 }: { q: string; student: string }) {
  const [q, setQ] = useState(q0);
  const [rows, setRows] = useState<Row[] | null>(null);
  const [total, setTotal] = useState(0);
  const [problem, setProblem] = useState<string | null>(null);
  const [student, setStudent] = useState(student0);

  async function search(term: string) {
    const t = term.trim();
    if (t.length < 2) { setProblem("Type at least two characters of a matriculation number, JAMB number, application number, name or phone."); return; }
    setProblem(null);
    const r = await fetch(`/api/bff/api/v1/helpdesk/support/students?q=${encodeURIComponent(t)}&size=20`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem(failureWords(j ?? { status: r.status })); setRows([]); setTotal(0); return; }
    setRows((j?.rows ?? []) as Row[]);
    setTotal(Number(j?.total ?? 0));
    const url = new URL(window.location.href);
    url.searchParams.set("q", t);
    url.searchParams.delete("student");
    window.history.replaceState(null, "", url.toString());
  }

  // a search carried in the address is run once, when the page opens
  useEffect(() => {
    if (!q0 || student0) return;
    void (async () => { await search(q0); })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function open(id: string) {
    setStudent(id);
    const url = new URL(window.location.href);
    url.searchParams.set("student", id);
    window.history.replaceState(null, "", url.toString());
  }

  return (
    <>
      <PageHead title="Student password reset" eyebrow="ICT Support Desk"
        description="Find the student, check who they are, and reset the password. The default student credential is the matriculation number, and the student must change it at the next sign-in. No email is needed, and the password is never shown or recorded."
        actions={<><LinkBtn href="/helpdesk/password-reset/history">Password reset history</LinkBtn><LinkBtn href="/helpdesk">Support Desk</LinkBtn></>} />

      <Panel title="Search student">
        <PBody>
          <form className="row row--inline" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); void search(q); }}>
            <div style={{ flex: "1 1 320px" }}>
              <Field id="pr-q" label="Matriculation number, JAMB number, application number, name or phone">
                <input id="pr-q" className="ctl" value={q} maxLength={80} autoFocus onChange={(e) => setQ(e.target.value)} placeholder="e.g. MOAU/SC/CSC/26/12345" />
              </Field>
            </div>
            <Btn kind="primary" type="submit" busyLabel="SEARCHING...">Search</Btn>
          </form>
          {problem ? <div className="mt-2"><Note kind="bad" title={problem} /></div> : null}
        </PBody>
        {rows ? (rows.length ? (
          <DTable pageSize={0} cols={["Student", "Matric No", "JAMB No", "Programme", "Level|num", "Status|mid", "|num"]} rows={rows.map((r) => [
            <span key="n"><b>{r.surname}, {r.other_names}</b>{r.application_no ? <div className="sub2 tnum">{r.application_no}</div> : null}</span>,
            <span key="m" className="tnum">{r.matric_no ?? <Pil kind="warn">No matriculation number</Pil>}</span>,
            <span key="j" className="tnum">{r.jamb_reg_no ?? "—"}</span>,
            <span key="p">{r.programme ?? "—"}<div className="sub2">{r.department ?? ""}</div></span>,
            <span key="l" className="tnum">{r.current_level ?? "—"}</span>,
            <Pil key="s" kind={r.status === "ACTIVE" ? "ok" : "grey"}>{r.status}</Pil>,
            <Btn key="o" kind={student === r.id ? "primary" : "ghost"} size="sm" onClick={() => open(r.id)}>{student === r.id ? "Selected" : "Select"}</Btn>,
          ])} />
        ) : <PBody><div className="sub2">No student within your reach matches “{q.trim()}”.</div></PBody>) : null}
        {rows && total > rows.length ? <PBody><div className="sub2">The first {rows.length} of {total.toLocaleString("en-GB")} matches, names A–Z. Type more of the number to narrow them.</div></PBody> : null}
      </Panel>

      {student ? (
        <Panel title="Student password reset" right={<Link className="lnk" href={`/helpdesk/students/${student}`}>Open the support record</Link>}>
          <PBody>
            <PasswordReset key={student} studentId={student} ticket={null} inline />
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
