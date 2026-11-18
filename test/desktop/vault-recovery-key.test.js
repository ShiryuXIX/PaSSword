import assert from "node:assert/strict";
import test from "node:test";
import { decodeVaultRecoveryKey } from "../../desktop/ui/vault-crypto.js";

test("decodes a versioned 256-bit recovery key", () => {
  const expected = Uint8Array.from({ length: 32 }, (_, index) => index);
  const recovered = decodeVaultRecoveryKey({
    version: 1,
    key: Buffer.from(expected).toString("base64"),
  });

  assert.deepEqual(recovered, expected);
});

test("rejects malformed, unsupported, or extra recovery-key fields", () => {
  assert.throws(() => decodeVaultRecoveryKey({ version: 2, key: "AA==" }));
  assert.throws(() => decodeVaultRecoveryKey({ version: 1, key: "AA==" }));
  assert.throws(() => decodeVaultRecoveryKey({
    version: 1,
    key: Buffer.alloc(32).toString("base64"),
    extra: true,
  }));
  assert.throws(() => decodeVaultRecoveryKey({ version: 1, key: "not-base64!" }));
});
