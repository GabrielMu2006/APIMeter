import * as path from "node:path";
import * as os from "node:os";

export const KEYCHAIN_SERVICE = "com.apimeter.deepseeksync";
export const KEYCHAIN_ACCOUNT = "session";

export const USAGE_URL = "https://platform.deepseek.com/usage";
export const SIGN_IN_MARKERS = ["/sign_in", "/sign-in", "/login", "/signin"];

export const BASE_DIR = path.join(os.homedir(), "Library", "Application Support", "DeepSeekSync");
export const PROFILE_DIR = path.join(BASE_DIR, "browser-profile");
export const DOWNLOADS_DIR = path.join(BASE_DIR, "downloads");
export const STATE_FILE = path.join(BASE_DIR, "sync-state.json");

export const LOGIN_TIMEOUT_MS = 10 * 60 * 1000;
export const NAV_TIMEOUT_MS = 60 * 1000;
export const EXPORT_WAIT_MS = 5 * 60 * 1000;