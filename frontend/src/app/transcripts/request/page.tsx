import Link from "next/link";
import { api } from "@/lib/api";
import { AuthLayout } from "@/components/auth/AuthLayout";
import { Note } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, type TrnOptions } from "@/lib/transcripts-public";
import { RequestForm } from "./RequestForm";
import "../transcripts.css";

export const dynamic = "force-dynamic";
export const metadata = { title: "Request an academic transcript" };

/** /transcripts/request — a transcript asked for without a portal account (V668): a graduate, or an institution with the graduate's consent */
export default async function TranscriptRequestPage() {
  const o = await api<TrnOptions>("/api/v1/public/transcripts/options");
  if (!o.ok) {
    return <AuthLayout eyebrow="Transcripts" wide><div className="card"><div className="card__body"><ProblemNotice problem={o.problem} /></div></div></AuthLayout>;
  }
  const full = o.data.policies.find((p) => p.kind === "TRANSCRIPT");
  return (
    <AuthLayout eyebrow="Transcripts" wide legal>
      <div className="card"><div className="card__body trn-public">
        <h1 className="trn-h1">Request an academic transcript</h1>
        <p>Graduates and former students of the University, and institutions or employers acting for them, can request an official academic transcript here without a portal account.
          Current students request theirs from <Link href="/login">the student portal</Link>.</p>

        <h2 className="trn-h2">How it works</h2>
        <ol className="trn-list">
          <li>Tell us who you are. A graduate confirms their record with a code we send to the email or phone on their record; without access to that contact, they attach an identity document for the Transcript Desk to check.</li>
          <li>Say where the transcript goes, and how: by email as a secure link, printed and posted, or both.</li>
          <li>Pay the fee with the payment reference you are given, online or at any bank.</li>
          <li>The Transcript Desk prepares the transcript, checks it, and has it signed and sealed. You follow each step from the private link in your acknowledgement email.</li>
        </ol>
        {full ? (
          <p>The fee for a full transcript sent by email is {full.fee_now !== null ? naira(full.fee_now) : "shown before you pay"}{full.physical_fee ? `; a printed copy adds ${naira(full.physical_fee)}` : ""}{full.international_fee ? `, and ${naira(full.international_fee)} more if posted abroad` : ""}.
            It is normally ready within {full.sla_days} working days of payment{full.urgent_sla_days ? ` (${full.urgent_sla_days} days if marked urgent${full.urgent_fee ? `, for ${naira(full.urgent_fee)} more` : ""})` : ""}.</p>
        ) : null}
        <Note kind="info" title="An institution's request needs the graduate's consent.">We email and text the graduate a link to agree to it. Nothing is prepared until they do.</Note>

        <RequestForm options={o.data} />

        <h2 className="trn-h2">Already requested?</h2>
        <p>Follow your request from the private link in its acknowledgement email. Every transcript the University issues carries a verification code you can check at <Link href="/verify/document">/verify/document</Link>.</p>
        <p className="sub2">How your information is used: <Link href="/privacy-policy">the University&rsquo;s privacy policy</Link>.</p>
      </div></div>
    </AuthLayout>
  );
}
