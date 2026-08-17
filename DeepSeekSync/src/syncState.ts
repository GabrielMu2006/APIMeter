import * as fs from "node:fs";
import { STATE_FILE } from "./config";

export interface SyncState {
  lastSyncAt?: string;
  lastFileHash?: string;
  lastFilePath?: string;
}

export function loadState(): SyncState {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
  } catch {
    return {};
  }
}

export function saveState(state: SyncState): void {
  fs.mkdirSync(require("node:path").dirname(STATE_FILE), { recursive: true });
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}