"use client";

/**
 * The University's own words for a programme — proto/part53.html's Edit on
 * "One course code, two names". The code is for ever (BR-007: a retired
 * programme keeps it for every graduate who holds it), the faculty follows
 * the department, and what JAMB calls it is the alias list's business, not
 * this modal's.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Programme } from "@/lib/caps";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Department {
  code: string;
  name: string;
  facultyName: string;
}

const CATEGORIES = ["UNDER GRADUATE", "POST GRADUATE"];

export function ProgrammeEditor({ programme, departments, onClose }: { programme: Programme; departments: Department[]; onClose: () => void }) {
  const router = useRouter();
  const [name, setName] = useState(programme.name);
  const [deptCode, setDeptCode] = useState(programme.deptCode);
  const [category, setCategory] = useState(programme.category);
  const [archived, setArchived] = useState(programme.archived);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const known = departments.some((d) => d.code === programme.deptCode);

  async function save() {
    setBusy(true);
    setProblem(null);
    try {
      const response = await fetch(`/api/bff/api/v1/admissions/programmes/${encodeURIComponent(programme.code)}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${programme.code}: ${reason.trim()}`) },
        body: JSON.stringify({ name: name.trim(), deptCode, category, archived }),
      });
      const body = await response.json().catch(() => null);
      if (response.ok) {
        router.refresh();
        onClose();
      } else {
        setProblem(body && typeof body === "object" && "status" in body ? (body as Problem) : { status: response.status, title: response.statusText });
      }
    } finally {
      setBusy(false);
    }
  }

  const ready = name.trim().length > 0 && deptCode.length > 0 && reason.trim().length > 0 && !busy;

  return (
    <Modal
      title={`${programme.code} · ${programme.name}`}
      sub={`${programme.facultyName ?? ""}${programme.jambName ? ` · JAMB calls it ${programme.jambName}` : " · no JAMB name yet"}`}
      wide
      onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <span style={{ flexGrow: 1 }} />
        <Btn kind="primary" disabled={!ready} onClick={() => void save()}>{busy ? "Saving…" : "Save the programme"}</Btn>
      </>}
    >
      <Note kind="info" title="The code never changes; the words around it may">
        A retired programme keeps its code for every graduate who holds it and simply stops admitting. What JAMB calls the programme is set from the alias list, not here.
      </Note>
      <div className="grid grid--2 rfgrid">
        <Field id="pg-name" label="The University calls it" full>
          <input id="pg-name" className="ctl" value={name} onChange={(e) => setName(e.target.value)} autoComplete="off" maxLength={200} />
        </Field>
        <Field id="pg-dept" label="Department" hint="The faculty follows the department">
          <select id="pg-dept" className="ctl" value={deptCode} onChange={(e) => setDeptCode(e.target.value)}>
            {!known ? <option value={programme.deptCode}>{programme.deptCode} · not in the structure</option> : null}
            {departments.map((d) => (
              <option key={d.code} value={d.code}>{d.code} · {d.name} · {d.facultyName}</option>
            ))}
          </select>
        </Field>
        <Field id="pg-cat" label="Category">
          <select id="pg-cat" className="ctl" value={category} onChange={(e) => setCategory(e.target.value)}>
            {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </Field>
        <Field id="pg-arch" label="Admissions" full>
          <label style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <input id="pg-arch" type="checkbox" checked={archived} onChange={(e) => setArchived(e.target.checked)} />
            <span>Retired: keeps its code, no longer admits</span>
          </label>
        </Field>
        <Field id="pg-reason" label="Reason" hint="Goes on the record with the change" full>
          <input id="pg-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} autoComplete="off" placeholder="Senate minute, or what was wrong" />
        </Field>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}
