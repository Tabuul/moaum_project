"use client";
/** The ticket form (V251): the requester's details from the account, the category, the fields the category asks for,
 *  the subject and description, the evidence. On submission the number is shown and the ticket opened. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { EMAIL_OK, FILE_TYPES, MAX_FILE, PRIORITY, human, parse, readBase64, type Category, type Field as F, type Profile } from "@/lib/helpdesk";

export function NewTicket({ profile, categories, sessions }: { profile: Profile; categories: Category[]; sessions: string[] }) {
  const router = useRouter();
  const [code, setCode] = useState("");
  const [subject, setSubject] = useState("");
  const [description, setDescription] = useState("");
  const [email, setEmail] = useState(profile.email ?? "");
  const [phone, setPhone] = useState(profile.phone ?? "");
  const [details, setDetails] = useState<Record<string, string>>({});
  const [files, setFiles] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [done, setDone] = useState<{ id: string; number: string; attached: number; skipped: string[] } | null>(null);

  const category = categories.find((c) => c.code === code) ?? null;
  const fields = category ? parse<F[]>(category.fields, []) : [];
  const missing = fields.filter((f) => f.required && !(details[f.key] ?? "").trim());
  const emailFixed = !!(profile.email && profile.email.trim());
  const ready = !!category && subject.trim().length > 2 && description.trim().length > 9 && EMAIL_OK.test(email.trim()) && missing.length === 0;

  function pick(list: FileList | null) {
    const next = [...files];
    for (const f of Array.from(list ?? [])) if (next.length < 5 && !next.some((x) => x.name === f.name && x.size === f.size)) next.push(f);
    setFiles(next);
  }

  async function submit(e?: React.FormEvent) {
    e?.preventDefault();
    if (!ready || !category) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/helpdesk/my/tickets", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`ICT support ticket: ${category.name} — ${subject.trim()}`) },
        body: JSON.stringify({ category: category.code, subject: subject.trim(), description: description.trim(), email: email.trim(), phone: phone.trim(), details }),
      });
      const j = (await r.json().catch(() => null)) as { id: string; number: string } | Problem | null;
      if (!r.ok || !j || !("number" in j)) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      let attached = 0; const skipped: string[] = [];
      for (const f of files) {
        if (!FILE_TYPES.includes(f.type) || f.size > MAX_FILE) { skipped.push(f.name); continue; }
        try {
          const b64 = await readBase64(f);
          const a = await fetch(`/api/bff/api/v1/helpdesk/my/tickets/${j.id}/attachments`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${f.name} attached to ${j.number}`) }, body: JSON.stringify({ filename: f.name, contentType: f.type, contentBase64: b64 }) });
          if (a.ok) attached += 1; else skipped.push(f.name);
        } catch { skipped.push(f.name); }
      }
      setDone({ id: j.id, number: j.number, attached, skipped });
      notify(`Ticket ${j.number} submitted`);
      router.refresh();
    } finally { setBusy(false); }
  }

  if (done) {
    return (
      <>
        <Note kind="ok" title={`Your ticket number is ${done.number}`} action={<LinkBtn kind="primary" href={`/tickets/${done.id}`}>Open the Ticket</LinkBtn>}>
          Keep the number: quote it in any follow-up and use it, with your email address, on the public tracking page. The desk has been told, and you will be told when it is opened, when work begins and when it is resolved. An email confirming this has been sent to {email.trim()}.
          {done.attached ? ` ${done.attached} file${done.attached === 1 ? "" : "s"} attached.` : ""}
          {done.skipped.length ? ` Not attached (a PDF, JPEG or PNG of at most 5 MB is accepted): ${done.skipped.join(", ")}.` : ""}
        </Note>
        <div className="row"><LinkBtn href="/tickets">My Support Tickets</LinkBtn><Btn kind="ghost" onClick={() => { setDone(null); setCode(""); setSubject(""); setDescription(""); setDetails({}); setFiles([]); }}>Submit Another</Btn></div>
      </>
    );
  }

  return (
    <form onSubmit={(e) => void submit(e)}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div className="grid grid--2">
        <Panel title="Who you are" right="From your account; nothing to type">
          <PBody>
            <div className="stack">
              <KvGrid cls="grid--2" pairs={[
                ["Name", <strong key="n">{profile.name}</strong>],
                [profile.kind === "STUDENT" ? "Matriculation number" : "Staff number", <span key="m" className="tnum">{profile.number ?? "—"}</span>],
                ...(profile.programme ? [["Programme", profile.programme] as [string, string]] : []),
                ["Department", profile.department ?? "—"],
                ["Faculty", profile.faculty ?? "—"],
              ]} />
              <div className="row">
                <Field id="tk-email" label="Email" required hint={emailFixed ? `The address on your account; the desk writes here and the tracking page asks for it. Change it under ${profile.kind === "STUDENT" ? "Profile" : "your staff record"}.` : "Where the desk writes to you, and what the tracking page asks for"} style={{ flex: "1 1 220px" }}>
                  <input id="tk-email" className="ctl" type="email" value={email} readOnly={emailFixed} onChange={(e) => setEmail(e.target.value)} autoComplete="email" />
                </Field>
                <Field id="tk-phone" label="Phone" style={{ flex: "1 1 160px" }}>
                  <input id="tk-phone" className="ctl" value={phone} onChange={(e) => setPhone(e.target.value)} autoComplete="tel" />
                </Field>
              </div>
            </div>
          </PBody>
        </Panel>
        <Panel title="What it is about" right={category ? <PriorityHint p={category.suggested_priority} /> : "Choose a category"}>
          <PBody>
            <div className="stack">
              <Field id="tk-cat" label="Category" required>
                <select id="tk-cat" className="ctl" value={code} onChange={(e) => { setCode(e.target.value); setDetails({}); }}>
                  <option value="">Choose…</option>
                  {categories.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}
                </select>
              </Field>
              {category?.description ? <div className="sub2">{category.description}</div> : null}
              {fields.map((f) => <DynamicField key={f.key} f={f} value={details[f.key] ?? ""} sessions={sessions} onChange={(v) => setDetails({ ...details, [f.key]: v })} />)}
            </div>
          </PBody>
        </Panel>
      </div>
      <Panel title="The problem" right="A subject, the description, and any evidence">
        <PBody>
          <div className="stack">
            <Field id="tk-subject" label="Subject" required hint="One line that says what is wrong">
              <input id="tk-subject" className="ctl" value={subject} onChange={(e) => setSubject(e.target.value)} maxLength={200} autoComplete="off" />
            </Field>
            <Field id="tk-desc" label="Description" required hint="What happened, what you expected, and anything you already tried">
              <textarea id="tk-desc" className="ctl" rows={6} value={description} onChange={(e) => setDescription(e.target.value)} maxLength={8000} />
            </Field>
            <Field id="tk-files" label="Attachments" hint={`${category?.attachment_hint ? category.attachment_hint + ". " : ""}Optional. A PDF, JPEG or PNG of at most 5 MB each, up to five.`}>
              <input id="tk-files" className="ctl" type="file" accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png" multiple onChange={(e) => { pick(e.target.files); e.target.value = ""; }} />
            </Field>
            {files.length ? (
              <ul className="plain stack">
                {files.map((f) => (
                  <li key={f.name + f.size} className="row row--base">
                    <span>{f.name}</span><span className="sub2">{human(f.size)}</span>
                    {!FILE_TYPES.includes(f.type) || f.size > MAX_FILE ? <Pil kind="bad">Will be skipped</Pil> : null}
                    <button type="button" className="lnk" onClick={() => setFiles(files.filter((x) => x !== f))}>Remove</button>
                  </li>
                ))}
              </ul>
            ) : null}
            <div className="row row--base">
              <Btn kind="primary" type="submit" disabled={busy || !ready}>{busy ? "Submitting…" : "Submit the Ticket"}</Btn>
              {!ready ? <span className="sub2">{!category ? "Choose a category." : missing.length ? `Fill in: ${missing.map((m) => m.label).join(", ")}.` : subject.trim().length <= 2 ? "Give a subject." : description.trim().length <= 9 ? "Describe the problem." : "Give a valid email address."}</span> : <span className="sub2">You will receive a tracking number at once.</span>}
            </div>
          </div>
        </PBody>
      </Panel>
    </form>
  );
}

function PriorityHint({ p }: { p: string }) {
  const x = PRIORITY[p] ?? [p, "grey"];
  return <span className="row row--inline row--tight"><span className="sub2">Handled as</span><Pil kind={x[1]}>{x[0]}</Pil></span>;
}

/** one of the category's fields, by its type */
function DynamicField({ f, value, sessions, onChange }: { f: F; value: string; sessions: string[]; onChange: (v: string) => void }) {
  const id = `tk-f-${f.key}`;
  const listed = f.type === "select" ? (f.options ?? []) : f.type === "session" ? sessions : f.type === "semester" ? ["First semester", "Second semester"] : f.type === "level" ? ["100", "200", "300", "400", "500", "600"] : null;
  // a choice with nothing to choose from (the sessions could not be read, say) falls back to typing
  const opts = listed && listed.length ? listed : null;
  return (
    <Field id={id} label={f.label} required={f.required} hint={f.hint ?? (f.type === "session" && !opts ? "e.g. 2025/2026" : undefined)}>
      {opts ? (
        <select id={id} className="ctl" value={value} onChange={(e) => onChange(e.target.value)}>
          <option value="">Choose…</option>
          {opts.map((o) => <option key={o} value={o}>{f.type === "level" ? `${o} Level` : o}</option>)}
        </select>
      ) : f.type === "date" ? (
        <input id={id} className="ctl" type="date" value={value} onChange={(e) => onChange(e.target.value)} />
      ) : f.type === "number" ? (
        <input id={id} className="ctl tnum" inputMode="decimal" value={value} onChange={(e) => onChange(e.target.value.replace(/[^0-9.]/g, ""))} />
      ) : (
        <input id={id} className="ctl" value={value} onChange={(e) => onChange(e.target.value)} maxLength={500} autoComplete="off" />
      )}
    </Field>
  );
}
