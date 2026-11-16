const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const path = require("node:path");

const PIN_PATTERN = /^\d{4}$/;
const MAX_FAILED_ATTEMPTS = 5;
const LOCKOUT_MS = 30_000;

function createPinStore({ filePath, safeStorage, now = Date.now }) {
  let failedAttempts = 0;
  let lockedUntil = 0;

  async function readPin(userId) {
    validateUserId(userId);
    ensureEncryptionAvailable(safeStorage);

    let serialized;
    try {
      serialized = await fs.readFile(filePath, "utf8");
    } catch (error) {
      if (error.code === "ENOENT") {
        return null;
      }
      throw error;
    }

    let record;
    try {
      record = JSON.parse(serialized);
    } catch {
      throw new Error("No se pudo leer la configuración local del PIN.");
    }
    if (
      record?.version !== 1
      || typeof record.encryptedPin !== "string"
      || !/^[A-Za-z0-9+/]+={0,2}$/.test(record.encryptedPin)
    ) {
      throw new Error("La configuración local del PIN no es válida.");
    }

    let payload;
    try {
      payload = JSON.parse(safeStorage.decryptString(Buffer.from(record.encryptedPin, "base64")));
    } catch {
      throw new Error("Windows no pudo descifrar la configuración local del PIN.");
    }
    if (
      payload?.version !== 1
      || typeof payload.userId !== "string"
      || !PIN_PATTERN.test(payload.pin)
    ) {
      throw new Error("La configuración local del PIN no es válida.");
    }
    return payload.userId === userId ? payload.pin : null;
  }

  return Object.freeze({
    async hasPin(userId) {
      return (await readPin(userId)) !== null;
    },

    async setPin(userId, pin) {
      validateUserId(userId);
      validatePin(pin);
      ensureEncryptionAvailable(safeStorage);

      const encryptedPin = safeStorage.encryptString(JSON.stringify({
        version: 1,
        userId,
        pin,
      })).toString("base64");
      const temporaryPath = `${filePath}.${crypto.randomUUID()}.tmp`;
      await fs.mkdir(path.dirname(filePath), { recursive: true });
      await fs.writeFile(temporaryPath, JSON.stringify({ version: 1, encryptedPin }), {
        encoding: "utf8",
        flag: "wx",
        mode: 0o600,
      });
      await fs.rename(temporaryPath, filePath);
      failedAttempts = 0;
      lockedUntil = 0;
    },

    async verifyPin(userId, pin) {
      validateUserId(userId);
      validatePin(pin);
      const remainingLockoutMs = lockedUntil - now();
      if (remainingLockoutMs > 0) {
        return {
          configured: true,
          valid: false,
          retryAfterSeconds: Math.ceil(remainingLockoutMs / 1000),
        };
      }

      const storedPin = await readPin(userId);
      if (storedPin === null) {
        return { configured: false, valid: false };
      }
      const valid = crypto.timingSafeEqual(Buffer.from(pin), Buffer.from(storedPin));
      if (valid) {
        failedAttempts = 0;
        return { configured: true, valid: true };
      }

      failedAttempts += 1;
      if (failedAttempts >= MAX_FAILED_ATTEMPTS) {
        failedAttempts = 0;
        lockedUntil = now() + LOCKOUT_MS;
        return { configured: true, valid: false, retryAfterSeconds: LOCKOUT_MS / 1000 };
      }
      return {
        configured: true,
        valid: false,
        attemptsRemaining: MAX_FAILED_ATTEMPTS - failedAttempts,
      };
    },
  });
}

function ensureEncryptionAvailable(safeStorage) {
  if (!safeStorage || typeof safeStorage.isEncryptionAvailable !== "function" || !safeStorage.isEncryptionAvailable()) {
    throw new Error("El almacenamiento protegido de Windows no está disponible.");
  }
}

function validateUserId(userId) {
  if (typeof userId !== "string" || userId.length < 1 || userId.length > 128) {
    throw new TypeError("La cuenta de Google no es válida para configurar el PIN.");
  }
}

function validatePin(pin) {
  if (typeof pin !== "string" || !PIN_PATTERN.test(pin)) {
    throw new TypeError("El PIN debe tener exactamente cuatro cifras.");
  }
}

module.exports = { createPinStore };
