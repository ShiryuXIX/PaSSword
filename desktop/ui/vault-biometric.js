import { importVaultKeyMaterial } from "./vault-crypto.js";

const PRF_SALT_BYTES = 32;
const CHALLENGE_BYTES = 32;
const IV_BYTES = 12;
const KEY_BYTES = 32;
const TEXT_ENCODER = new TextEncoder();

export async function isBiometricUnlockAvailable() {
  if (
    !globalThis.isSecureContext
    || !globalThis.navigator?.credentials?.create
    || !globalThis.navigator?.credentials?.get
    || typeof globalThis.PublicKeyCredential?.isUserVerifyingPlatformAuthenticatorAvailable !== "function"
  ) {
    return false;
  }

  try {
    return await globalThis.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
  } catch (error) {
    if (error.name === "NotSupportedError" || error.name === "SecurityError") {
      return false;
    }
    throw error;
  }
}

export async function createBiometricVaultRecord(userId, keyMaterial, keyGeneration) {
  validateUserId(userId);
  validateKeyMaterial(keyMaterial);
  validateKeyGeneration(keyGeneration);
  if (!await isBiometricUnlockAvailable()) {
    throw new Error("Este navegador no ofrece autenticación biométrica segura en el dispositivo.");
  }

  const prfSalt = crypto.getRandomValues(new Uint8Array(PRF_SALT_BYTES));
  const challenge = crypto.getRandomValues(new Uint8Array(CHALLENGE_BYTES));
  const userHandle = crypto.getRandomValues(new Uint8Array(32));
  const credential = await navigator.credentials.create({
    publicKey: {
      challenge,
      rp: {
        id: location.hostname,
        name: "PaSSword",
      },
      user: {
        id: userHandle,
        name: "password-vault",
        displayName: "PaSSword",
      },
      pubKeyCredParams: [
        { type: "public-key", alg: -7 },
        { type: "public-key", alg: -257 },
      ],
      authenticatorSelection: {
        authenticatorAttachment: "platform",
        residentKey: "discouraged",
        userVerification: "required",
      },
      timeout: 60_000,
      attestation: "none",
      extensions: {
        prf: {
          eval: { first: prfSalt },
        },
      },
    },
  });

  if (!credential?.rawId || typeof credential.getClientExtensionResults !== "function") {
    throw new Error("El dispositivo no devolvió una credencial biométrica válida.");
  }

  let prfOutput = getPrfOutput(credential);
  if (!prfOutput) {
    prfOutput = await evaluateCredentialPrf(credential.rawId, prfSalt);
  }

  try {
    const wrappingKey = await importVaultKeyMaterial(prfOutput);
    const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
    const wrappedKey = new Uint8Array(await crypto.subtle.encrypt(
      {
        name: "AES-GCM",
        iv,
        additionalData: additionalData(userId),
        tagLength: 128,
      },
      wrappingKey,
      keyMaterial,
    ));

    return {
      credentialId: new Uint8Array(credential.rawId),
      prfSalt,
      iv,
      wrappedKey,
      keyGeneration,
    };
  } finally {
    prfOutput.fill(0);
  }
}

export async function unlockBiometricVaultKey(userId, record) {
  validateUserId(userId);
  validateBiometricRecord(record);

  const credential = await navigator.credentials.get({
    publicKey: {
      challenge: crypto.getRandomValues(new Uint8Array(CHALLENGE_BYTES)),
      rpId: location.hostname,
      allowCredentials: [{
        type: "public-key",
        id: record.credentialId,
      }],
      userVerification: "required",
      timeout: 60_000,
      extensions: {
        prf: {
          eval: { first: record.prfSalt },
        },
      },
    },
  });

  const prfOutput = getPrfOutput(credential);
  if (!prfOutput) {
    throw new Error("El dispositivo no devolvió la llave biométrica. Desbloquea con tu clave de recuperación.");
  }

  let keyMaterial;
  try {
    const wrappingKey = await importVaultKeyMaterial(prfOutput);
    keyMaterial = new Uint8Array(await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: record.iv,
        additionalData: additionalData(userId),
        tagLength: 128,
      },
      wrappingKey,
      record.wrappedKey,
    ));
    if (keyMaterial.length !== KEY_BYTES) {
      throw new Error("La llave biométrica guardada no tiene un formato válido.");
    }
    return await importVaultKeyMaterial(keyMaterial);
  } finally {
    prfOutput.fill(0);
    keyMaterial?.fill(0);
  }
}

function evaluateCredentialPrf(credentialId, prfSalt) {
  return navigator.credentials.get({
    publicKey: {
      challenge: crypto.getRandomValues(new Uint8Array(CHALLENGE_BYTES)),
      rpId: location.hostname,
      allowCredentials: [{
        type: "public-key",
        id: credentialId,
      }],
      userVerification: "required",
      timeout: 60_000,
      extensions: {
        prf: {
          eval: { first: prfSalt },
        },
      },
    },
  }).then((credential) => {
    const output = getPrfOutput(credential);
    if (!output) {
      throw new Error("Este dispositivo no admite llaves biométricas seguras. Puedes seguir usando la clave de recuperación.");
    }
    return output;
  });
}

function getPrfOutput(credential) {
  const result = credential?.getClientExtensionResults?.()?.prf?.results?.first;
  if (result instanceof ArrayBuffer) {
    return new Uint8Array(result);
  }
  if (ArrayBuffer.isView(result)) {
    return new Uint8Array(result.buffer, result.byteOffset, result.byteLength).slice();
  }
  return null;
}

function additionalData(userId) {
  return TEXT_ENCODER.encode(`password-vault:biometric:v1:${userId}`);
}

function validateUserId(userId) {
  if (typeof userId !== "string" || userId.length === 0 || userId.length > 128) {
    throw new TypeError("La cuenta de usuario no es válida para el desbloqueo biométrico.");
  }
}

function validateKeyMaterial(keyMaterial) {
  if (!(keyMaterial instanceof Uint8Array) || keyMaterial.length !== KEY_BYTES) {
    throw new TypeError("El material de la llave de PaSSword no es válido.");
  }
}

function validateKeyGeneration(keyGeneration) {
  if (!Number.isSafeInteger(keyGeneration) || keyGeneration < 1) {
    throw new TypeError("La generación de la llave de PaSSword no es válida.");
  }
}

function validateBiometricRecord(record) {
  if (
    !record
    || record.kind !== "webauthn-prf-v1"
    || !(record.credentialId instanceof Uint8Array)
    || record.credentialId.length < 16
    || record.credentialId.length > 1024
    || !(record.prfSalt instanceof Uint8Array)
    || record.prfSalt.length !== PRF_SALT_BYTES
    || !(record.iv instanceof Uint8Array)
    || record.iv.length !== IV_BYTES
    || !(record.wrappedKey instanceof Uint8Array)
    || record.wrappedKey.length !== KEY_BYTES + 16
    || !Number.isSafeInteger(record.keyGeneration)
    || record.keyGeneration < 1
  ) {
    throw new TypeError("El registro biométrico de PaSSword no es válido.");
  }
}
