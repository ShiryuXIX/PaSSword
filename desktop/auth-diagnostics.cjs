const fs = require("node:fs/promises");
const path = require("node:path");

async function appendAuthFailure(userDataPath, details, timestamp = new Date()) {
  const logPath = path.join(userDataPath, "sign-in-diagnostics.log");
  const safeCode = typeof details?.code === "string"
    && /^(auth|desktop)\/[a-z0-9-]{1,80}$/.test(details.code)
    ? details.code
    : "unknown";
  const safeStage = ["oauth", "firebase"].includes(details?.stage) ? details.stage : "unknown";
  const safeAppVersion = typeof details?.appVersion === "string"
    && /^\d+\.\d+\.\d+(?:\.\d+)?$/.test(details.appVersion)
    ? details.appVersion
    : "unknown";
  const safeErrorType = typeof details?.errorType === "string"
    && /^[A-Za-z][A-Za-z0-9]{0,39}$/.test(details.errorType)
    ? details.errorType
    : "Error";
  const safeDetail = typeof details?.detail === "string"
    && /^[a-z0-9_-]{1,48}$/i.test(details.detail)
    ? ` detail=${details.detail}`
    : "";
  await fs.mkdir(userDataPath, { recursive: true });
  await fs.appendFile(
    logPath,
    `${timestamp.toISOString()} appVersion=${safeAppVersion} stage=${safeStage} errorCode=${safeCode} errorType=${safeErrorType}${safeDetail}\n`,
    { encoding: "utf8", mode: 0o600 },
  );
  return logPath;
}

module.exports = { appendAuthFailure };
