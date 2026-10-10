"use client";

/**
 * The sign-in, with what only the address says — where to go after it (?next=) and why single sign-on did not complete
 * (?sso=) — read in the browser, so the page served is the same for everyone and can be kept in a cache. The form is
 * drawn at once and usable before; what is typed meanwhile is kept, as the address only changes the form's props.
 */
import { useSyncExternalStore } from "react";
import { Login } from "./Login";
import type { SsoOption } from "./options";

const noChange = () => () => {};

/** a path on this site only: "/x", never "//host" or "/\host", which a browser would read as another site */
function samePath(p: string | null): string {
  return p && p.startsWith("/") && !p.startsWith("//") && !p.startsWith("/\\") ? p : "/";
}

export function SignIn({ sso }: { sso: SsoOption }) {
  const search = useSyncExternalStore(noChange, () => window.location.search, () => "");
  const q = new URLSearchParams(search);
  return <Login next={samePath(q.get("next"))} sso={sso} ssoProblem={q.get("sso") || null} />;
}
