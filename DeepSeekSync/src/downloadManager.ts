import { Download } from "playwright";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import { DOWNLOADS_DIR } from "./config";

export interface DownloadResult {
  path: string;
  fileName: string;
  sha256: string;
  bytes: number;
}

export async function saveDownload(download: Download): Promise<DownloadResult> {
  fs.mkdirSync(DOWNLOADS_DIR, { recursive: true });
  const suggested = download.suggestedFilename() || "usage-export.zip";
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const fileName = "export-" + stamp + "-" + suggested;
  const target = DOWNLOADS_DIR + "/" + fileName;
  await download.saveAs(target);
  const data = fs.readFileSync(target);
  const sha256 = crypto.createHash("sha256").update(data).digest("hex");
  return { path: target, fileName, sha256, bytes: data.length };
}