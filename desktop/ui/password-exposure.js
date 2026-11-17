const CHECK_INTERVAL_MS = 7 * 24 * 60 * 60 * 1000;
const RETRY_DELAY_MS = 6 * 60 * 60 * 1000;
const STORE_PREFIX = "password-exposure-v1:";

export async function fingerprintEncryptedCredential(document) {
  const canonicalDocument = Object.keys(document)
    .sort()
    .map((key) => [key, document[key]]);
  const bytes = new TextEncoder().encode(JSON.stringify(canonicalDocument));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function scanPasswordExposure({
  userId,
  credentials,
  storage = globalThis.localStorage,
  fetchImpl = globalThis.fetch,
  canCommit = () => true,
  now = Date.now(),
}) {
  if (typeof userId !== "string" || userId.length === 0) {
    throw new TypeError("La cuenta de la bóveda no es válida.");
  }
  const key = `${STORE_PREFIX}${userId}`;
  const state = readState(storage.getItem(key));
  const due = state.lastFullCheck === null
    || now - state.lastFullCheck >= CHECK_INTERVAL_MS;
  const previous = state.findings;
  const changed = due
    ? credentials
    : credentials.filter(({ id, revision }) => previous[id]?.revision !== revision);
  const counts = {};

  for (const credential of credentials) {
    const prior = previous[credential.id];
    if (!due && prior?.revision === credential.revision) {
      counts[credential.id] = prior.count;
    }
  }

  const newlyExposedIds = [];
  const countsByPassword = new Map();
  for (const credential of changed) {
    let count = countsByPassword.get(credential.password);
    if (count === undefined) {
      count = await countPasswordOccurrences(credential.password, fetchImpl);
      countsByPassword.set(credential.password, count);
    }
    counts[credential.id] = count;
    const prior = previous[credential.id];
    if (
      count > 0
      && (!prior || prior.revision !== credential.revision || prior.count === 0)
    ) {
      newlyExposedIds.push(credential.id);
    }
  }

  if (!canCommit()) {
    return null;
  }

  const findings = {};
  for (const credential of credentials) {
    if (Number.isSafeInteger(counts[credential.id])) {
      findings[credential.id] = {
        revision: credential.revision,
        count: counts[credential.id],
      };
    }
  }
  const lastFullCheck = due ? now : state.lastFullCheck;
  storage.setItem(key, JSON.stringify({
    version: 1,
    lastFullCheck,
    findings,
  }));
  return {
    counts,
    newlyExposedIds,
    nextFullCheckAt: lastFullCheck + CHECK_INTERVAL_MS,
    retryDelay: RETRY_DELAY_MS,
  };
}

async function countPasswordOccurrences(password, fetchImpl) {
  const passwordBytes = new TextEncoder().encode(password);
  let hash;
  try {
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", passwordBytes));
    hash = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0"))
      .join("")
      .toUpperCase();
  } finally {
    passwordBytes.fill(0);
  }

  const prefix = hash.slice(0, 5);
  const suffix = hash.slice(5);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);
  let response;
  let body = "";
  try {
    response = await fetchImpl(
      `https://api.pwnedpasswords.com/range/${prefix}`,
      {
        headers: { "Add-Padding": "true" },
        cache: "no-store",
        referrerPolicy: "no-referrer",
        signal: controller.signal,
      },
    );
    if (response.ok) {
      body = await response.text();
    }
  } catch {
    throw new Error("No se pudo completar la conexión con el servicio de comprobación.");
  } finally {
    clearTimeout(timeout);
  }
  if (!response.ok) {
    throw new Error(`El servicio de comprobación respondió con HTTP ${response.status}.`);
  }

  for (const line of body.split(/\r?\n/)) {
    const separator = line.indexOf(":");
    if (separator < 0 || line.slice(0, separator).toUpperCase() !== suffix) {
      continue;
    }
    const count = Number.parseInt(line.slice(separator + 1), 10);
    if (!Number.isSafeInteger(count) || count < 0) {
      throw new Error("El servicio de comprobación devolvió una respuesta no válida.");
    }
    return count;
  }
  return 0;
}

function readState(value) {
  if (value === null) {
    return { lastFullCheck: null, findings: {} };
  }
  let state;
  try {
    state = JSON.parse(value);
  } catch {
    throw new Error("El estado local de comprobación está dañado.");
  }
  if (
    !state
    || state.version !== 1
    || !state.findings
    || typeof state.findings !== "object"
    || (state.lastFullCheck !== null && !Number.isSafeInteger(state.lastFullCheck))
  ) {
    throw new Error("El estado local de comprobación está dañado.");
  }
  for (const finding of Object.values(state.findings)) {
    if (
      !finding
      || typeof finding.revision !== "string"
      || !Number.isSafeInteger(finding.count)
      || finding.count < 0
    ) {
      throw new Error("El estado local de comprobación está dañado.");
    }
  }
  return state;
}
