"use client";

/** V443: a course belongs to the department whose code it carries. A prefix that is a department's own code needs nothing — the rule
 *  reads it at insert and the pool was corrected once. A prefix that is no department's code (MTH, STA, LIN, HIS…) is named here to
 *  its department by the Academic Office and, when it says so, the courses holding that prefix move to it on the owner trail. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";

export interface CodeOwnerRow {
  prefix: string; courses: number; live_courses: number; is_department: boolean; mapped_dept: string | null; owner_by_code: string | null;
  owner_name: string | null; owners_now: string | null; astray: number; note: string | null; set_at: string | null;
}
export interface CodeOwners { rows: CodeOwnerRow[]; departments: { code: string; name: string }[] }

export function CodeOwnersPanel({ data, maySet }: { data: CodeOwners; maySet: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [choice, setChoice] = useState<Record<string, string>>({});
  const [onlyUnnamed, setOnlyUnnamed] = useState(true);
  const rows = data.rows.filter((r) => r.live_courses > 0 && (!onlyUnnamed || (!r.is_department && !r.mapped_dept) || r.astray > 0));
  const unnamed = data.rows.filter((r) => r.live_courses > 0 && !r.is_department && !r.mapped_dept).length;
  const astray = data.rows.reduce((n, r) => n + r.astray, 0);

  async function send(method: "PUT" | "POST" | "DELETE", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(path);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue/code-owners${path}`, {
        method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: method === "DELETE" ? undefined : JSON.stringify(body ?? {}),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return false; }
      const moved = Number((j as { moved?: number } | null)?.moved ?? 0);
      notify(moved ? `${reason} · ${moved} course${moved === 1 ? "" : "s"} moved` : reason);
      router.refresh();
      return true;
    } finally {
      setBusy(null);
    }
  }

  return (
    <Panel title="Which department a course code names" right={`${unnamed} prefix${unnamed === 1 ? "" : "es"} named to no department · ${astray} course${astray === 1 ? "" : "s"} astray`}>
      <PBody>
        <div className="sub2 mb-2">
          A course belongs to the department whose code it carries: ENG 101 is the Department of English&apos;s whichever programme&apos;s structure carried it in.
          A prefix that is a department&apos;s own code needs nothing. A prefix that is no department&apos;s code is named here; &quot;Apply&quot; moves the courses holding it to that department, each move on the owner trail.
        </div>
        <label className="row row--inline row--tight mb-2"><input type="checkbox" checked={onlyUnnamed} onChange={(e) => setOnlyUnnamed(e.target.checked)} /> Only prefixes still to name, or with courses astray</label>
        {rows.length ? (
          <DTable cols={["Prefix", "Courses|num", "Names", "Held by now", "Astray|num", maySet ? "Action" : ""]} rows={rows.map((r) => [
            <b className="tnum" key="p">{r.prefix}</b>,
            <span className="tnum" key="n">{r.live_courses}</span>,
            r.is_department ? <Pil kind="ok" key="o">{r.owner_name ?? r.owner_by_code} · its own code</Pil>
              : r.mapped_dept ? <span key="o"><Pil kind="info">{r.owner_name ?? r.mapped_dept}</Pil>{r.note ? <span className="sub2"> · {r.note}</span> : null}</span>
              : <Pil kind="warn" key="o">Named to no department</Pil>,
            <span className="sub2" key="h">{r.owners_now ?? "—"}</span>,
            <span className={`tnum${r.astray ? " ink-red b700" : ""}`} key="a">{r.astray}</span>,
            maySet ? (
              <span key="x" className="row row--inline row--tight">
                {!r.is_department ? (
                  <>
                    <select className="ctl" value={choice[r.prefix] ?? r.mapped_dept ?? ""} onChange={(e) => setChoice({ ...choice, [r.prefix]: e.target.value })} aria-label={`Department for ${r.prefix}`}>
                      <option value="">— department —</option>
                      {data.departments.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}
                    </select>
                    <Btn kind="secondary" size="sm" disabled={busy !== null || !(choice[r.prefix] ?? r.mapped_dept)}
                      onClick={() => void send("PUT", `/${r.prefix}`, { department: choice[r.prefix] ?? r.mapped_dept, apply: true, reason: `${r.prefix} named to its department` }, `${r.prefix} named`)}>
                      Name &amp; apply
                    </Btn>
                    {r.mapped_dept ? <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => void send("DELETE", `/${r.prefix}`, null, `${r.prefix} no longer named`)}>Unname</Btn> : null}
                  </>
                ) : r.astray ? (
                  <Btn kind="secondary" size="sm" disabled={busy !== null} onClick={() => void send("POST", `/${r.prefix}/apply`, { reason: `${r.prefix} courses moved to their department` }, `${r.prefix} applied`)}>Apply</Btn>
                ) : <span className="sub2">—</span>}
              </span>
            ) : "",
          ])} texts={rows.map((r) => `${r.prefix} ${r.owner_name ?? ""} ${r.owners_now ?? ""}`)} />
        ) : <div className="sub2">Every prefix in use names its department, and no course sits astray.</div>}
      </PBody>
    </Panel>
  );
}
