import { SIGN_IN_TITLE, ssoOption } from "./options";
import { SignIn } from "./SignIn";

export const metadata = { title: SIGN_IN_TITLE };

/**
 * One door, the same for everyone: built once and rebuilt at most every minute (whether single sign-on is connected is the
 * API's to say), so it is served without a render or an API call, and a cache in front may keep it. What the address
 * carries (?next=, ?sso=) is read in the browser (SignIn).
 */
export const revalidate = 60;

export default async function LoginPage() {
  return <SignIn sso={await ssoOption()} />;
}
