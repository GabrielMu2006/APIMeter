import { chromium, BrowserContext } from "playwright";
import * as fs from "node:fs";
import { BASE_DIR, PROFILE_DIR } from "./config";

/**
 * Launches a PERSISTENT Chromium context: its profile (cookies/localStorage)
 * belongs to this module only - the user's normal browsers are never touched.
 */
export async function launchPersistent(headed: boolean): Promise<BrowserContext> {
  fs.mkdirSync(BASE_DIR, { recursive: true });
  return chromium.launchPersistentContext(PROFILE_DIR, {
    headless: !headed,
    viewport: { width: 1280, height: 900 },
    locale: "zh-CN",
    args: ["--disable-blink-features=AutomationControlled"],
  });
}

/** True when the current URL looks like a sign-in page. */
export function looksLikeSignIn(url: string, markers: string[]): boolean {
  return markers.some((m) => url.toLowerCase().includes(m.toLowerCase()));
}