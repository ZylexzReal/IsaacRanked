/**
 * Mods allowed during ranked play (besides Isaac Ranked itself).
 * Match folder names from the game's mod directory, e.g. "external item descriptions_836319872".
 */

export const MOD_WHITELIST_VERSION = 1;

export type ModWhitelistMatch = "exact" | "suffix" | "contains";

export interface ModWhitelistEntry {
  id: string;
  name: string;
  match: ModWhitelistMatch;
}

/** Always includes Isaac Ranked; extend with informational / QoL mods as needed. */
export const RANKED_MOD_WHITELIST: ModWhitelistEntry[] = [
  { id: "isaac-ranked", name: "Isaac Ranked", match: "exact" },
  {
    id: "836319872",
    name: "External Item Descriptions",
    match: "suffix",
  },
];

export function modFolderMatchesEntry(folder: string, entry: ModWhitelistEntry): boolean {
  if (entry.match === "exact") {
    return folder === entry.id;
  }
  if (entry.match === "suffix") {
    return folder === entry.id || folder.endsWith(`_${entry.id}`);
  }
  return folder.includes(entry.id);
}

export function isModFolderWhitelisted(folder: string): boolean {
  return RANKED_MOD_WHITELIST.some((entry) => modFolderMatchesEntry(folder, entry));
}

export function validateEnabledModFolders(enabledMods: string[]): {
  ok: boolean;
  disallowed: string[];
} {
  const disallowed = enabledMods.filter((folder) => !isModFolderWhitelisted(folder));
  return { ok: disallowed.length === 0, disallowed };
}
