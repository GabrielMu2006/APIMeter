import * as fs from "node:fs";
import { BASE_DIR } from "./config";
import { launchPersistent } from "./browser";
import { loginAndSaveSession } from "./authenticator";
import { exportUsage, SessionExpiredError } from "./usageExporter";
import { saveDownload } from "./downloadManager";
import { loadSession, deleteSession } from "./sessionStore";
import { loadState, saveState } from "./syncState";

async function main(): Promise<void> {
  const command = process.argv[2] ?? "help";
  fs.mkdirSync(BASE_DIR, { recursive: true });
  try {
    switch (command) {
      case "login": {
        deleteSession();
        const context = await launchPersistent(true);
        try {
          await loginAndSaveSession(context);
        } finally {
          await context.close();
        }
        break;
      }
      case "sync": {
        const session = loadSession();
        if (!session) {
          console.error("No session found. Run: ./deepseek-sync login");
          process.exit(2);
        }
        const context = await launchPersistent(false);
        try {
          const page = await context.newPage();
          const download = await exportUsage(page);
          const result = await saveDownload(download);
          console.log("SYNC OK");
          console.log("  file: " + result.fileName);
          console.log("  path: " + result.path);
          console.log("  bytes: " + result.bytes);
          console.log("  sha256: " + result.sha256);
          saveState({
            lastSyncAt: new Date().toISOString(),
            lastFileHash: result.sha256,
            lastFilePath: result.path,
          });
        } finally {
          await context.close();
        }
        break;
      }
      case "status": {
        const session = loadSession();
        console.log("session: " + (session ? "saved (Keychain)" : "missing - run login"));
        const state = loadState();
        if (state.lastSyncAt) {
          console.log("last sync: " + state.lastSyncAt);
          console.log("last file hash: " + (state.lastFileHash ?? "?"));
          console.log("last file path: " + (state.lastFilePath ?? "?"));
        } else {
          console.log("last sync: never");
        }
        break;
      }
      case "dump": {
        const context = await launchPersistent(process.argv.includes("--headed"));
        try {
          const page = await context.newPage();
          await page.goto("https://platform.deepseek.com/usage", { waitUntil: "domcontentloaded" });
          await page.waitForTimeout(5000);
          console.log("URL: " + page.url());
          console.log("TITLE: " + (await page.title()));
          console.log("--- buttons ---");
          const buttons = await page.getByRole("button").all();
          for (const b of buttons.slice(0, 60)) {
            const text = ((await b.innerText().catch(() => "")) || "").trim().slice(0, 60);
            if (text) console.log("BUTTON: " + text);
          }
          console.log("--- links ---");
          const links = await page.locator("a").all();
          for (const l of links.slice(0, 40)) {
            const text = ((await l.innerText().catch(() => "")) || "").trim().slice(0, 60);
            if (text) console.log("LINK: " + text);
          }
        } finally {
          await context.close();
        }
        break;
      }
      case "logout": {
        deleteSession();
        console.log("session removed from Keychain");
        break;
      }
      default:
        console.log("deepseek-sync - DeepSeek Usage Export downloader");
        console.log("  login   first run: open browser, sign in by hand, save session to Keychain");
        console.log("  sync    headless: auto-export usage (near 30 days) and download the ZIP");
        console.log("  status  show session + last sync info");
        console.log("  dump    debug: print the Usage page buttons/links (--headed to watch)");
        console.log("  logout  delete the saved session");
    }
  } catch (error) {
    if (error instanceof SessionExpiredError) {
      console.error(error.message);
      process.exit(3);
    }
    console.error("SYNC FAILED: " + (error instanceof Error ? error.message : String(error)));
    process.exit(1);
  }
}

main();