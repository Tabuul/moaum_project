"use client";

/**
 * V749: the member of staff's own identity information, the three things the staff identity card and the University's letters
 * need — each section saved on its own, every write the signed-in person's (the server takes the person from the token):
 *
 *  PASSPORT PHOTOGRAPH — a JPEG or PNG is sent as it is; the server checks it (light, contrast, sharpness, size, orientation,
 *  the background) and enhances it for the card with global corrections only — never the face — keeping the original. The two
 *  are shown side by side with the verdict, what was found and what was done; the enhanced one becomes the card photograph
 *  only when accepted. Upload another, or try the enhancement again when it failed.
 *  E-MAIL ADDRESS — a code is sent to the new address; the address on record stays until the code comes back.
 *  BLOOD GROUP — the dashboard's form: one of the eight, confirmed as accurate.
 */
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { day } from "@/lib/format";
import {
  codeOf, describeRecord, emailOutcome, emailProblem, enhancementSteps, faceWords, flagWords, missingItems, photoFileProblem, photoStateWord,
  qualityWord, submissionOf, type PhotoSubmission, type StaffIdentityState,
} from "@/lib/identity";
import { BloodGroupForm } from "@/components/BloodGroupPrompt";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Field, Passport } from "@/components/proto/blocks";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { notify, notifyProblem } from "@/components/proto/Toast";

const BASE = "/api/bff/api/v1/staff/identity";

/** an instant in Lagos time, the same on the server's page and the browser's */
function when(s: string | null | undefined): string {
  if (!s) return "";
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return s;
  return d.toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });
}

/** a request's refusal as a problem the page can show */
async function refusal(r: Response): Promise<Problem> {
  const j = (await r.json().catch(() => null)) as Problem | null;
  return j && typeof j === "object" ? { ...j, status: j.status ?? r.status } : { status: r.status, title: r.statusText || "That did not go through" };
}
const OFFLINE: Problem = { status: 0, title: "The portal could not reach the server", detail: "Check your connection and try again; nothing was saved." };

async function post(path: string, body: unknown, reason: string): Promise<{ ok: true; data: unknown } | { ok: false; problem: Problem }> {
  try {
    const r = await fetch(`${BASE}${path}`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}),
    });
    if (!r.ok) return { ok: false, problem: await refusal(r) };
    return { ok: true, data: await r.json().catch(() => null) };
  } catch {
    return { ok: false, problem: OFFLINE };
  }
}

/** the upload, with the bytes' progress (fetch cannot say how much of a body has gone): uploading, then processing on the server */
function sendPhoto(body: string, reason: string, onSent: (pct: number) => void): Promise<{ status: number; json: unknown }> {
  return new Promise((resolve) => {
    const x = new XMLHttpRequest();
    x.open("POST", `${BASE}/photo`);
    x.setRequestHeader("Content-Type", "application/json");
    x.setRequestHeader("X-Reason", reasonHeader(reason));
    x.upload.onprogress = (e) => { if (e.lengthComputable && e.total > 0) onSent(Math.min(100, Math.round((e.loaded / e.total) * 100))); };
    x.upload.onload = () => onSent(100);
    x.onload = () => {
      let j: unknown = null;
      try { j = JSON.parse(x.responseText); } catch { j = null; }
      resolve({ status: x.status, json: j });
    };
    x.onerror = () => resolve({ status: 0, json: null });
    x.onabort = () => resolve({ status: 0, json: null });
    x.send(body);
  });
}

function readAsDataUrl(file: File): Promise<string> {
  return new Promise((res, rej) => {
    const rd = new FileReader();
    rd.onload = () => res(String(rd.result));
    rd.onerror = () => rej(new Error("read"));
    rd.readAsDataURL(file);
  });
}

/** one picture of the pair, whole (contained, never cropped by the page) in the card's upright frame */
function Shot({ src, alt, caption, children }: { src: string | null; alt: string; caption: string; children?: React.ReactNode }) {
  const [broken, setBroken] = useState<string | null>(null);
  const shown = src && broken !== src ? src : null;
  return (
    <figure style={{ margin: 0, display: "flex", flexDirection: "column", gap: 6, minWidth: 0 }}>
      <figcaption className="eyebrow">{caption}</figcaption>
      <div style={{ width: "100%", maxWidth: 260, aspectRatio: "4 / 5", border: "1px solid var(--line)", borderRadius: 6, background: "var(--line-2, #f3f4f6)", display: "flex", alignItems: "center", justifyContent: "center", overflow: "hidden" }}>
        {shown ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={shown} alt={alt} onError={() => setBroken(shown)} style={{ maxWidth: "100%", maxHeight: "100%", objectFit: "contain", display: "block" }} />
        ) : (
          <span className="sub2" style={{ padding: 12, textAlign: "center" }}>{children ?? "Not available"}</span>
        )}
      </div>
    </figure>
  );
}

type PhotoBusy = "upload" | "accept" | "retry" | "discard" | null;

function PhotoSection({ state }: { state: StaffIdentityState }) {
  const router = useRouter();
  const p = state.photo ?? {};
  // the upload shown: the one this visit sent (or the server's answer to it), else the one the server says waits on the person
  const [mine, setMine] = useState<PhotoSubmission | null | undefined>(undefined);
  const pendingId = p.pendingSubmission ?? null;
  // an upload left waiting from an earlier visit: its verdict, readings and steps read once (GET /photo/{id}); the state's own
  // few words meanwhile
  const [details, setDetails] = useState<PhotoSubmission | null>(null);
  useEffect(() => {
    if (!pendingId || mine !== undefined) return;
    let live = true;
    fetch(`${BASE}/photo/${encodeURIComponent(pendingId)}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => { const got = submissionOf(j); if (live && got && got.id === pendingId) setDetails(got); })
      .catch(() => { /* the few words the state gives stay */ });
    return () => { live = false; };
  }, [pendingId, mine]);
  const waiting: PhotoSubmission | null = pendingId
    ? details && details.id === pendingId
      ? details
      : { id: pendingId, state: p.pendingState ?? "PROCESSED", quality: p.pendingQuality ?? null, assessment: null, enhancement: null, error: null }
    : null;
  const sub = mine !== undefined ? mine : waiting;
  const [busy, setBusy] = useState<PhotoBusy>(null);
  const acting = useRef(false);
  const [pct, setPct] = useState(0);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [fileMsg, setFileMsg] = useState<string | null>(null);
  // the picture this visit last sent, so the same file is not sent twice
  const [sentFile, setSentFile] = useState<string | null>(null);
  // a new picture each time the card photograph or an upload's enhanced copy changes
  const [version, setVersion] = useState(0);
  const current = p.present ? `${BASE}/photo/current?v=${encodeURIComponent(p.updatedAt ?? "")}-${version}` : null;

  function begin(b: Exclude<PhotoBusy, null>): boolean {
    if (acting.current) return false;
    acting.current = true;
    setBusy(b);
    setProblem(null);
    return true;
  }
  function end() {
    acting.current = false;
    setBusy(null);
  }

  async function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    setFileMsg(null);
    const bad = photoFileProblem(file);
    if (bad) { setFileMsg(bad); return; }
    const sig = `${file.name}|${file.size}|${file.lastModified}`;
    if (sub && sub.state === "PROCESSED" && sentFile === sig) {
      setFileMsg("That is the photograph you have just uploaded: accept the enhanced copy, or choose a different photograph.");
      return;
    }
    if (!begin("upload")) return;
    setPct(0);
    try {
      let dataUrl: string;
      try { dataUrl = await readAsDataUrl(file); } catch { setFileMsg("The picture could not be read from your device."); return; }
      const b64 = dataUrl.split(",")[1] ?? "";
      const r = await sendPhoto(JSON.stringify({ contentType: file.type, dataBase64: b64 }), "Staff photograph uploaded for enhancement by the holder", setPct);
      if (r.status < 200 || r.status >= 300) {
        const j = r.json as Problem | null;
        const pr: Problem = r.status === 0 ? OFFLINE : j && typeof j === "object" ? { ...j, status: j.status ?? r.status } : { status: r.status, title: "The photograph was not taken" };
        setProblem(pr);
        notifyProblem(pr);
        return;
      }
      const got = submissionOf(r.json);
      if (!got) { setProblem({ status: 502, title: "The server's answer could not be read", detail: "Reload the page: the upload, if it was recorded, is shown there." }); return; }
      setMine(got);
      setSentFile(sig);
      setVersion((v) => v + 1);
      if (got.state === "FAILED") notify("The photograph was kept but could not be enhanced", "warn");
      else notify(`Photograph checked and enhanced — ${qualityWord(got.quality).label.toLowerCase()}`);
      router.refresh();
    } finally {
      end();
    }
  }

  async function act(kind: "accept" | "retry" | "discard") {
    if (!sub || !begin(kind)) return;
    try {
      const reason = kind === "accept" ? "Enhanced staff photograph accepted by the holder" : kind === "retry" ? "Staff photograph enhancement tried again by the holder" : "Staff photograph upload discarded by the holder";
      const r = await post(`/photo/${encodeURIComponent(sub.id)}/${kind}`, {}, reason);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      if (kind === "retry") {
        // the retry answers as the upload did; a bare state (the database's) keeps the rest of what is shown
        const bare = (r.data as { state?: unknown } | null)?.state;
        const got = submissionOf(r.data) ?? { ...sub, state: typeof bare === "string" ? bare : r.data === "FAILED" || r.data === "PROCESSED" ? r.data : sub.state };
        setMine(got);
        setVersion((v) => v + 1);
        notify(got.state === "FAILED" ? "The enhancement failed again: upload another photograph" : "Photograph enhanced", got.state === "FAILED" ? "warn" : "ok");
      } else {
        setMine(null);
        setSentFile(null);
        setVersion((v) => v + 1);
        notify(kind === "accept" ? "The enhanced photograph is now your identity-card photograph" : "The upload is discarded; your card photograph is unchanged");
      }
      router.refresh();
    } finally {
      end();
    }
  }

  const q = qualityWord(sub?.quality);
  const flags = flagWords(sub?.assessment?.flags);
  const steps = enhancementSteps(sub?.enhancement);
  const measures = describeRecord(sub?.assessment);
  const notes = describeRecord(sub?.enhancement);
  const [stateWord, stateKind] = photoStateWord(sub?.state);
  const canAccept = !!sub && sub.state === "PROCESSED" && sub.quality !== "REPLACE";
  const status: [string, "ok" | "warn" | "bad"] = p.enhanced ? ["Enhanced and accepted", "ok"] : p.present ? ["On file, not enhanced", "warn"] : ["None on file", "bad"];

  const chooser = (label: string, kind: "primary" | "ghost") => (
    <label className={`btn btn--${kind} btn--sm${busy ? " is-disabled" : ""}`} style={{ cursor: busy ? "default" : "pointer" }} aria-disabled={busy ? true : undefined}>
      {label}
      <input type="file" accept="image/jpeg,image/png" hidden disabled={busy !== null} onChange={(e) => void onFile(e)} />
    </label>
  );

  return (
    <div id="photo">
      <Panel title="PASSPORT PHOTOGRAPH" right={<Pil kind={status[1]}>{status[0]}</Pil>}>
        <PBody>
          <div className="row row--wrap" style={{ gap: "var(--s-4)", alignItems: "flex-start" }}>
            <div className="stack" style={{ gap: 6, alignItems: "center" }}>
              <Passport w={112} h={140} src={current} alt="Your identity-card photograph" />
              <span className="sub2">{p.present ? `On the card${p.updatedAt ? ` since ${day(p.updatedAt)}` : ""}` : "No photograph yet"}</span>
            </div>
            <div className="stack" style={{ flex: 1, minWidth: 240, gap: "var(--s-2)" }}>
              <p style={{ margin: 0 }}>
                A recent head-and-shoulders photograph: facing the camera, eyes open, on a plain light background, with no cap or dark glasses (a head covering
                worn for religion is fine). JPEG or PNG, up to 6 MB.
              </p>
              <p className="sub2" style={{ margin: 0 }}>
                The server checks it and enhances it for the card — light and contrast, colour balance, a mild clean-up and sharpening, turned upright and
                cropped to the card&rsquo;s upright frame — with corrections over the whole picture only: your face is never altered. The photograph you upload is
                kept as it is. Nothing changes on your card until you accept the enhanced copy.
              </p>
              <div className="row row--wrap row--tight" style={{ alignItems: "center" }}>
                {chooser(sub ? "Upload another" : p.present ? "Upload a new photograph" : "Upload a photograph", sub ? "ghost" : "primary")}
                {busy === "upload" ? (
                  <span className="sub2" role="status" aria-live="polite">
                    {pct < 100 ? `Uploading… ${pct}%` : "Processing… checking and enhancing the photograph"}
                  </span>
                ) : null}
              </div>
              {fileMsg ? <span className="sub2 ink-red" role="alert">{fileMsg}</span> : null}
            </div>
          </div>
          {problem ? <ProblemNotice problem={problem} /> : null}
        </PBody>

        {sub ? (
          <PBody style={{ borderTop: "1px solid var(--line-2)" }}>
            <div className="row row--wrap row--tight" style={{ alignItems: "center", marginBottom: "var(--s-3)" }}>
              <b>Your upload</b>
              <Pil kind={stateKind}>{stateWord}</Pil>
              {sub.quality ? <Pil kind={q.kind}>Quality: {q.label}</Pil> : null}
            </div>
            <div className="grid grid--2" style={{ gap: "var(--s-4)", maxWidth: 560 }}>
              <Shot src={`${BASE}/photo/${encodeURIComponent(sub.id)}/original?v=${version}`} alt="The photograph as you uploaded it" caption="Original — as uploaded" />
              <Shot src={sub.state === "FAILED" ? null : `${BASE}/photo/${encodeURIComponent(sub.id)}/enhanced?v=${version}`} alt="The enhanced photograph for the card" caption="Enhanced — for the card">
                {sub.state === "FAILED" ? `Could not be enhanced${sub.error ? `: ${sub.error}` : ""}` : undefined}
              </Shot>
            </div>

            {sub.state === "FAILED" ? (
              <Note kind="bad" title="The photograph could not be enhanced">
                {sub.error ?? "The server could not enhance it."} Your original is kept. Try the enhancement again, or upload another photograph.
              </Note>
            ) : sub.quality ? (
              <Note kind={q.kind === "ok" ? "ok" : q.kind === "bad" ? "bad" : "info"} title={`Quality: ${q.label}`}>
                {q.words}
                {flags.length ? (
                  <ul style={{ margin: "6px 0 0", paddingLeft: "1.2em", listStyle: "disc" }}>
                    {flags.map((f) => <li key={f}>{f}</li>)}
                  </ul>
                ) : null}
              </Note>
            ) : null}

            {steps.length || notes.length ? (
              <div className="mt-2">
                <div className="eyebrow">What was done</div>
                <ul style={{ margin: "4px 0 0", paddingLeft: "1.2em", listStyle: "disc" }}>
                  {steps.map((s, i) => (
                    <li key={i} className={s.applied ? undefined : "sub2"}>
                      {s.applied ? s.title : `${s.title} — not needed`}{s.detail ? <span className="sub2"> ({s.detail})</span> : null}
                    </li>
                  ))}
                  {notes.map(([k, v]) => <li key={k} className="sub2">{k}: {v}</li>)}
                </ul>
              </div>
            ) : null}
            {sub.assessment ? (
              <details className="mt-2">
                <summary className="sub2" style={{ cursor: "pointer" }}>What the check measured</summary>
                <ul style={{ margin: "4px 0 0", paddingLeft: "1.2em", listStyle: "disc" }} className="sub2">
                  {measures.map(([k, v]) => <li key={k}>{k}: <span className="tnum">{v}</span></li>)}
                  <li>Face: {faceWords(sub.assessment)}</li>
                </ul>
              </details>
            ) : null}

            <div className="row row--wrap row--tight mt-2" style={{ alignItems: "center" }}>
              {sub.state === "PROCESSED" ? (
                <Btn kind="primary" disabled={!canAccept || (busy !== null && busy !== "accept")} busy={busy === "accept"} busyLabel="Accepting…" onClick={() => void act("accept")}>
                  Accept enhanced photograph
                </Btn>
              ) : null}
              {sub.state === "FAILED" ? (
                <Btn kind="primary" disabled={busy !== null && busy !== "retry"} busy={busy === "retry"} busyLabel="Enhancing…" onClick={() => void act("retry")}>
                  Retry enhancement
                </Btn>
              ) : null}
              {chooser("Upload another", "ghost")}
              <Btn kind="ghost" disabled={busy !== null && busy !== "discard"} busy={busy === "discard"} busyLabel="Discarding…" onClick={() => void act("discard")}>
                Discard this upload
              </Btn>
            </div>
            {sub.state === "PROCESSED" && sub.quality === "REPLACE" ? (
              <p className="sub2 mt-1" style={{ marginBottom: 0 }}>This photograph cannot go on the card: upload another.</p>
            ) : sub.state === "PROCESSED" ? (
              <p className="sub2 mt-1" style={{ marginBottom: 0 }}>Look at the enhanced copy before you accept it: it becomes the photograph on your staff identity card.</p>
            ) : null}
          </PBody>
        ) : null}
      </Panel>
    </div>
  );
}

function EmailSection({ state }: { state: StaffIdentityState }) {
  const router = useRouter();
  const e = state.email ?? {};
  const [address, setAddress] = useState("");
  const [addressMsg, setAddressMsg] = useState<string | null>(null);
  // the address an open code went to: the one this visit sent, else the server's
  const [sent, setSent] = useState<string | null | undefined>(undefined);
  const sentTo = sent !== undefined ? sent : e.pending ?? null;
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState<"send" | "verify" | null>(null);
  const acting = useRef(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [answer, setAnswer] = useState<{ kind: "ok" | "bad"; title: string; detail: string } | null>(null);

  async function send(to: string) {
    const bad = emailProblem(to, e);
    if (bad) { setAddressMsg(bad); return; }
    if (acting.current) return;
    acting.current = true;
    setBusy("send");
    setProblem(null);
    setAnswer(null);
    setAddressMsg(null);
    try {
      const r = await post("/email/code", { email: to.trim() }, "A code to verify my e-mail address");
      if (!r.ok) { setProblem(r.problem); return; }
      const j = (r.data ?? {}) as { sentTo?: string; email?: string };
      const where = j.sentTo ?? j.email ?? to.trim().toLowerCase();
      setSent(where);
      setCode("");
      notify(`A code was sent to ${where}`);
    } finally {
      acting.current = false;
      setBusy(null);
    }
  }

  async function verify() {
    if (code.length !== 6 || acting.current) return;
    acting.current = true;
    setBusy("verify");
    setProblem(null);
    setAnswer(null);
    try {
      const r = await post("/email/verify", { code }, "My e-mail address verified by its code");
      if (!r.ok) { setProblem(r.problem); return; }
      const outcome = (r.data as { outcome?: unknown } | null)?.outcome;
      const words = emailOutcome(outcome);
      if (outcome === "VERIFIED") {
        notify(`${sentTo ?? "Your e-mail address"} is verified`);
        setSent(null);
        setAddress("");
        setCode("");
        setAnswer({ kind: "ok", title: words.title, detail: words.detail });
        router.refresh();
        return;
      }
      setAnswer({ kind: "bad", title: words.title, detail: words.detail });
      // a code that has run out, or an address another person took meanwhile, needs a new start
      if (outcome === "EXPIRED" || outcome === "TAKEN") { setSent(null); setCode(""); router.refresh(); }
    } finally {
      acting.current = false;
      setBusy(null);
    }
  }

  const status: [string, "ok" | "warn" | "bad"] = e.verified ? ["Verified", "ok"] : e.value ? ["Not verified", "warn"] : ["None on record", "bad"];

  return (
    <div id="email">
      <Panel title="E-MAIL ADDRESS" right={<Pil kind={status[1]}>{status[0]}</Pil>}>
        <PBody>
          <div className="stack" style={{ gap: "var(--s-3)" }}>
            <div>
              <div className="eyebrow">On record</div>
              <div><b className="tnum">{e.value ?? "None"}</b>{" "}
                <span className="sub2">{e.verified ? `— verified${e.verifiedAt ? ` on ${day(e.verifiedAt)}` : ""}` : e.value ? "— not verified" : ""}</span>
              </div>
              {e.value && !e.verified && !sentTo ? (
                <div className="mt-1">
                  <Btn kind="secondary" disabled={busy !== null} busy={busy === "send"} busyLabel="Sending…" onClick={() => void send(e.value as string)}>Send a code to this address</Btn>
                </div>
              ) : null}
            </div>

            {sentTo ? (
              <form className="stack" style={{ gap: "var(--s-2)" }} onSubmit={(ev) => { ev.preventDefault(); void verify(); }}>
                <Note kind="info" title={`A six-digit code was sent to ${sentTo}`}>
                  Enter it here. It lasts 15 minutes.
                  {e.value && sentTo.toLowerCase() !== e.value.toLowerCase() ? ` Until the new address is verified, the University keeps writing to ${e.value}.` : ""}
                </Note>
                <div className="row row--wrap row--tight" style={{ alignItems: "flex-end" }}>
                  <Field id="em-code" label="Code">
                    <input id="em-code" className="ctl tnum" inputMode="numeric" autoComplete="one-time-code" maxLength={6} placeholder="6-digit code"
                      value={code} onChange={(ev) => { setCode(codeOf(ev.target.value)); setAnswer(null); }} style={{ width: 140 }} />
                  </Field>
                  <Btn kind="primary" type="submit" disabled={code.length !== 6 || (busy !== null && busy !== "verify")} busy={busy === "verify"} busyLabel="Verifying…">Verify</Btn>
                  <Btn kind="ghost" disabled={busy !== null} busy={busy === "send"} busyLabel="Sending…" onClick={() => void send(sentTo)}>Send the code again</Btn>
                  <Btn kind="ghost" disabled={busy !== null} onClick={() => { setSent(null); setCode(""); setAnswer(null); setProblem(null); }}>Use another address</Btn>
                </div>
              </form>
            ) : (
              <form className="stack" style={{ gap: "var(--s-2)" }} onSubmit={(ev) => { ev.preventDefault(); void send(address); }}>
                <div className="row row--wrap row--tight" style={{ alignItems: "flex-end" }}>
                  <Field id="em-new" label={e.value ? "A new e-mail address" : "Your e-mail address"} error={addressMsg ?? undefined}>
                    <input id="em-new" className="ctl" type="email" autoComplete="email" value={address} placeholder="name@example.com"
                      onChange={(ev) => { setAddress(ev.target.value); setAddressMsg(null); }} style={{ minWidth: 260 }} />
                  </Field>
                  <Btn kind="primary" type="submit" disabled={!address.trim() || busy !== null} busy={busy === "send"} busyLabel="Sending…">Send code</Btn>
                </div>
                <span className="sub2">
                  A code goes to the new address; the address is changed only when you enter it here.
                  {e.value ? ` Until then the University keeps writing to ${e.value}.` : ""} An address another member of staff holds cannot be used.
                </span>
              </form>
            )}

            {answer ? <Note kind={answer.kind} title={answer.title}>{answer.detail}</Note> : null}
            {problem ? <ProblemNotice problem={problem} /> : null}
          </div>
        </PBody>
      </Panel>
    </div>
  );
}

function BloodSection({ state }: { state: StaffIdentityState }) {
  const router = useRouter();
  const b = state.bloodGroup ?? {};
  const status: [string, "ok" | "warn" | "bad"] = b.confirmed ? ["Confirmed", "ok"] : b.value ? ["Not confirmed", "warn"] : ["None on record", "bad"];
  return (
    <div id="blood">
      <Panel title="BLOOD GROUP" right={<Pil kind={status[1]}>{status[0]}</Pil>}>
        <PBody>
          <p style={{ marginTop: 0 }}>
            {b.value
              ? <>On record: <b>{b.value}</b>{b.confirmed ? ` — confirmed${b.confirmedAt ? ` on ${when(b.confirmedAt)}` : ""}${b.source === "DESK" ? ", recorded at the card desk" : ""}.` : " — not confirmed."}</>
              : "No blood group is on record."}
            {" "}It is printed on your staff identity card. {b.confirmed ? "To correct it, choose the right group and confirm it again." : "Choose yours and confirm that it is accurate."}
          </p>
          <BloodGroupForm kind="STAFF" current={b.value ?? null} idPrefix="me-bg" onSaved={() => router.refresh()} />
        </PBody>
      </Panel>
    </div>
  );
}

export function StaffIdentity({ state, name }: { state: StaffIdentityState; name: string | null }) {
  const missing = missingItems(state);
  return (
    <>
      {state.staff === false ? (
        <Note kind="bad" title="The portal does not hold you as a member of staff in service">
          A staff number and an office today or a record on the HR register, and not out of service in HR (every employment ended, from the
          exit&rsquo;s effective date), make a member of staff in service. If you are still in service, Human Resources puts your record right;
          until then the blood group cannot be saved here.
        </Note>
      ) : null}
      {missing.length ? (
        <Note kind="info" title={`${name ? `${name}: ` : ""}${missing.length === 1 ? "one thing is" : `${missing.length} things are`} still needed for your staff identity card`}>
          <ul style={{ margin: "4px 0 0", paddingLeft: "1.2em", listStyle: "disc" }}>
            {missing.map((m) => (
              <li key={m.key}><a className="lnk" href={m.key === "PHOTO" ? "#photo" : m.key === "EMAIL" ? "#email" : "#blood"}>{m.title}</a> <span className="sub2">— {m.detail}</span></li>
            ))}
          </ul>
        </Note>
      ) : (
        <Note kind="ok" title="Your staff identity information is complete">
          Your photograph is enhanced and accepted, your e-mail address is verified and your blood group is confirmed. You can change any of them here.
        </Note>
      )}
      <PhotoSection state={state} />
      <EmailSection state={state} />
      <BloodSection state={state} />
    </>
  );
}
