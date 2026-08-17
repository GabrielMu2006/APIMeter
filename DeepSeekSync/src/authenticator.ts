import { BrowserContext } from "playwright";
import { LOGIN_TIMEOUT_MS, USAGE_URL } from "./config";
import { saveSession } from "./sessionStore";

/**
 * First-run flow: opens a VISIBLE browser window on the Usage page.
 * The user completes whatever the platform asks for (password, WeChat
 * scan, captcha, MFA) by hand. We poll the URL until it is the Usage
 * page (i.e. logged in), then persist the session into Keychain.
 * Never touches the user's existing browsers, never stores credentials.
 */
export async function loginAndSaveSession(context: BrowserContext): Promise<void> {
  const page = await context.newPage();
  console.log("[login] opening " + USAGE_URL);
  console.log("[login] complete sign-in in the browser window that just opened.");
  console.log("[login] waiting until the Usage page loads (timeout 10 min)...");
  await page.goto(USAGE_URL, { waitUntil: "domcontentloaded" });
  const deadline = Date.now() + LOGIN_TIMEOUT_MS;
  let lastUrl = page.url();
  while (Date.now() < deadline) {
    await page.waitForTimeout(2000);
    const url = page.url();
    if (url !== lastUrl) {
      console.log("[login] current URL: " + url);
      lastUrl = url;
    }
    const onUsage = url.startsWith("https://platform.deepseek.com/usage")
      || url.includes("/usage");
    if (onUsage) {
      console.log("[login] signed in - saving session to Keychain");
      const storage = await context.storageState();
      saveSession(JSON.stringify(storage));
      console.log("[login] session saved (cookies + localStorage, Keychain-encrypted)");
      return;
    }
  }
  throw new Error("login timed out after 10 minutes");
}