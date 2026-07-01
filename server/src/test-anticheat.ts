import assert from "node:assert/strict";
import {
  REQUIRED_ANTICHEAT_VERSION,
  validateIntegrityReport,
  validateMatchStartedIntegrity,
} from "./anticheat.js";

function validReport(overrides: Record<string, unknown> = {}) {
  return {
    matchId: "match-1",
    vanillaConsoleDisabled: true,
    repentogonConsoleBlocked: true,
    consoleViolation: false,
    anticheatVersion: REQUIRED_ANTICHEAT_VERSION,
    modsWhitelisted: true,
    modWhitelistVersion: 1,
    enabledMods: ["isaac-ranked", "external item descriptions_836319872"],
    ...overrides,
  };
}

assert.equal(validateMatchStartedIntegrity(validReport()).ok, true);

const missingProtection = validateMatchStartedIntegrity(
  validReport({ repentogonConsoleBlocked: false })
);
assert.equal(missingProtection.ok, false);
assert.equal(missingProtection.reason, "run_protection_inactive");

const consoleEnabled = validateMatchStartedIntegrity(
  validReport({ vanillaConsoleDisabled: false })
);
assert.equal(consoleEnabled.ok, false);
assert.equal(consoleEnabled.reason, "vanilla_console_not_disabled");

const outdated = validateMatchStartedIntegrity(validReport({ anticheatVersion: 0 }));
assert.equal(outdated.ok, false);
assert.equal(outdated.reason, "anticheat_version_outdated");

const violation = validateIntegrityReport(
  validReport({ consoleViolation: true, violationReason: "blocked console command: giveitem" }),
  { strictPreflight: false }
);
assert.equal(violation.ok, false);
assert.equal(violation.reason, "blocked console command: giveitem");

const disallowedMod = validateMatchStartedIntegrity(
  validReport({
    modsWhitelisted: false,
    disallowedMods: ["isaac-reflourished_3655824749"],
    enabledMods: ["isaac-ranked", "isaac-reflourished_3655824749"],
  })
);
assert.equal(disallowedMod.ok, false);
assert.equal(disallowedMod.reason, "disallowed_mods:isaac-reflourished_3655824749");

console.log("anticheat validation test passed");
