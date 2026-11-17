import assert from "node:assert/strict";
import test from "node:test";
import { webcrypto } from "node:crypto";
import {
  fingerprintEncryptedCredential,
  scanPasswordExposure,
} from "../../desktop/ui/password-exposure.js";

globalThis.crypto ??= webcrypto;

test("sends a five-character hash prefix and matches the suffix locally", async () => {
  const result = await scanPasswordExposure({
    userId: "user",
    credentials: [{ id: "one", password: "password", revision: "cipher-1" }],
    storage: new MemoryStorage(),
    fetchImpl: async (url, options) => {
      assert.equal(url, "https://api.pwnedpasswords.com/range/5BAA6");
      assert.equal(options.headers["Add-Padding"], "true");
      assert.equal(url.includes("1E4"), false);
      return new Response(
        "OTHER:8\r\n1E4C9B93F3F0682250B6CF8331B7EE68FD8:7\r\n",
        { status: 200 },
      );
    },
    now: Date.UTC(2026, 0, 1),
  });

  assert.equal(result.counts.one, 7);
  assert.deepEqual(result.newlyExposedIds, ["one"]);
});

test("stores no password or full password hash in local scan state", async () => {
  const storage = new MemoryStorage();
  await scanPasswordExposure({
    userId: "user",
    credentials: [{ id: "one", password: "password", revision: "cipher-1" }],
    storage,
    fetchImpl: async () => new Response("", { status: 200 }),
    now: Date.UTC(2026, 0, 1),
  });

  assert.equal(storage.value.includes("password"), false);
  assert.equal(storage.value.includes("5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8"), false);
});

test("checks changed passwords immediately and scans all credentials weekly", async () => {
  const storage = new MemoryStorage();
  const checked = [];
  const fetchImpl = async (url) => {
    checked.push(url);
    return new Response("", { status: 200 });
  };
  const firstTime = Date.UTC(2026, 0, 1);
  const original = [{ id: "one", password: "password", revision: "cipher-1" }];

  await scanPasswordExposure({
    userId: "user",
    credentials: original,
    storage,
    fetchImpl,
    now: firstTime,
  });
  await scanPasswordExposure({
    userId: "user",
    credentials: [{ id: "one", password: "changed", revision: "cipher-2" }],
    storage,
    fetchImpl,
    now: firstTime + 24 * 60 * 60 * 1000,
  });
  await scanPasswordExposure({
    userId: "user",
    credentials: [{ id: "one", password: "changed", revision: "cipher-2" }],
    storage,
    fetchImpl,
    now: firstTime + 7 * 24 * 60 * 60 * 1000,
  });

  assert.equal(checked.length, 3);
});

test("fingerprints encrypted data without using the password", async () => {
  const first = await fingerprintEncryptedCredential({
    version: 1,
    ciphertext: "encrypted-a",
    iv: "nonce-a",
  });
  const same = await fingerprintEncryptedCredential({
    iv: "nonce-a",
    ciphertext: "encrypted-a",
    version: 1,
  });
  const changed = await fingerprintEncryptedCredential({
    version: 1,
    ciphertext: "encrypted-b",
    iv: "nonce-a",
  });

  assert.equal(first, same);
  assert.notEqual(first, changed);
});

class MemoryStorage {
  value = null;

  getItem(key) {
    assert.equal(key, "password-exposure-v1:user");
    return this.value;
  }

  setItem(key, value) {
    assert.equal(key, "password-exposure-v1:user");
    this.value = value;
  }
}
