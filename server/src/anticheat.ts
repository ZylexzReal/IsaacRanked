import type { IntegrityReport } from "../../shared/protocol.js";
import {
  MOD_WHITELIST_VERSION,
  validateEnabledModFolders,
} from "../../shared/modWhitelist.js";

export const REQUIRED_ANTICHEAT_VERSION = 1;

export interface IntegrityValidationResult {
  ok: boolean;
  reason?: string;
}

export function validateIntegrityReport(
  report: IntegrityReport,
  options: { strictPreflight?: boolean } = {}
): IntegrityValidationResult {
  const strictPreflight = options.strictPreflight ?? true;

  if (!report.matchId) {
    return { ok: false, reason: "missing_match_id" };
  }

  if (report.consoleViolation) {
    return { ok: false, reason: report.violationReason ?? "console_violation" };
  }

  if (!report.repentogonConsoleBlocked) {
    return { ok: false, reason: "run_protection_inactive" };
  }

  if (strictPreflight && report.vanillaConsoleDisabled !== true) {
    return { ok: false, reason: "vanilla_console_not_disabled" };
  }

  if ((report.anticheatVersion ?? 0) < REQUIRED_ANTICHEAT_VERSION) {
    return { ok: false, reason: "anticheat_version_outdated" };
  }

  if (strictPreflight) {
    if (report.modsWhitelisted !== true) {
      if (report.disallowedMods && report.disallowedMods.length > 0) {
        return {
          ok: false,
          reason: `disallowed_mods:${report.disallowedMods.join(",")}`,
        };
      }
      return { ok: false, reason: "mod_whitelist_failed" };
    }

    if ((report.modWhitelistVersion ?? 0) < MOD_WHITELIST_VERSION) {
      return { ok: false, reason: "mod_whitelist_version_outdated" };
    }

    if (report.enabledMods) {
      const modCheck = validateEnabledModFolders(report.enabledMods);
      if (!modCheck.ok) {
        return {
          ok: false,
          reason: `disallowed_mods:${modCheck.disallowed.join(",")}`,
        };
      }
    }
  }

  return { ok: true };
}

export function validateMatchStartedIntegrity(report: IntegrityReport): IntegrityValidationResult {
  return validateIntegrityReport(report, { strictPreflight: true });
}
