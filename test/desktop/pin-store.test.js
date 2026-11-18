import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { afterEach, test } from "node:test";

const require = createRequire(import.meta.url);
const { createPinStore } = require("../../desktop/pin-store.cjs");
const temporaryDirectories = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((directory) =>
      rm(directory, { recursive: true, force: true }),
    ),
  );
});

async function createStore() {
  const directory = await mkdtemp(path.join(os.tmpdir(), "password-pin-"));
  temporaryDirectories.push(directory);
  const safeStorage = {
    isEncryptionAvailable: () => true,
    encryptString: (value) => Buffer.from(value),
    decryptString: (value) => value.toString("utf8"),
  };
  return createPinStore({
    filePath: path.join(directory, "pin.json"),
    safeStorage,
  });
}

test("accepts four- and six-digit PINs", async () => {
  const store = await createStore();
  await store.setPin("user-1", "1234");
  assert.deepEqual(await store.verifyPin("user-1", "1234"), {
    configured: true,
    valid: true,
  });

  await store.setPin("user-1", "123456");
  assert.deepEqual(await store.verifyPin("user-1", "123456"), {
    configured: true,
    valid: true,
  });
});

test("rejects PINs shorter than four or longer than six digits", async () => {
  const store = await createStore();
  await assert.rejects(store.setPin("user-1", "123"), TypeError);
  await assert.rejects(store.setPin("user-1", "1234567"), TypeError);
});

test("forgets the configured PIN for recovery", async () => {
  const store = await createStore();
  await store.setPin("user-1", "1234");
  await store.forgetPin("user-1");
  assert.deepEqual(await store.verifyPin("user-1", "1234"), {
    configured: false,
    valid: false,
  });
});

test("does not remove another account's PIN", async () => {
  const store = await createStore();
  await store.setPin("user-1", "1234");
  await store.forgetPin("user-2");
  assert.deepEqual(await store.verifyPin("user-1", "1234"), {
    configured: true,
    valid: true,
  });
});
