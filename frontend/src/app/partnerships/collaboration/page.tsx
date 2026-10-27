import Link from "next/link";
import { api } from "@/lib/api";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note } from "@/components/proto/ui";
import { CollaborationForm, type Options } from "./CollaborationForm";
import "../partnerships.css";
import { LinkRequest } from "./LinkRequest";

export const dynamic = "force-dynamic";
export const metadata = { title: "Partnership/Linkages/Collaboration Form" };

function Shield() {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" />
      <path d="m9 12 2 2 4-4" />
    </svg>
  );
}

/** /partnerships/collaboration — the public collaboration enquiry (V658): no session. Two columns (the University's word of
 *  27 October 2026): what the form is for, on the University's navy card where the crest stood, and the form beside it under
 *  "Partnership/Linkages/Collaboration Form"; one column on a narrow screen, the narrative first. */
export default async function CollaborationPage() {
  const o = await api<Options>("/api/v1/public/partnerships/options");
  if (!o.ok) {
    return <main className="ptn-page"><div className="ptn-page__inner"><div className="ptn-formcard"><ProblemNotice problem={o.problem} /></div></div></main>;
  }
  const s = o.data.settings;
  const groups = o.data.groups.map((g) => ({ ...g, items: o.data.categories.filter((c) => c.grp === g.code) })).filter((g) => g.items.length);
  return (
    <main className="ptn-page">
      <div className="ptn-page__inner">
        <div className="ptn-cols">
          {/* column 1: what the form is for */}
          <aside className="ptn-info" aria-labelledby="ptn-info-h">
            <p className="ptn-eyebrow"><Shield />Partnerships · Rev. Fr. Moses Orshio Adasu University, Makurdi</p>
            <h2 id="ptn-info-h" className="ptn-info__title">Initiate a collaboration or partnership</h2>
            <p className="ptn-lede">The University welcomes collaboration and partnership proposals from local and international organisations.</p>

            <section>
              <h3>Who may propose</h3>
              <p>Universities and other higher education institutions, research institutions, companies, government agencies, NGOs, foundations and donors,
                international organisations, industry, community organisations and other organisations.</p>
            </section>

            <section>
              <h3>What can be proposed</h3>
              <ul className="ptn-cats">
                {groups.map((g) => <li key={g.code}><strong>{g.label}</strong>: {g.items.map((c) => c.label).join(", ")}</li>)}
              </ul>
            </section>

            <section>
              <h3>What happens next</h3>
              <ol className="ptn-steps">
                <li>Submission</li><li>Automatic acknowledgement by email</li><li>Initial screening</li><li>Routing to the office or academic unit concerned</li>
                <li>Review</li><li>A request for more information, where needed</li><li>Due diligence, where applicable</li><li>A decision, and development where approved</li>
              </ol>
              <p className="ptn-small">We aim to acknowledge complete enquiries within {s.acknowledge_days} working days. Review takes longer, depending on the proposal.</p>
            </section>

            <p className="ptn-pledge">Submission of this form does not constitute acceptance of a partnership proposal or create a binding commitment with the University.</p>

            <section>
              <h3>This form is not for</h3>
              <ul className="ptn-not">
                <li>Admissions enquiries: <Link href="/apply">apply for admission</Link></li>
                <li>ICT support or signing in: <Link href="/login">help from the sign-in page</Link>, or <Link href="/track">track an ICT support ticket</Link></li>
                <li>Student support, payment enquiries, job applications, media enquiries, complaints and general customer service: contact the University&rsquo;s offices concerned{s.contact_email ? <> or write to <a href={`mailto:${s.contact_email}`}>{s.contact_email}</a></> : null}</li>
              </ul>
            </section>

            <p className="ptn-small">How your information is used: <Link href="/privacy-policy">the University&rsquo;s privacy policy</Link> · <Link href="/privacy-policy#s-cookies">Cookies</Link></p>
          </aside>

          {/* column 2: the form */}
          <div className="ptn-formcol">
            <section className="ptn-formcard ptn-public" aria-labelledby="ptn-form-h">
              <h1 id="ptn-form-h" className="ptn-h1">Partnership/Linkages/Collaboration Form</h1>
              {s.public_open ? <CollaborationForm options={o.data} /> : (
                <Note kind="info" title="The collaboration enquiry form is closed for now.">{s.contact_email ? <>Write to <a href={`mailto:${s.contact_email}`}>{s.contact_email}</a>.</> : null}</Note>
              )}
            </section>
            <section className="ptn-formcard ptn-public" aria-labelledby="ptn-link-h">
              <h2 id="ptn-link-h" className="ptn-h2" style={{ marginTop: 0 }}>Already submitted?</h2>
              <p>Follow your enquiry from the private link in its acknowledgement email. Lost it? Ask for a new one.</p>
              <LinkRequest />
            </section>
          </div>
        </div>
      </div>
    </main>
  );
}
