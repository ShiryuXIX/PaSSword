import assert from "node:assert/strict";
import { initializeApp, deleteApp } from "firebase/app";
import {
  connectAuthEmulator,
  getAuth,
  signInAnonymously,
} from "firebase/auth";
import {
  connectFirestoreEmulator,
  deleteDoc,
  doc,
  getFirestore,
  getDocFromServer,
  runTransaction,
  setDoc,
  updateDoc,
} from "firebase/firestore";

const projectId = "demo-password-recovery";
const apps = [];

async function createTestUser(name) {
  const app = initializeApp(
    { apiKey: "demo-key", authDomain: "localhost", projectId },
    name,
  );
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  const db = getFirestore(app);
  connectFirestoreEmulator(db, "127.0.0.1", 8080);
  const { user } = await signInAnonymously(auth);
  return { db, uid: user.uid };
}

function metadata() {
  return {
    version: 1,
    kdf: "RANDOM-AES-256",
    iterations: 0,
    keyGeneration: 1,
    salt: Buffer.alloc(16).toString("base64"),
    verifier: {
      iv: Buffer.alloc(12).toString("base64"),
      ciphertext: Buffer.alloc(32).toString("base64"),
    },
  };
}

async function expectPermissionDenied(operation) {
  await assert.rejects(operation, (error) => error.code === "permission-denied");
}

try {
  const owner = await createTestUser("owner");
  const other = await createTestUser("other");
  const metadataRef = doc(owner.db, "users", owner.uid, "vault", "meta");
  const recoveryRef = doc(owner.db, "users", owner.uid, "vault", "recovery");
  const recoveryKey = {
    version: 1,
    key: Buffer.alloc(32, 7).toString("base64"),
  };

  await runTransaction(owner.db, async (transaction) => {
    transaction.set(metadataRef, metadata());
    transaction.set(recoveryRef, recoveryKey);
  });

  const savedKey = await getDocFromServer(recoveryRef);
  assert.equal(savedKey.data().key, recoveryKey.key);

  await expectPermissionDenied(() =>
    getDocFromServer(doc(other.db, "users", owner.uid, "vault", "recovery")),
  );
  await expectPermissionDenied(() => updateDoc(recoveryRef, { key: "AA==" }));
  await expectPermissionDenied(() => deleteDoc(recoveryRef));
  await expectPermissionDenied(() => updateDoc(metadataRef, { keyGeneration: 2 }));
  await expectPermissionDenied(() => updateDoc(metadataRef, {
    rotationInProgress: true,
    rotationId: "12345678-1234-1234-1234-123456789012",
  }));
  await expectPermissionDenied(() => setDoc(
    doc(other.db, "users", other.uid, "vault", "meta"),
    metadata(),
  ));
} finally {
  await Promise.all(apps.map((app) => deleteApp(app)));
}
