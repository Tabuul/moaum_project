import { LinkBtn, Note, PageHead } from "@/components/proto/ui";
import { AuthLayout } from "@/components/auth/AuthLayout";
import type { ReactNode } from "react";

/** one application window as the public reads it from /api/v1/public/application-windows (V312) */
export interface PublicWindow {
  type: string; label: string; session: string; status: string; open: boolean;
  opensAt: string | null; closesAt: string | null; message: string | null; applicationPath: string; applicationUrl: string;
}
export interface PublicWindows { postUtme: PublicWindow; postgraduate: PublicWindow; jupeb?: PublicWindow; cce?: PublicWindow; postUtmeCbt?: PublicWindow; postUtmeResults?: PublicWindow; now: string }

const when = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : null;

/**
 * The page an applicant meets at /apply or /pg/apply while the Director of ICT has that application window closed,
 * scheduled or expired: the Director's own message, the dates where there are any, and the way back to sign in. The
 * backend refuses the application whatever this page shows; this is the kind way of saying so first.
 */
export function ApplicationClosed({ title, eyebrow, window }: { title: string; eyebrow: string; window: PublicWindow | null }) {
  const status = window?.status ?? "UNKNOWN";
  const opens = when(window?.opensAt);
  const closes = when(window?.closesAt);
  const headline = status === "SCHEDULED" ? `${title} opens ${opens ? `on ${opens}` : "soon"}` : status === "UNKNOWN" ? `${title} cannot be confirmed open right now` : `${title} is closed`;
  const message = window?.message?.trim() || (status === "UNKNOWN"
    ? "The portal could not reach the University's records to confirm whether applications are open. Please try again in a few minutes."
    : status === "SCHEDULED"
      ? `${title} has not opened yet.${opens ? ` It opens on ${opens}.` : ""} Please come back then.`
      : `${title} is closed. Please check the University's official website and this portal for announcements regarding the next application window.`);
  return (
    <AuthLayout eyebrow={<>{eyebrow}{window ? ` ${window.session}` : ""}</>} lead={<>Thank you for your interest in the University. Applications are received only while the application period is open.</>} stats={[...(window ? [[window.session.slice(0, 4), "admission year"] as [ReactNode, ReactNode]] : []), [status === "SCHEDULED" ? "SOON" : status === "UNKNOWN" ? "—" : "CLOSED", title.toLowerCase()] as [ReactNode, ReactNode]]}>
        <div className="login-card">
          <PageHead title={headline} description={status === "SCHEDULED" ? "The application period has been scheduled by the University." : status === "UNKNOWN" ? "Try again shortly." : "No new application can be started until the University opens the next application period."} />
          <Note kind={status === "SCHEDULED" ? "info" : "bad"} title={status === "SCHEDULED" ? "Not yet open" : status === "UNKNOWN" ? "Please try again" : "Applications are closed"}>
            <span style={{ whiteSpace: "pre-line", display: "block" }}>{message}</span>
          </Note>
          {opens || closes ? (
            <div className="hint">
              {opens ? <div>Opens: {opens}</div> : null}
              {closes ? <div>{status === "EXPIRED" ? "Closed on" : "Closes"}: {closes}</div> : null}
              <div>Times are West Africa Time (Africa/Lagos).</div>
            </div>
          ) : null}
          <div className="stack" style={{ borderTop: "1px solid var(--line)", paddingTop: "var(--s-4)" }}>
            <LinkBtn kind="ghost" href="/login">Already registered? Sign in</LinkBtn>
            <div className="hint" style={{ textAlign: "center" }}>An applicant who registered while the window was open signs in as before to continue their application.</div>
          </div>
        </div>
    </AuthLayout>
  );
}
