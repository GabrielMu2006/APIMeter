import { execFileSync } from "node:child_process";
import { KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT } from "./config";

/**
 * Session (cookies + localStorage) lives ONLY in the macOS Keychain,
 * base64-encoded. Never written to disk as plaintext. Username/password
 * are never stored at all.
 */
export function saveSession(sessionJson: string): void {
  const payload = Buffer.from(sessionJson, "utf8").toString("base64");
  // Remove any previous item first (idempotent re-save).
  try {
    execFileSync("security", ["delete-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT], { stdio: "ignore" });
  } catch {
    /* not present - fine */
  }
  execFileSync("security", ["add-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-U", "-w", payload]);
}

export function loadSession(): string | null {
  try {
    const out = execFileSync("security", ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w"], { encoding: "utf8" });
    return Buffer.from(out.trim(), "base64").toString("utf8");
  } catch {
    return null;
  }
}

export function deleteSession(): void {
  try {
    execFileSync("security", ["delete-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT], { stdio: "ignore" });
  } catch {
    /* not present - fine */
  }
}