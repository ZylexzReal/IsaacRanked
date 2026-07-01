import { runLaunchSession } from "./launch-session.js";

async function main(): Promise<void> {
  console.log("");
  console.log("Isaac Ranked Launcher");
  console.log("=====================");
  console.log("");

  const exitCode = await runLaunchSession({
    onStatus(event) {
      const prefix = event.level === "error" ? "ERROR: "
        : event.level === "warn" ? "WARN: "
          : "";
      console.log(`${prefix}${event.message}`);
    },
  });

  console.log("");
  console.log(`Done (exit code ${exitCode}).`);
}

main().catch((err) => {
  console.error("");
  console.error("Launcher failed:");
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});
