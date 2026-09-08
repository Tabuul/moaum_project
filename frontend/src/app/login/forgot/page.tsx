import { Forgot } from "./Forgot";

export const dynamic = "force-dynamic";

/** an applicant who forgot the password: the reset link goes out as a notice, good for an hour, used once */
export default function ForgotPage() {
  return <Forgot />;
}
