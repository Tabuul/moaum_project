import { api } from "@/lib/api";
import { AuthLayout } from "@/components/auth/AuthLayout";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, PageHead } from "@/components/proto/ui";
import { TARGET_NOTE, longDay, monthsWords, naira, prelimPage, requirementWords, type PrelimPublic, type PrelimTarget } from "@/lib/preliminary";

/**
 * The public page of a preliminary or proficiency programme (V446, V701) — Preliminary Science, Preliminary Technology & Industrial
 * Studies, the Adikpo Campus proficiency certificate courses — as the University's configuration states it: the description, the
 * programme type, campus and duration, the session and the Director of ICT's window, the entry requirement and the remediation
 * rule, the targets (programmes of the register with their options and an area's subjects, or certificate courses by category),
 * the fee the Bursary stated (or none), the procedure and the documents. Every figure is read from the API.
 */
export async function PrelimProgrammePage({ slug }: { slug: string }) {
  const r = await api<PrelimPublic>(`/api/v1/public/preliminary/${slug}`, { anonymous: true });
  if (!r.ok) return <div style={{ padding: "var(--s-5)" }}><ProblemNotice problem={r.problem} /></div>;
  const p = r.data;
  const page = prelimPage(p.route);
  const open = p.window.state === "OPEN";
  const groups = [...new Set(p.targets.map((t) => t.group))];
  const rules = p.rules;
  const courses = p.targets.every((t) => t.kind === "COURSE");
  const typeWord = p.programmeTypeCode === "PROFICIENCY_CERTIFICATE" ? "Proficiency certificate" : "Preliminary / Remedial";
  const target = (t: PrelimTarget) => (
    <li key={t.id}>
      {t.name}{t.kind === "PROGRAMME" && t.registerName && t.registerName.toLowerCase() !== t.name.toLowerCase() ? <span className="sub2"> ({t.registerName})</span> : null}
      {t.specialisations.length ? <div className="sub2">Specialisations: {t.specialisations.map((s) => s.name).join(", ")}</div> : null}
      {t.coreSubjects?.length ? <div className="sub2">Subjects ({t.minCoreCredits ?? rules.minCoreCredits} required): {t.coreSubjects.join(", ")}</div> : null}
    </li>
  );
  return (
    <AuthLayout wide eyebrow={`${typeWord} · ${p.session}${p.campus ? ` · ${p.campus.name}` : ""}`}
      lead={<>{p.description.split(". ").slice(0, 1).join("")}.</>}
      stats={courses
        ? [[String(p.targets.length), "certificate courses"], [String(groups.length), "categories"], [monthsWords(p.durationMonths), "duration"]]
        : [[String(rules.minCredits), "O'Level credits to apply"], [String(rules.maxSittings), "sittings at most"], [String(p.targets.length), `${p.targetWord}s`]]}>
      <div className="login-card" style={{ maxWidth: 860 }}>
        <PageHead title={p.name} description={`${p.session} academic session${p.campus ? ` · ${p.campus.name}` : ""}`} />
        {open ? (
          <Note kind="ok" title={`Applications are open${p.window.closesAt ? ` until ${longDay(p.window.closesAt)}` : ""}`}
            action={<LinkBtn kind="primary" href={`${page}/apply`}>Apply now</LinkBtn>}>
            Applications opened on {longDay(p.window.opensAt)}. Already started? <a className="lnk" href="/login">Sign in to continue your application</a>.
          </Note>
        ) : p.window.state === "SCHEDULED" ? (
          <Note kind="info" title={`Applications open on ${longDay(p.window.opensAt)}`}>The Apply button appears here when the application opens.</Note>
        ) : (
          <Note kind="bad" title="Application closed">{p.window.message ?? `${p.name} applications are not open at present.`} <a className="lnk" href="/login">Sign in</a> to an application you already started.</Note>
        )}

        <h2 className="h3 mt-3">Programme overview</h2>
        <p>{p.description}</p>
        <dl className="kv grid grid--3">
          <div><dt>Programme</dt><dd>{p.name}</dd></div>
          <div><dt>Programme type</dt><dd>{typeWord}</dd></div>
          <div><dt>Academic session</dt><dd>{p.session}</dd></div>
          <div><dt>Study mode</dt><dd>{p.studyMode === "FULL_TIME" ? "Full-time" : p.studyMode}</dd></div>
          {p.campus ? <div><dt>Campus</dt><dd>{p.campus.name}</dd></div> : null}
          <div><dt>Duration</dt><dd>{monthsWords(p.durationMonths)}</dd></div>
          {p.certificateType ? <div><dt>Certificate</dt><dd>{p.certificateType}</dd></div> : null}
          <div><dt>Application opening</dt><dd>{longDay(p.window.opensAt)}</dd></div>
          <div><dt>Application fee</dt><dd>{p.fee.stated && p.fee.applicationFee != null ? naira(p.fee.applicationFee) : "To be announced by the Bursary"}</dd></div>
        </dl>

        <h2 className="h3 mt-3">Entry requirements</h2>
        {p.entryRequirement ? <p>{p.entryRequirement}</p> : null}
        {rules.kind === "ATTEMPTED_CERTIFICATE" ? (
          <ul><li>You give the results of the secondary school certificate examination you sat; no credit grade is asked.</li>
            <li>Accepted: {rules.qualifications.map((q) => q.label).join(", ")}.</li></ul>
        ) : (
          <ul>
            <li>{requirementWords(p)}</li>
            {rules.qualifications.length ? <li>Accepted: {rules.qualifications.map((q) => q.label).join(", ")}.</li> : null}
          </ul>
        )}

        {rules.kind === "OLEVEL_CREDITS" && p.completionNote ? (
          <>
            <h2 className="h3 mt-3">Remediation requirement</h2>
            <p>{p.completionNote}</p>
            {rules.remediationTerms ? <p>{rules.remediationTerms}</p> : null}
          </>
        ) : null}

        <h2 className="h3 mt-3">{courses ? "Certificate courses" : `${p.targetWord[0].toUpperCase()}${p.targetWord.slice(1)}s`}</h2>
        {courses ? null : <p className="sub2">{p.targetNote ?? TARGET_NOTE}</p>}
        <div className="grid grid--2">
          {groups.map((g) => (
            <div key={g}>
              <h3 className="h4">{g}</h3>
              <ul>{p.targets.filter((t) => t.group === g).map(target)}</ul>
            </div>
          ))}
        </div>

        <h2 className="h3 mt-3">Method of application</h2>
        <ol>{p.procedure.map((s, i) => <li key={i}>{s}</li>)}</ol>

        <h2 className="h3 mt-3">Required documents</h2>
        <ul>
          {p.documents.filter((d) => d.required).map((d) => <li key={d.kind}>{d.label}{d.secondSittingOnly ? " (only with a second sitting)" : ""}</li>)}
          <li>The payment receipt: issued by the portal when your payment is verified.</li>
        </ul>
        {p.officeNote ? <p className="sub2">{p.officeNote}</p> : null}

        <div className="row row--inline mt-3">
          {open ? <LinkBtn kind="primary" href={`${page}/apply`}>Apply now</LinkBtn> : null}
          <LinkBtn kind="ghost" href="/login">Sign in</LinkBtn>
        </div>
      </div>
    </AuthLayout>
  );
}

/** the application's first step, or the closure message while the Director of ICT has the window closed (the API refuses again) */
export async function prelimApplyData(slug: string) {
  return api<PrelimPublic>(`/api/v1/public/preliminary/${slug}`, { anonymous: true });
}
