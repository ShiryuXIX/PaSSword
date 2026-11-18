const PBKDF2_ITERATIONS = 600_000;
const SALT_BYTES = 16;
const IV_BYTES = 12;
const TEXT_ENCODER = new TextEncoder();

export { PBKDF2_ITERATIONS };

export function createVaultSalt() {
  return crypto.getRandomValues(new Uint8Array(SALT_BYTES));
}

export function encodeVaultBytes(bytes) {
  if (!(bytes instanceof Uint8Array)) {
    throw new TypeError("El valor criptográfico no es válido.");
  }
  return encodeBase64(bytes);
}

export function decodeVaultBytes(value) {
  if (typeof value !== "string") {
    throw new TypeError("El valor criptográfico no es válido.");
  }
  return decodeBase64(value);
}

export function decodeVaultRecoveryKey(document) {
  if (
    !document
    || Object.keys(document).length !== 2
    || document.version !== 1
    || typeof document.key !== "string"
  ) {
    throw new Error("La llave de recuperación de Google está dañada o no es compatible.");
  }

  const key = decodeVaultBytes(document.key);
  if (key.length !== 32) {
    key.fill(0);
    throw new Error("La llave de recuperación de Google tiene un tamaño no válido.");
  }
  return key;
}

export async function createVaultVerifier(key, ownerId) {
  validateContext(ownerId, "verifier");
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const ciphertext = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv,
      additionalData: TEXT_ENCODER.encode(`boveda:verifier:v1:${ownerId}`),
      tagLength: 128,
    },
    key,
    TEXT_ENCODER.encode("boveda-vault-verifier-v1"),
  );

  return {
    iv: encodeBase64(iv),
    ciphertext: encodeBase64(new Uint8Array(ciphertext)),
  };
}

export async function verifyVaultKey(key, ownerId, verifier) {
  validateContext(ownerId, "verifier");

  try {
    if (
      !verifier
      || typeof verifier.iv !== "string"
      || typeof verifier.ciphertext !== "string"
    ) {
      return false;
    }

    const plaintext = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: decodeBase64(verifier.iv),
        additionalData: TEXT_ENCODER.encode(`boveda:verifier:v1:${ownerId}`),
        tagLength: 128,
      },
      key,
      decodeBase64(verifier.ciphertext),
    );
    const plaintextBytes = new Uint8Array(plaintext);
    const valid = new TextDecoder("utf-8", { fatal: true }).decode(plaintextBytes)
      === "boveda-vault-verifier-v1";
    plaintextBytes.fill(0);
    return valid;
  } catch {
    return false;
  }
}

export async function deriveVaultKey(masterPassword, salt) {
  const keyMaterial = await deriveVaultKeyMaterial(masterPassword, salt);
  try {
    return await importVaultKeyMaterial(keyMaterial);
  } finally {
    keyMaterial.fill(0);
  }
}

export async function deriveVaultKeyMaterial(masterPassword, salt) {
  if (typeof masterPassword !== "string" || masterPassword.length === 0 || masterPassword.length > 1024) {
    throw new TypeError("La clave de recuperación no es válida.");
  }
  if (!(salt instanceof Uint8Array) || salt.length !== SALT_BYTES) {
    throw new TypeError("La configuración criptográfica de PaSSword no es válida.");
  }

  const passwordBytes = TEXT_ENCODER.encode(masterPassword.normalize("NFKC"));
  try {
    const passwordKey = await crypto.subtle.importKey(
      "raw",
      passwordBytes,
      "PBKDF2",
      false,
      ["deriveBits"],
    );
    return new Uint8Array(await crypto.subtle.deriveBits(
      {
        name: "PBKDF2",
        hash: "SHA-256",
        salt,
        iterations: PBKDF2_ITERATIONS,
      },
      passwordKey,
      256,
    ));
  } finally {
    passwordBytes.fill(0);
  }
}

export async function importVaultKeyMaterial(keyMaterial) {
  if (!(keyMaterial instanceof Uint8Array) || keyMaterial.length !== 32) {
    throw new TypeError("El material de la llave de PaSSword no es válido.");
  }

  return crypto.subtle.importKey(
    "raw",
    keyMaterial,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}

export async function encryptCredential(key, ownerId, credentialId, credential, keyGeneration = 1) {
  validateContext(ownerId, credentialId);
  validateCredential(credential);
  validateKeyGeneration(keyGeneration);

  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const plaintext = TEXT_ENCODER.encode(JSON.stringify(credential));
  let encrypted;
  try {
    encrypted = await crypto.subtle.encrypt(
      {
        name: "AES-GCM",
        iv,
        additionalData: additionalData(ownerId, credentialId, keyGeneration),
        tagLength: 128,
      },
      key,
      plaintext,
    );
  } finally {
    plaintext.fill(0);
  }

  return {
    version: 1,
    keyGeneration,
    iv: encodeBase64(iv),
    ciphertext: encodeBase64(new Uint8Array(encrypted)),
  };
}

export async function decryptCredential(key, ownerId, credentialId, document) {
  validateContext(ownerId, credentialId);

  try {
    if (!document || document.version !== 1 || typeof document.iv !== "string" || typeof document.ciphertext !== "string") {
      throw new TypeError("El documento cifrado no tiene un formato válido.");
    }

    const keyGeneration = document.keyGeneration;
    if (keyGeneration !== undefined) {
      validateKeyGeneration(keyGeneration);
    }
    const iv = decodeBase64(document.iv);
    const ciphertext = decodeBase64(document.ciphertext);
    if (iv.length !== IV_BYTES || ciphertext.length <= 16) {
      throw new TypeError("El documento cifrado no tiene un tamaño válido.");
    }

    const plaintext = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv,
        additionalData: keyGeneration === undefined
          ? legacyAdditionalData(ownerId, credentialId)
          : additionalData(ownerId, credentialId, keyGeneration),
        tagLength: 128,
      },
      key,
      ciphertext,
    );
    const plaintextBytes = new Uint8Array(plaintext);
    try {
      const decoded = new TextDecoder("utf-8", { fatal: true }).decode(plaintextBytes);
      const credential = JSON.parse(decoded);
      validateCredential(credential);
      return credential;
    } finally {
      plaintextBytes.fill(0);
    }
  } catch {
    throw new Error("No se pudo descifrar el acceso. La clave de recuperación puede ser incorrecta o el acceso estar dañado.");
  }
}

function validateContext(ownerId, credentialId) {
  if (
    typeof ownerId !== "string"
    || ownerId.length === 0
    || ownerId.length > 128
    || typeof credentialId !== "string"
    || credentialId.length === 0
    || credentialId.length > 128
  ) {
    throw new TypeError("El identificador del acceso no es válido.");
  }
}

function validateKeyGeneration(keyGeneration) {
  if (!Number.isSafeInteger(keyGeneration) || keyGeneration < 1 || keyGeneration > 2_147_483_647) {
    throw new TypeError("La generación de clave de PaSSword no es válida.");
  }
}

function validateCredential(credential) {
  if (!credential || typeof credential !== "object" || Array.isArray(credential)) {
    throw new TypeError("El acceso no tiene un formato válido.");
  }

  const keys = Object.keys(credential).sort();
  if (
    keys.length !== 3
    || keys[0] !== "email"
    || keys[1] !== "password"
    || keys[2] !== "site"
    || typeof credential.site !== "string"
    || typeof credential.email !== "string"
    || typeof credential.password !== "string"
  ) {
    throw new TypeError("Cada acceso debe contener sitio web, email y contraseña.");
  }
}

function additionalData(ownerId, credentialId, keyGeneration) {
  return TEXT_ENCODER.encode(`boveda:credential:v2:${ownerId}:${credentialId}:${keyGeneration}`);
}

function legacyAdditionalData(ownerId, credentialId) {
  return TEXT_ENCODER.encode(`boveda:credential:v1:${ownerId}:${credentialId}`);
}

function encodeBase64(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function decodeBase64(value) {
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    throw new TypeError("El documento cifrado no tiene una codificación válida.");
  }

  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
