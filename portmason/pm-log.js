import { spawnSync } from "node:child_process";

function pmLogCommand() {
  if (process.env.PORTMASON_SHARE) {
    return `${process.env.PORTMASON_SHARE}/pm-log`;
  }

  return "pm-log";
}

export function log(
  levelOrMessage,
  maybeMessage,
) {
  const args =
    maybeMessage === undefined
      ? [String(levelOrMessage)]
      : [
          String(levelOrMessage),
          String(maybeMessage),
        ];

  const result =
    spawnSync(
      pmLogCommand(),
      args,
      {
        stdio: "inherit",
        env: process.env,
      },
    );

  if (result.error) {
    const fallbackLevel =
      maybeMessage === undefined
        ? "INFO"
        : String(levelOrMessage);

    const fallbackMessage =
      maybeMessage === undefined
        ? String(levelOrMessage)
        : String(maybeMessage);

    console.log(
      `[${fallbackLevel}] ${fallbackMessage}`,
    );
  }
}
