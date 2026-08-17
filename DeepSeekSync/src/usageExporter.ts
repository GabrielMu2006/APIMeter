import { Page, Download } from "playwright";
import { EXPORT_WAIT_MS, NAV_TIMEOUT_MS, USAGE_URL, SIGN_IN_MARKERS } from "./config";
import { looksLikeSignIn } from "./browser";

export class SessionExpiredError extends Error {
  constructor() {
    super("DeepSeek session expired. Please login again.");
    this.name = "SessionExpiredError";
  }
}

/**
 * Headless sync: load saved session -> open Usage -> pick "near 30 days"
 * (text-based, several fallbacks) -> click Export -> wait for download.
 */
export async function exportUsage(page: Page): Promise<Download> {
  await page.goto(USAGE_URL, { waitUntil: "domcontentloaded", timeout: NAV_TIMEOUT_MS });
  await page.waitForTimeout(3000);
  if (looksLikeSignIn(page.url(), SIGN_IN_MARKERS)) {
    throw new SessionExpiredError();
  }

  const rangeLabels = ["近30天", "近 30 天", "近30天", "Last 30 days", "近7天", "近 7 天", "Last 7 days"];
  let picked = false;
  for (const label of rangeLabels) {
    const locator = page.getByText(label, { exact: false }).first();
    try {
      if ((await locator.count()) > 0) {
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

  const downloadPromise = page.waitForEvent("download", { timeout: EXPORT_WAIT_MS });
  const exportLabels = ["导出", "Export", "export"];
  let clicked = false;
  for (const label of exportLabels) {
    const button = page.getByRole("button", { name: new RegExp(label, "i") }).first();
    try {
      if ((await button.count()) > 0) {
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
    throw new Error("export button not found - page structure may have changed");
  }
  const download = await downloadPromise;
  console.log("[sync] download started: " + download.suggestedFilename());
  return download;
}