import { Page, Download, BrowserContext } from "playwright";
import { EXPORT_WAIT_MS, NAV_TIMEOUT_MS, USAGE_URL, SIGN_IN_MARKERS } from "./config";
import { looksLikeSignIn, looksLikeBlocked } from "./browser";

export class SessionExpiredError extends Error {
  constructor() {
    super("DeepSeek session expired. Please login again.");
    this.name = "SessionExpiredError";
  }
}

export class BlockedError extends Error {
  constructor() {
    super("page blocked by bot protection (CloudFront) - retry, or run login again to refresh the session");
    this.name = "BlockedError";
  }
}

/**
 * Opens Usage with the saved session, picks the widest available preset
 * range, clicks Export and returns the download (context-scoped wait so a
 * page replacement cannot kill the listener).
 */
export async function exportUsage(context: BrowserContext, page: Page): Promise<Download> {
  await page.goto(USAGE_URL, { waitUntil: "domcontentloaded", timeout: NAV_TIMEOUT_MS });
  await page.waitForTimeout(4000);
  if (looksLikeSignIn(page.url(), SIGN_IN_MARKERS)) {
    throw new SessionExpiredError();
  }
  if (await looksLikeBlocked(page)) {
    throw new BlockedError();
  }

  // Range: prefer 30-day-ish presets, fall back to 7-day, else keep default.
  const rangeLabels = ["近 30 天", "近30天", "Last 30 days", "近 7 天", "近7天", "Last 7 days"];
  let picked = false;
  for (const label of rangeLabels) {
    try {
      const locator = page.getByText(label, { exact: false }).first();
      if ((await locator.count()) > 0 && (await locator.isVisible())) {
        await locator.click({ timeout: 5000 });
        console.log("[sync] selected range: " + label);
        picked = true;
        break;
      }
    } catch {
      /* try next label */
    }
  }
  if (!picked) {
    console.warn("[sync] range selector not found - using the page default range");
  }
  await page.waitForTimeout(1500);

  const downloadPromise = context.waitForEvent("download", { timeout: EXPORT_WAIT_MS });
  const exportLabels = ["导出", "Export", "export"];
  let clicked = false;
  for (const label of exportLabels) {
    try {
      const button = page.getByRole("button", { name: new RegExp(label, "i") }).first();
      if ((await button.count()) > 0 && (await button.isVisible())) {
        await button.click({ timeout: 5000 });
        console.log("[sync] clicked export button (" + label + ")");
        clicked = true;
        break;
      }
    } catch {
      /* try next label */
    }
  }
  if (!clicked) {
    throw new Error("export button not found - page structure may have changed (run dump to inspect)");
  }
  const download = await downloadPromise;
  console.log("[sync] download started: " + download.suggestedFilename());
  return download;
}