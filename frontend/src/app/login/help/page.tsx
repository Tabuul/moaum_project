import { api } from "@/lib/api";
import { SignInHelp, type HelpField } from "./SignInHelp";

export const dynamic = "force-dynamic";

/** /login/help — V363: a person who cannot sign in asks the ICT Support Desk, with the questions the desk keeps for Login Issues */
export default async function Page() {
  const form = await api<{ open: boolean; fields: HelpField[] }>("/api/v1/helpdesk/sign-in-help");
  return <SignInHelp reachable={form.ok} open={form.ok && form.data.open} fields={form.ok && Array.isArray(form.data.fields) ? form.data.fields : []} />;
}
