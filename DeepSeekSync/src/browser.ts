import { chromium, BrowserContext } from "playwright";
import * as fs from "node:fs";
import { BASE_DIR, PROFILE_DIR } from "./config";

export type LaunchMode = "headed" | "headless" | "hidden";

/**
 * Launches a PERSISTENT Chromium context: its profile (cookies/localStorage)
 * belongs to this module only - the user's normal browsers are never touched.
 *
 * Modes:
 * - headed:   visible window (first-run login, debugging)
 * - hidden:   full headed browser with the window placed far off-screen;
 *             keeps the real browser fingerprint that CloudFront accepts
 *             while staying practically invisible (used for sync)
 * - headless: plain headless (fast, but DeepSeek's CloudFront blocks it)
 */
export async function launchPersistent(mode: LaunchMode, storageState?: any): Promise<BrowserContext> {
  fs.mkdirSync(BASE_DIR, { recursive: true });
  const args = ["--disable-blink-features=AutomationControlled"];
  if (mode === "hidden") {
    args.push("--window-position=-3200,-3200", "--window-size=1000,800");
  }
  return chromium.launchPersistentContext(PROFILE_DIR, {
    headless: mode === "headless",
    viewport: { width: 1280, height: 900 },
    locale: "zh-CN",
    args,
    ...(storageState ? { storageState } : {}),
  });
}

/** True when the current URL looks like a sign-in page. */
export function looksLikeSignIn(url: string, markers: string[]): boolean {
  return markers.some((m) => url.toLowerCase().includes(m.toLowerCase()));
}

/** True when the page was replaced by a bot-protection error page. */
export async function looksLikeBlocked(page: { title(): Promise<string> }): Promise<boolean> {
  try {
    const title = await page.title();
    return /error: the request could not be satisfied|access denied|just a moment/i.test(title);
  } catch {
    return false;
  }
}