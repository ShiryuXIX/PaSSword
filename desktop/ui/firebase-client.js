import { initializeApp } from "firebase/app";
import {
  browserPopupRedirectResolver,
  getAuth,
  getRedirectResult,
  GoogleAuthProvider,
  indexedDBLocalPersistence,
  initializeAuth,
  onAuthStateChanged,
  signInWithCredential,
  signInWithPopup,
  signInWithRedirect,
  signOut,
} from "firebase/auth";
import {
  collection,
  deleteField,
  deleteDoc,
  doc,
  getDocFromCache,
  getDocFromServer,
  getDocsFromServer,
  initializeFirestore,
  onSnapshot,
  persistentLocalCache,
  persistentMultipleTabManager,
  query,
  runTransaction,
  setDoc,
} from "firebase/firestore";
import { firebaseConfig } from "./firebase-config.js";
import {
  PBKDF2_ITERATIONS,
  decodeVaultBytes,
  decodeVaultRecoveryKey,
  decryptCredential,
  encodeVaultBytes,
  encryptCredential,
} from "./vault-crypto.js";

export const KDF_NAME = "PBKDF2-SHA-256";
export const RECOVERY_KEY_MODE = "RANDOM-AES-256";
const MAX_ATOMIC_KEY_ROTATION_CREDENTIALS = 249;
export const app = initializeApp(firebaseConfig);
export const auth = initializeAuth(app, {
  persistence: [indexedDBLocalPersistence],
  popupRedirectResolver: browserPopupRedirectResolver,
});
export const db = initializeFirestore(app, {
  localCache: persistentLocalCache({
    tabManager: persistentMultipleTabManager(),
  }),
});

const googleProvider = new GoogleAuthProvider();

export function observeAuth(callback, onError) {
  return onAuthStateChanged(auth, callback, onError);
}

export function getSignInRedirectResult() {
  return getRedirectResult(auth);
}

export async function signInWithGoogle() {
  if (globalThis.bovedaDesktop) {
    let response;
    try {
      response = await globalThis.bovedaDesktop.signInWithGoogle();
    } catch (error) {
      const wrapped = annotateSignInFailure(error, "oauth", "desktop/oauth-bridge-failed");
      wrapped.diagnosticDetail = error?.diagnosticDetail;
      throw wrapped;
    }
    if (response?.error) {
      const error = new Error(
        typeof response.error.message === "string"
          ? response.error.message
          : "No se pudo completar el inicio de sesión con Google.",
      );
      error.code = typeof response.error.code === "string"
        && /^(auth|desktop)\/[a-z0-9-]{1,80}$/.test(response.error.code)
        ? response.error.code
        : "desktop/oauth-bridge-failed";
      error.diagnosticDetail = response.error.diagnosticDetail;
      error.signInStage = "oauth";
      throw error;
    }
    const idToken = response?.idToken;
    if (typeof idToken !== "string" || idToken.length === 0) {
      const error = new Error("La autenticación de escritorio no devolvió una identidad válida.");
      error.code = "desktop/oauth-identity-invalid";
      error.signInStage = "oauth";
      throw error;
    }
    try {
      return await signInWithCredential(
        auth,
        GoogleAuthProvider.credential(idToken),
      );
    } catch (error) {
      throw annotateSignInFailure(error, "firebase", "auth/unknown-error");
    }
  }

  try {
    return await signInWithPopup(auth, googleProvider);
  } catch (error) {
    if (
      error.code === "auth/popup-blocked"
      || error.code === "auth/operation-not-supported-in-this-environment"
      || error.code === "auth/web-storage-unsupported"
    ) {
      await signInWithRedirect(auth, googleProvider);
      return null;
    }
    throw error;
  }
}

function annotateSignInFailure(error, stage, fallbackCode) {
  const wrapped = new Error("No se pudo completar el inicio de sesión.", { cause: error });
  wrapped.code = typeof error?.code === "string" ? error.code : fallbackCode;
  wrapped.signInStage = stage;
  return wrapped;
}

export function signOutUser() {
  return signOut(auth);
}

function vaultMetadataRef(uid) {
  return doc(db, "users", uid, "vault", "meta");
}

function vaultRecoveryRef(uid) {
  return doc(db, "users", uid, "vault", "recovery");
}

function credentialsCollectionRef(uid) {
  return collection(db, "users", uid, "credentials");
}

export async function readVaultMetadata(uid) {
  const reference = vaultMetadataRef(uid);

  if (navigator.onLine) {
    try {
      const snapshot = await getDocFromServer(reference);
      return snapshot.exists() ? snapshot.data() : null;
    } catch (error) {
      if (!["unavailable", "deadline-exceeded"].includes(error?.code)) {
        throw error;
      }
    }
  }

  let snapshot;
  try {
    snapshot = await getDocFromCache(reference);
  } catch {
    throw new Error("No hay datos de PaSSword disponibles sin conexión. Conéctate y vuelve a intentarlo.");
  }
  return snapshot.exists() ? snapshot.data() : null;
}

export async function readVaultRecoveryKey(uid) {
  const reference = vaultRecoveryRef(uid);

  if (navigator.onLine) {
    try {
      const snapshot = await getDocFromServer(reference);
      return snapshot.exists() ? decodeVaultRecoveryKey(snapshot.data()) : null;
    } catch (error) {
      if (!["unavailable", "deadline-exceeded"].includes(error?.code)) {
        throw error;
      }
    }
  }

  let snapshot;
  try {
    snapshot = await getDocFromCache(reference);
  } catch (error) {
    if (["failed-precondition", "unavailable"].includes(error?.code)) {
      return null;
    }
    throw error;
  }
  return snapshot.exists() ? decodeVaultRecoveryKey(snapshot.data()) : null;
}

export async function createVaultMetadata(uid, salt, verifier, recoveryKey) {
  if (!navigator.onLine) {
    throw new Error("Necesitas conexión para configurar PaSSword por primera vez.");
  }
  if (!(recoveryKey instanceof Uint8Array) || recoveryKey.length !== 32) {
    throw new TypeError("La llave de recuperación de PaSSword no es válida.");
  }

  const reference = vaultMetadataRef(uid);
  const recoveryReference = vaultRecoveryRef(uid);
  await runTransaction(db, async (transaction) => {
    const existing = await transaction.get(reference);
    const existingRecoveryKey = await transaction.get(recoveryReference);
    if (existing.exists() || existingRecoveryKey.exists()) {
      throw new Error("PaSSword ya está configurado. Vuelve a cargar sus datos e intenta desbloquearlo.");
    }

    transaction.set(reference, {
      version: 1,
      kdf: RECOVERY_KEY_MODE,
      iterations: 0,
      keyGeneration: 1,
      salt: encodeVaultBytes(salt),
      verifier,
    });
    transaction.set(recoveryReference, {
      version: 1,
      key: encodeVaultBytes(recoveryKey),
    });
  });
}

export async function saveVaultRecoveryKeyIfAbsent(uid, recoveryKey, expectedMetadata) {
  if (!navigator.onLine) {
    throw new Error("Conéctate para activar la recuperación de esta bóveda.");
  }
  if (!(recoveryKey instanceof Uint8Array) || recoveryKey.length !== 32) {
    throw new TypeError("La llave de recuperación de PaSSword no es válida.");
  }

  const reference = vaultRecoveryRef(uid);
  const metadataReference = vaultMetadataRef(uid);
  await runTransaction(db, async (transaction) => {
    const metadataSnapshot = await transaction.get(metadataReference);
    const existing = await transaction.get(reference);
    if (!metadataSnapshot.exists()) {
      const error = new Error("No se encontró la configuración de PaSSword.");
      error.code = "vault/metadata-changed";
      throw error;
    }
    const metadata = metadataSnapshot.data();
    try {
      assertExpectedVaultMetadata(metadata, expectedMetadata);
    } catch (error) {
      error.code = "vault/metadata-changed";
      throw error;
    }
    if (metadata.rotationInProgress === true) {
      const error = new Error("La bóveda se está actualizando desde otro dispositivo.");
      error.code = "vault/metadata-changed";
      throw error;
    }
    if (existing.exists()) {
      const storedKey = decodeVaultRecoveryKey(existing.data());
      let difference = 0;
      for (let index = 0; index < storedKey.length; index += 1) {
        difference |= storedKey[index] ^ recoveryKey[index];
      }
      storedKey.fill(0);
      if (difference !== 0) {
        throw new Error("Ya hay una llave de recuperación distinta para esta cuenta.");
      }
      return;
    }
    transaction.set(reference, {
      version: 1,
      key: encodeVaultBytes(recoveryKey),
    });
  });
}

export async function reencryptVault(uid, expectedMetadata, oldKey, newKey, salt, verifier) {
  if (!navigator.onLine) {
    throw new Error("Necesitas conexión para cambiar la clave de recuperación.");
  }

  const metadataReference = vaultMetadataRef(uid);
  const credentialsQuery = query(credentialsCollectionRef(uid));
  const expectedGeneration = expectedMetadata.keyGeneration ?? 1;
  if (expectedGeneration >= 2_147_483_647) {
    throw new Error("Se alcanzó el límite de cambios de clave de PaSSword. No se cambió nada.");
  }

  const rotationId = crypto.randomUUID();
  try {
    await runTransaction(db, async (transaction) => {
      const metadataSnapshot = await transaction.get(metadataReference);
      if (!metadataSnapshot.exists()) {
        throw new Error("No se encontró la configuración de PaSSword. No se cambió nada.");
      }

      const metadata = metadataSnapshot.data();
      assertExpectedVaultMetadata(metadata, expectedMetadata);
      transaction.update(metadataReference, {
        rotationInProgress: true,
        rotationId,
      });
    });

    const credentialsSnapshot = await getDocsFromServer(credentialsQuery);
    const items = credentialsSnapshot.docs;
    if (items.length > MAX_ATOMIC_KEY_ROTATION_CREDENTIALS) {
      throw new Error("PaSSword supera el límite de 249 accesos para un cambio atómico. No se cambió nada.");
    }

    const nextGeneration = expectedGeneration + 1;
    const encryptedDocuments = [];
    for (const item of items) {
      const plaintext = await decryptCredential(oldKey, uid, item.id, item.data());
      const reference = doc(credentialsCollectionRef(uid));
      const encrypted = await encryptCredential(newKey, uid, reference.id, plaintext, nextGeneration);
      encryptedDocuments.push({ oldReference: item.ref, reference, encrypted });
    }

    await runTransaction(db, async (transaction) => {
      const metadataSnapshot = await transaction.get(metadataReference);
      if (!metadataSnapshot.exists()) {
        throw new Error("No se encontró la configuración de PaSSword. No se cambió nada.");
      }

      const metadata = metadataSnapshot.data();
      assertExpectedVaultMetadata(metadata, expectedMetadata);
      if (!metadata.rotationInProgress || metadata.rotationId !== rotationId) {
        throw new Error("El cambio fue sustituido en otro dispositivo. Recarga PaSSword antes de volver a intentarlo.");
      }

      for (const item of encryptedDocuments) {
        transaction.set(item.reference, item.encrypted);
        transaction.delete(item.oldReference);
      }
      transaction.set(metadataReference, {
        version: 1,
        kdf: KDF_NAME,
        iterations: PBKDF2_ITERATIONS,
        keyGeneration: nextGeneration,
        salt: encodeVaultBytes(salt),
        verifier,
      });
    });

    return { keyGeneration: nextGeneration, credentialCount: items.length };
  } catch (error) {
    try {
      await runTransaction(db, async (transaction) => {
        const metadataSnapshot = await transaction.get(metadataReference);
        if (!metadataSnapshot.exists()) {
          return;
        }

        const metadata = metadataSnapshot.data();
        if (
          metadata.rotationInProgress
          && metadata.rotationId === rotationId
          && (metadata.keyGeneration ?? 1) === expectedGeneration
        ) {
          transaction.update(metadataReference, {
            rotationInProgress: false,
            rotationId: deleteField(),
          });
        }
      });
    } catch (releaseError) {
      throw new AggregateError(
        [error, releaseError],
        "No se pudo completar ni liberar la rotación. Vuelve a intentarlo con conexión.",
      );
    }
    throw error;
  }
}

function assertExpectedVaultMetadata(metadata, expectedMetadata) {
  if (
    metadata.version !== expectedMetadata.version
    || metadata.kdf !== expectedMetadata.kdf
    || metadata.iterations !== expectedMetadata.iterations
    || metadata.salt !== expectedMetadata.salt
    || metadata.verifier?.iv !== expectedMetadata.verifier?.iv
    || metadata.verifier?.ciphertext !== expectedMetadata.verifier?.ciphertext
    || (metadata.keyGeneration ?? 1) !== (expectedMetadata.keyGeneration ?? 1)
  ) {
    throw new Error("PaSSword cambió en otro dispositivo. Recárgalo y desbloquéalo antes de volver a intentarlo.");
  }
}

export function watchVaultCredentials(uid, callback, onError) {
  const credentialsQuery = query(credentialsCollectionRef(uid));
  return onSnapshot(
    credentialsQuery,
    { includeMetadataChanges: true },
    (snapshot) => {
      callback(
        snapshot.docs.map((item) => ({
          id: item.id,
          document: item.data(),
          hasPendingWrites: item.metadata.hasPendingWrites,
        })),
        snapshot.metadata.fromCache,
      );
    },
    onError,
  );
}

export function saveEncryptedCredential(uid, credentialId, encryptedDocument) {
  return setDoc(
    doc(db, "users", uid, "credentials", credentialId),
    encryptedDocument,
  );
}

export function deleteEncryptedCredential(uid, credentialId) {
  return deleteDoc(doc(db, "users", uid, "credentials", credentialId));
}

export function decodeVaultSalt(metadata) {
  if (
    metadata?.version !== 1
    || metadata.kdf !== KDF_NAME
    || metadata.iterations !== PBKDF2_ITERATIONS
    || typeof metadata.salt !== "string"
  ) {
    throw new Error("La configuración de PaSSword no es compatible.");
  }

  const salt = decodeVaultBytes(metadata.salt);
  if (salt.length !== 16) {
    throw new Error("La configuración de PaSSword está dañada.");
  }
  return salt;
}

export function validateVaultVerifier(metadata) {
  const verifier = metadata?.verifier;
  if (
    !verifier
    || typeof verifier.iv !== "string"
    || typeof verifier.ciphertext !== "string"
  ) {
    throw new Error("La configuración de PaSSword está dañada.");
  }
  return verifier;
}

export function getVaultKeyGeneration(metadata) {
  const generation = metadata?.keyGeneration ?? 1;
  if (!Number.isSafeInteger(generation) || generation < 1 || generation > 2_147_483_647) {
    throw new Error("La configuración de PaSSword está dañada.");
  }
  return generation;
}
