const DATABASE_NAME = "password-vault-local";
const DATABASE_VERSION = 1;
const STORE_NAME = "vault-keys";
let databasePromise;

export async function loadRememberedVaultKey(userId) {
  validateUserId(userId);
  const database = await openDatabase();
  const transaction = database.transaction(STORE_NAME, "readonly");
  const request = transaction.objectStore(STORE_NAME).get(userId);
  const record = await requestResult(request);
  await transactionComplete(transaction);

  if (!record || record.kind === "webauthn-prf-v1") {
    return null;
  }
  validateVaultKey(record.key);
  return record.key;
}

export async function loadBiometricVaultRecord(userId) {
  validateUserId(userId);
  const database = await openDatabase();
  const transaction = database.transaction(STORE_NAME, "readonly");
  const request = transaction.objectStore(STORE_NAME).get(userId);
  const record = await requestResult(request);
  await transactionComplete(transaction);

  if (!record || record.kind !== "webauthn-prf-v1") {
    return null;
  }
  validateBiometricVaultRecord(record);
  return record;
}

export async function saveRememberedVaultKey(userId, key) {
  validateUserId(userId);
  validateVaultKey(key);
  const database = await openDatabase();
  const transaction = database.transaction(STORE_NAME, "readwrite");
  const request = transaction.objectStore(STORE_NAME).put({ userId, key });
  await Promise.all([
    requestResult(request),
    transactionComplete(transaction),
  ]);
}

export async function saveBiometricVaultRecord(userId, record) {
  validateUserId(userId);
  const storedRecord = { ...record, userId, kind: "webauthn-prf-v1" };
  validateBiometricVaultRecord(storedRecord);
  const database = await openDatabase();
  const transaction = database.transaction(STORE_NAME, "readwrite");
  const request = transaction.objectStore(STORE_NAME).put(storedRecord);
  await Promise.all([
    requestResult(request),
    transactionComplete(transaction),
  ]);
}

export async function forgetRememberedVaultKey(userId) {
  validateUserId(userId);
  const database = await openDatabase();
  const transaction = database.transaction(STORE_NAME, "readwrite");
  const request = transaction.objectStore(STORE_NAME).delete(userId);
  await Promise.all([
    requestResult(request),
    transactionComplete(transaction),
  ]);
}

function openDatabase() {
  if (!globalThis.indexedDB) {
    return Promise.reject(new Error("Este navegador no permite recordar la llave de PaSSword."));
  }
  if (databasePromise) {
    return databasePromise;
  }

  databasePromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(STORE_NAME)) {
        request.result.createObjectStore(STORE_NAME, { keyPath: "userId" });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error("No se pudo abrir el almacenamiento local de la llave."));
    request.onblocked = () => reject(new Error("El almacenamiento local de la llave está bloqueado por otra pestaña."));
  }).catch((error) => {
    databasePromise = null;
    throw error;
  });

  return databasePromise;
}

function requestResult(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error("No se pudo acceder a la llave guardada."));
  });
}

function transactionComplete(transaction) {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = resolve;
    transaction.onerror = () => reject(transaction.error || new Error("No se pudo guardar la llave local."));
    transaction.onabort = () => reject(transaction.error || new Error("Se canceló el almacenamiento de la llave local."));
  });
}

function validateUserId(userId) {
  if (typeof userId !== "string" || userId.length === 0 || userId.length > 128) {
    throw new TypeError("La cuenta de usuario no es válida para el almacenamiento local.");
  }
}

function validateVaultKey(key) {
  if (
    !key
    || key.type !== "secret"
    || key.extractable !== false
    || key.algorithm?.name !== "AES-GCM"
    || key.algorithm.length !== 256
    || !key.usages.includes("encrypt")
    || !key.usages.includes("decrypt")
  ) {
    throw new TypeError("La llave local de PaSSword no es válida.");
  }
}

function validateBiometricVaultRecord(record) {
  if (
    !record
    || record.kind !== "webauthn-prf-v1"
    || !(record.credentialId instanceof Uint8Array)
    || record.credentialId.length < 16
    || record.credentialId.length > 1024
    || !(record.prfSalt instanceof Uint8Array)
    || record.prfSalt.length !== 32
    || !(record.iv instanceof Uint8Array)
    || record.iv.length !== 12
    || !(record.wrappedKey instanceof Uint8Array)
    || record.wrappedKey.length !== 48
    || !Number.isSafeInteger(record.keyGeneration)
    || record.keyGeneration < 1
  ) {
    throw new TypeError("El registro biométrico de PaSSword no es válido.");
  }
}
