import {
  createVaultSalt,
  createVaultVerifier,
  decryptCredential,
  deriveVaultKey,
  deriveVaultKeyMaterial,
  encryptCredential,
  importVaultKeyMaterial,
  verifyVaultKey,
} from "./vault-crypto.js";
import {
  forgetRememberedVaultKey,
  loadBiometricVaultRecord,
  loadRememberedVaultKey,
  saveBiometricVaultRecord,
  saveRememberedVaultKey,
} from "./vault-key-store.js";
import {
  createBiometricVaultRecord,
  isBiometricUnlockAvailable,
  unlockBiometricVaultKey,
} from "./vault-biometric.js";
import {
  fingerprintEncryptedCredential,
  scanPasswordExposure,
} from "./password-exposure.js";

const credentials = [];
const symbols = "!@#$%^&*()-_=+[]{}:,.?";
const characterSets = [
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
  "abcdefghijklmnopqrstuvwxyz",
  "0123456789",
  symbols,
];

const listElement = document.querySelector("#credential-items");
const emptyState = document.querySelector("#empty-state");
const detailPanel = document.querySelector("#detail-panel");
const contentGrid = document.querySelector(".content-grid");
const listToolbar = document.querySelector(".list-toolbar");
const detailPlaceholder = document.querySelector("#detail-placeholder");
const detailElement = document.querySelector("#credential-detail");
const dialog = document.querySelector("#credential-dialog");
const form = document.querySelector("#credential-form");
const masterPasswordForm = document.querySelector("#master-password-form");
const masterPasswordError = document.querySelector("#master-password-error");
const currentMasterPasswordInput = document.querySelector("#current-master-password");
const newMasterPasswordInput = document.querySelector("#new-master-password");
const confirmMasterPasswordInput = document.querySelector("#confirm-master-password");
const changePinButton = document.querySelector("#change-pin");
const changeMasterPasswordSubmit = document.querySelector("#confirm-master-password-change");
const configureBiometricButton = document.querySelector("#configure-biometric");
const configureBiometricLabel = document.querySelector("#configure-biometric-label");
const biometricSetupForm = document.querySelector("#biometric-setup-form");
const biometricMasterPasswordInput = document.querySelector("#biometric-master-password");
const biometricSetupError = document.querySelector("#biometric-setup-error");
const confirmBiometricSetupButton = document.querySelector("#confirm-biometric-setup");
const toast = document.querySelector("#toast");
const exposureBanner = document.querySelector("#password-exposure-banner");
const searchInput = document.querySelector("#search-input");
const passwordInput = document.querySelector("#password-input");
const passwordVisibilityButton = document.querySelector("#toggle-password-visibility");
const formError = document.querySelector("#form-error");
const authGate = document.querySelector("#auth-gate");
const workspace = document.querySelector("#workspace");
const googleSignInButton = document.querySelector("#google-sign-in");
const vaultForm = document.querySelector("#vault-form");
const masterPasswordInput = document.querySelector("#master-password");
const masterPasswordConfirm = document.querySelector("#master-password-confirm");
const masterConfirmField = document.querySelector("#master-confirm-field");
const masterPasswordField = document.querySelector("#master-password-field");
const pinField = document.querySelector("#pin-field");
const pinConfirmField = document.querySelector("#pin-confirm-field");
const pinInput = document.querySelector("#pin-input");
const pinConfirmInput = document.querySelector("#pin-confirm-input");
const pinNote = document.querySelector("#pin-note");
const pinRecoveryButton = document.querySelector("#pin-recovery");
const pinSettingsForm = document.querySelector("#pin-settings-form");
const currentPinInput = document.querySelector("#current-pin-input");
const newPinInput = document.querySelector("#new-pin-input");
const confirmPinInput = document.querySelector("#confirm-pin-input");
const pinSettingsError = document.querySelector("#pin-settings-error");
const biometricOption = document.querySelector("#biometric-option");
const enableBiometricInput = document.querySelector("#enable-biometric");
const biometricUnlockButton = document.querySelector("#biometric-unlock");
const vaultSubmitButton = document.querySelector("#vault-submit");
const authMessage = document.querySelector("#auth-message");
const authDiagnosticActions = document.querySelector("#auth-diagnostic-actions");
const openAuthDiagnosticsButton = document.querySelector("#open-auth-diagnostics");
const accountActions = document.querySelector("#account-actions");
const accountMenu = document.querySelector(".account-menu");
const forgetDeviceKeyButton = document.querySelector("#forget-device-key");
let firebaseClient;
let currentUser = null;
let currentVaultMetadata = null;
let vaultKey = null;
let pendingPinKey = null;
let pinResetRequested = false;
let vaultKeyGeneration = 1;
let hasRememberedVaultKey = false;
let hasBiometricVaultRecord = false;
let biometricUnlockAvailable = false;
let vaultMode = "unlock";
let credentialsUnsubscribe = null;
let selectedId = null;
let toastTimeout;
let revealTimeout;
let passwordVisibilityTimeout;
let passwordExposureTimer;
let passwordExposureCounts = {};
let passwordExposureError = "";
let passwordExposureIsScanning = false;
let pendingWriteCount = 0;
let pendingDocumentCount = 0;
let snapshotFromCache = true;
let syncError = false;
let keyRotationInProgress = false;
let vaultSessionId = 0;
let credentialSnapshotRevision = 0;

function randomIndex(length) {
  if (!Number.isSafeInteger(length) || length < 1 || length > 256) {
    throw new RangeError("El tamaño del conjunto aleatorio no es válido.");
  }

  const values = new Uint8Array(1);
  const acceptedLimit = Math.floor(256 / length) * length;

  do {
    crypto.getRandomValues(values);
  } while (values[0] >= acceptedLimit);

  return values[0] % length;
}

async function showPinGate(key, userId = currentUser?.uid) {
  if (!currentUser || currentUser.uid !== userId) {
    return;
  }
  const sessionId = vaultSessionId;
  const pinStatus = await window.bovedaDesktop.getPinStatus(userId);
  if (currentUser?.uid !== userId || vaultSessionId !== sessionId) {
    return;
  }
  pendingPinKey = key;
  setVaultFormMode(pinStatus.configured ? "pin-unlock" : "pin-create");
  if (!pinStatus.configured) {
    pinNote.hidden = false;
  }
  pinInput.focus();
}

function secureShuffle(items) {
  for (let index = items.length - 1; index > 0; index -= 1) {
    const swapIndex = randomIndex(index + 1);
    [items[index], items[swapIndex]] = [items[swapIndex], items[index]];
  }

  return items;
}

function generatePassword() {
  const password = characterSets.map((set) => set[randomIndex(set.length)]);
  const allCharacters = characterSets.join("");

  while (password.length < 12) {
    password.push(allCharacters[randomIndex(allCharacters.length)]);
  }

  return secureShuffle(password).join("");
}

function createIcon(name) {
  const paths = {
    copy: '<rect x="7" y="7" width="10" height="10" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M13 5H5v8" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
    eye: '<path d="M2.5 10s2.7-5 7.5-5 7.5 5 7.5 5-2.7 5-7.5 5-7.5-5-7.5-5Z" fill="none" stroke="currentColor" stroke-width="1.5"/><circle cx="10" cy="10" r="2" fill="none" stroke="currentColor" stroke-width="1.5"/>',
    edit: '<path d="m12.8 4.2 3 3M4 16l3.2-.7 8.4-8.4a1.4 1.4 0 0 0-2-2l-8.4 8.4L4 16Z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',
  };
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 20 20");
  svg.setAttribute("aria-hidden", "true");
  svg.innerHTML = paths[name];
  return svg;
}

function showToast(message, kind = "success") {
  window.clearTimeout(toastTimeout);
  toast.textContent = message;
  toast.dataset.kind = kind;
  toast.hidden = false;
  toastTimeout = window.setTimeout(() => {
    toast.hidden = true;
  }, 3200);
}

function showAuthMessage(message) {
  authMessage.textContent = message;
  authMessage.hidden = !message;
}

function setVaultFormMode(mode, message = "") {
  vaultMode = mode;
  authGate.hidden = false;
  workspace.hidden = true;
  googleSignInButton.hidden = Boolean(currentUser);
  googleSignInButton.disabled = !firebaseClient;
  accountActions.hidden = !currentUser;
  forgetDeviceKeyButton.hidden = !currentUser || !hasRememberedVaultKey;
  vaultForm.hidden = !currentUser || mode === "loading";
  const isRecoveryMode = mode === "create" || mode === "unlock";
  const isPinMode = mode === "pin-create" || mode === "pin-unlock";
  const masterPasswordNote = document.querySelector("#master-password-note");
  masterPasswordField.hidden = !isRecoveryMode;
  masterPasswordInput.required = isRecoveryMode;
  masterConfirmField.hidden = mode !== "create";
  masterPasswordConfirm.required = mode === "create";
  pinField.hidden = !isPinMode;
  pinInput.required = isPinMode;
  pinConfirmField.hidden = mode !== "pin-create";
  pinConfirmInput.required = mode === "pin-create";
  pinNote.hidden = !isPinMode;
  pinRecoveryButton.hidden = mode !== "pin-unlock";
  masterPasswordNote.hidden = isPinMode;
  biometricOption.hidden = true;
  biometricUnlockButton.hidden = true;

  const title = document.querySelector("#auth-title");
  const formTitle = document.querySelector("#vault-form-title");
  const formDescription = document.querySelector("#vault-form-description");
  const submitText = document.querySelector("#vault-submit");

  if (mode === "create") {
    title.textContent = "Configura PaSSword.";
    formTitle.textContent = "Crea tu clave de recuperación";
    formDescription.textContent = message || "La necesitarás para configurar PaSSword en otro dispositivo.";
    masterPasswordInput.autocomplete = "new-password";
    masterPasswordNote.textContent = "Conserva esta clave en un gestor seguro. La necesitarás en dispositivos que aún no tengan la llave local.";
    submitText.textContent = "Crear clave";
  } else if (mode === "unlock") {
    title.textContent = "PaSSword te espera.";
    formTitle.textContent = "Configura este dispositivo";
    formDescription.textContent = message;
    masterPasswordInput.autocomplete = "current-password";
    masterPasswordNote.textContent = "Introduce la clave de recuperación una vez para guardar una llave local protegida por tu PIN.";
    submitText.textContent = "Continuar";
  } else if (mode === "pin-create") {
    title.textContent = "PaSSword";
    formTitle.textContent = "Crea tu PIN";
    formDescription.textContent = "Elige cuatro cifras para abrir PaSSword en este PC después de iniciar sesión con Google.";
    masterPasswordInput.autocomplete = "current-password";
    document.querySelector("#pin-label").textContent = "PIN de 4 cifras";
    submitText.textContent = "Guardar PIN";
  } else if (mode === "pin-unlock") {
    title.textContent = "PaSSword";
    formTitle.textContent = "Introduce tu PIN";
    formDescription.textContent = "Inicia sesión con Google y usa tu PIN para abrir PaSSword en este PC.";
    masterPasswordInput.autocomplete = "current-password";
    document.querySelector("#pin-label").textContent = "PIN";
    submitText.textContent = "Desbloquear";
  } else {
    title.textContent = "PaSSword";
  }
}

function updateSyncStatus() {
  const label = document.querySelector("#connection-label");
  const securityStatus = document.querySelector("#security-status");
  changePinButton.hidden = !vaultKey;
  configureBiometricButton.hidden = true;
  securityStatus.hidden = !vaultKey;
  configureBiometricLabel.textContent = hasBiometricVaultRecord
    ? "Reconfigurar desbloqueo del dispositivo"
    : "Configurar desbloqueo del dispositivo";
  forgetDeviceKeyButton.hidden = !currentUser || !hasRememberedVaultKey;

  if (!currentUser) {
    label.textContent = firebaseClient ? "Esperando inicio de sesión" : "Preparando conexión segura…";
    return;
  }

  if (!vaultKey) {
    label.textContent = "Bóveda bloqueada";
    return;
  }

  if (syncError) {
    label.textContent = "Error de sincronización";
  } else if (!navigator.onLine) {
    label.textContent = "Sin conexión; cambios pendientes";
  } else if (pendingWriteCount > 0 || pendingDocumentCount > 0 || snapshotFromCache) {
    label.textContent = "Cambios pendientes de sincronizar";
  } else {
    label.textContent = "Sincronizado";
  }
}

function clearVaultState() {
  vaultSessionId += 1;
  credentialSnapshotRevision += 1;
  window.clearTimeout(passwordExposureTimer);
  passwordExposureTimer = undefined;
  passwordExposureCounts = {};
  passwordExposureError = "";
  passwordExposureIsScanning = false;
  document.body.classList.remove("vault-open");
  window.clearTimeout(revealTimeout);
  credentialsUnsubscribe?.();
  credentialsUnsubscribe = null;
  vaultKey = null;
  pendingPinKey = null;
  pinResetRequested = false;
  vaultKeyGeneration = 1;
  keyRotationInProgress = false;
  credentials.length = 0;
  selectedId = null;
  pendingWriteCount = 0;
  pendingDocumentCount = 0;
  snapshotFromCache = true;
  syncError = false;
  passwordInput.value = "";
  passwordInput.type = "password";
  masterPasswordInput.value = "";
  masterPasswordConfirm.value = "";
  pinInput.value = "";
  pinConfirmInput.value = "";
  currentMasterPasswordInput.value = "";
  newMasterPasswordInput.value = "";
  confirmMasterPasswordInput.value = "";
  if (dialog.open) {
    dialog.close();
  }
  render();
  workspace.hidden = true;
  updateSyncStatus();
}

function activateVaultKey(key) {
  vaultKey = key;
  pendingPinKey = null;
  vaultKeyGeneration = firebaseClient.getVaultKeyGeneration(currentVaultMetadata);
  document.body.classList.add("vault-open");
  authGate.hidden = true;
  workspace.hidden = false;
  showAuthMessage("");
  startCredentialListener();
  updateSyncStatus();
}

function handleCredentialSnapshotError() {
  syncError = true;
  updateSyncStatus();
  showToast("No se pudieron sincronizar los accesos. Revisa la conexión y las reglas de Firestore.", "error");
}

function startCredentialListener() {
  const userId = currentUser.uid;
  const activeKey = vaultKey;
  const sessionId = vaultSessionId;
  credentialsUnsubscribe?.();
  credentialsUnsubscribe = firebaseClient.watchVaultCredentials(
    userId,
    (items, fromCache) => {
      const snapshotRevision = ++credentialSnapshotRevision;
      void Promise.all(items.map(async ({ id, document }) => ({
        id,
        ...await decryptCredential(activeKey, userId, id, document),
        revision: await fingerprintEncryptedCredential(document),
      })))
        .then((decrypted) => {
          if (
            vaultSessionId !== sessionId
            || vaultKey !== activeKey
            || currentUser?.uid !== userId
            || snapshotRevision !== credentialSnapshotRevision
          ) {
            return;
          }
          credentials.splice(0, credentials.length, ...decrypted);
          pendingDocumentCount = items.filter((item) => item.hasPendingWrites).length;
          snapshotFromCache = fromCache;
          syncError = false;
          render();
          updateSyncStatus();
          void updatePasswordExposure();
        })
        .catch(() => {
          if (
            vaultSessionId !== sessionId
            || vaultKey !== activeKey
            || currentUser?.uid !== userId
            || snapshotRevision !== credentialSnapshotRevision
            || keyRotationInProgress
          ) {
            return;
          }
          clearVaultState();
          setVaultFormMode("unlock", "No se pudo validar el contenido cifrado de PaSSword.");
          showAuthMessage("No se pudo descifrar un acceso. Comprueba la clave de recuperación o contacta con el propietario antes de continuar.");
        });
    },
    () => {
      if (vaultSessionId === sessionId && currentUser?.uid === userId) {
        handleCredentialSnapshotError();
      }
    },
  );
}

async function updatePasswordExposure() {
  if (!vaultKey || !currentUser || passwordExposureIsScanning) {
    return;
  }
  const activeUserId = currentUser.uid;
  const activeKey = vaultKey;
  const sessionId = vaultSessionId;
  const snapshotRevision = credentialSnapshotRevision;
  passwordExposureIsScanning = true;
  let nextDelay = 6 * 60 * 60 * 1000;
  render();

  try {
    const result = await scanPasswordExposure({
      userId: activeUserId,
      credentials: credentials.map(({ id, password, revision }) => ({
        id,
        password,
        revision,
      })),
      canCommit: () => vaultSessionId === sessionId
        && vaultKey === activeKey
        && currentUser?.uid === activeUserId
        && credentialSnapshotRevision === snapshotRevision,
    });
    if (result && vaultSessionId === sessionId && vaultKey === activeKey) {
      passwordExposureCounts = result.counts;
      passwordExposureError = "";
      nextDelay = Math.max(1000, result.nextFullCheckAt - Date.now());
      if (result.newlyExposedIds.length > 0) {
        showToast(
          `Se detectaron contraseñas expuestas en ${result.newlyExposedIds.length} acceso(s). Cámbialas cuanto antes.`,
          "error",
        );
      }
    }
  } catch {
    if (vaultSessionId === sessionId && vaultKey === activeKey) {
      passwordExposureError =
        "No se pudo completar la comprobación de contraseñas. Se volverá a intentar más tarde.";
    }
  } finally {
    if (vaultSessionId === sessionId && vaultKey === activeKey) {
      passwordExposureIsScanning = false;
      render();
      if (credentialSnapshotRevision !== snapshotRevision) {
        window.clearTimeout(passwordExposureTimer);
        void updatePasswordExposure();
        return;
      }
      window.clearTimeout(passwordExposureTimer);
      passwordExposureTimer = window.setTimeout(
        () => void updatePasswordExposure(),
        Math.min(nextDelay, 2_147_000_000),
      );
    }
  }
}

function renderAccountAvatar(user) {
  const avatar = document.querySelector("#account-avatar");
  const fallback = user.displayName?.trim().charAt(0).toLocaleUpperCase("es") || "G";
  avatar.replaceChildren();
  avatar.textContent = fallback;
  avatar.setAttribute("aria-label", user.displayName || "Cuenta de Google");

  if (typeof user.photoURL !== "string") {
    return;
  }

  let photoUrl;
  try {
    photoUrl = new URL(user.photoURL);
  } catch {
    return;
  }
  if (photoUrl.protocol !== "https:" || !photoUrl.hostname.endsWith(".googleusercontent.com")) {
    return;
  }

  const photo = document.createElement("img");
  photo.alt = "";
  photo.addEventListener("error", () => {
    photo.remove();
    avatar.textContent = fallback;
  }, { once: true });
  photo.src = photoUrl.toString();
  avatar.replaceChildren(photo);
}

async function handleAuthState(user) {
  const sameUser = currentUser?.uid && currentUser.uid === user?.uid;
  if (!sameUser) {
    clearVaultState();
    hasRememberedVaultKey = false;
    hasBiometricVaultRecord = false;
  }
  currentUser = user;
  currentVaultMetadata = null;
  showAuthMessage("");
  accountActions.hidden = !user;
  googleSignInButton.hidden = Boolean(user);
  googleSignInButton.disabled = !firebaseClient;

  if (user) {
    renderAccountAvatar(user);
    setVaultFormMode("loading");

    try {
      const metadata = await firebaseClient.readVaultMetadata(user.uid);
      if (currentUser?.uid !== user.uid) {
        return;
      }
      currentVaultMetadata = metadata;
      if (metadata) {
        try {
          const [rememberedKey, biometricRecord] = await Promise.all([
            loadRememberedVaultKey(user.uid),
            loadBiometricVaultRecord(user.uid),
          ]);
          if (currentUser?.uid !== user.uid) {
            return;
          }
          hasBiometricVaultRecord = Boolean(biometricRecord);
          hasRememberedVaultKey = Boolean(rememberedKey || biometricRecord);
          const isValidRememberedKey = rememberedKey && await verifyVaultKey(
            rememberedKey,
            user.uid,
            firebaseClient.validateVaultVerifier(metadata),
          );
          if (isValidRememberedKey) {
            await showPinGate(rememberedKey, user.uid);
            return;
          }
          if (biometricRecord) {
            setVaultFormMode(
              "unlock",
              biometricRecord.keyGeneration === firebaseClient.getVaultKeyGeneration(metadata)
                ? "Confirma tu identidad con el dispositivo o usa la clave de recuperación."
                : "El desbloqueo del dispositivo necesita actualizarse. Usa la clave de recuperación.",
            );
            return;
          }
          setVaultFormMode(
            "unlock",
            rememberedKey
              ? "La llave guardada no coincide con la clave de recuperación actual. Introdúcela para actualizar este dispositivo."
              : "",
          );
        } catch (error) {
          setVaultFormMode("unlock");
          showAuthMessage("No se pudo cargar el PIN o la llave local de esta cuenta. Comprueba el almacenamiento local o introduce la clave de recuperación para continuar.");
        }
      } else {
        hasRememberedVaultKey = false;
        hasBiometricVaultRecord = false;
        setVaultFormMode("create");
      }
      if (!metadata && !navigator.onLine) {
        showAuthMessage("Conéctate para configurar PaSSword por primera vez.");
      }
    } catch (error) {
      if (currentUser?.uid !== user.uid) {
        return;
      }
      setVaultFormMode("loading");
      showAuthMessage(error.message || "No se pudo leer la configuración cifrada de PaSSword.");
    }
  } else {
    hasBiometricVaultRecord = false;
    setVaultFormMode("sign-in");
  }

  updateSyncStatus();
}

function trackPendingWrite(promise, errorMessage) {
  const sessionId = vaultSessionId;
  const userId = currentUser?.uid;
  pendingWriteCount += 1;
  syncError = false;
  updateSyncStatus();

  promise.then(() => {
    if (vaultSessionId !== sessionId || currentUser?.uid !== userId) {
      return;
    }
    pendingWriteCount = Math.max(0, pendingWriteCount - 1);
    updateSyncStatus();
  }).catch(() => {
    if (vaultSessionId !== sessionId || currentUser?.uid !== userId) {
      return;
    }
    pendingWriteCount = Math.max(0, pendingWriteCount - 1);
    syncError = true;
    updateSyncStatus();
    showToast(errorMessage, "error");
  });
}

async function submitVault(event) {
  event.preventDefault();
  if (!currentUser || !firebaseClient || !vaultForm.reportValidity()) {
    return;
  }

  const user = currentUser;
  const sessionId = vaultSessionId;
  const isCurrentSession = () => vaultSessionId === sessionId && currentUser?.uid === user.uid;
  const password = masterPasswordInput.value;
  if (password.length < 12) {
    showAuthMessage("La clave de recuperación debe tener al menos 12 caracteres.");
    return;
  }
  if (vaultMode === "create" && password !== masterPasswordConfirm.value) {
    showAuthMessage("Las claves de recuperación no coinciden.");
    masterPasswordConfirm.focus();
    return;
  }

  vaultSubmitButton.disabled = true;
  showAuthMessage("");
  let derivedKey;
  let keyMaterial;
  let metadataCreated = false;
  const configureBiometric = biometricUnlockAvailable && enableBiometricInput.checked;
  try {
    if (vaultMode === "create") {
      const salt = createVaultSalt();
      if (configureBiometric) {
        keyMaterial = await deriveVaultKeyMaterial(password, salt);
        derivedKey = await importVaultKeyMaterial(keyMaterial);
      } else {
        derivedKey = await deriveVaultKey(password, salt);
      }
      if (!isCurrentSession()) {
        return;
      }
      const verifier = await createVaultVerifier(derivedKey, user.uid);
      if (!isCurrentSession()) {
        return;
      }
      const biometricRecord = configureBiometric
        ? await createBiometricVaultRecord(user.uid, keyMaterial, 1)
        : null;
      if (!isCurrentSession()) {
        return;
      }
      await firebaseClient.createVaultMetadata(user.uid, salt, verifier);
      if (!isCurrentSession()) {
        return;
      }
      metadataCreated = true;
      currentVaultMetadata = {
        version: 1,
        kdf: firebaseClient.KDF_NAME,
        iterations: 600_000,
        keyGeneration: 1,
        verifier,
        salt: btoa(String.fromCharCode(...salt)),
      };
      if (biometricRecord) {
        await saveBiometricVaultRecord(user.uid, biometricRecord);
        hasBiometricVaultRecord = true;
      }
    } else {
      const salt = firebaseClient.decodeVaultSalt(currentVaultMetadata);
      if (configureBiometric) {
        keyMaterial = await deriveVaultKeyMaterial(password, salt);
        derivedKey = await importVaultKeyMaterial(keyMaterial);
      } else {
        derivedKey = await deriveVaultKey(password, salt);
      }
      const verifier = firebaseClient.validateVaultVerifier(currentVaultMetadata);
      if (!isCurrentSession()) {
        return;
      }
      if (!await verifyVaultKey(derivedKey, user.uid, verifier)) {
        throw new Error("La clave de recuperación no es correcta.");
      }
      if (configureBiometric) {
        const keyGeneration = firebaseClient.getVaultKeyGeneration(currentVaultMetadata);
        const biometricRecord = await createBiometricVaultRecord(user.uid, keyMaterial, keyGeneration);
        if (!isCurrentSession()) {
          return;
        }
        await saveBiometricVaultRecord(user.uid, biometricRecord);
        hasBiometricVaultRecord = true;
      }
    }

    if (!isCurrentSession()) {
      return;
    }
    masterPasswordInput.value = "";
    masterPasswordConfirm.value = "";
    await saveRememberedVaultKey(user.uid, derivedKey);
    hasRememberedVaultKey = true;
    if (!isCurrentSession()) {
      return;
    }
    const pinStatus = await window.bovedaDesktop.getPinStatus(user.uid);
    if (!isCurrentSession()) {
      return;
    }
    if (pinStatus.configured && !pinResetRequested) {
      activateVaultKey(derivedKey);
    } else {
      pendingPinKey = derivedKey;
      pinResetRequested = false;
      setVaultFormMode("pin-create");
      pinInput.focus();
    }
  } catch (error) {
    derivedKey = null;
    if (isCurrentSession()) {
      masterPasswordInput.value = "";
      masterPasswordConfirm.value = "";
      masterPasswordInput.focus();
      if (metadataCreated) {
        setVaultFormMode("unlock", "PaSSword se configuró, pero este dispositivo no terminó de prepararse. Usa la clave de recuperación para continuar.");
      }
      showAuthMessage(getBiometricErrorMessage(error));
    }
  } finally {
    keyMaterial?.fill(0);
    vaultSubmitButton.disabled = false;
  }
}

async function submitPin(event) {
  event.preventDefault();
  if (!currentUser || !pendingPinKey || !vaultForm.reportValidity()) {
    return;
  }

  const userId = currentUser.uid;
  const sessionId = vaultSessionId;
  const activeKey = pendingPinKey;
  const pin = pinInput.value;
  if (vaultMode === "pin-create" && pin !== pinConfirmInput.value) {
    pinConfirmInput.value = "";
    pinConfirmInput.focus();
    showAuthMessage("Los PIN no coinciden.");
    return;
  }

  vaultSubmitButton.disabled = true;
  showAuthMessage("");
  try {
    if (vaultMode === "pin-create") {
      await window.bovedaDesktop.setPin(userId, pin);
    } else {
      const result = await window.bovedaDesktop.verifyPin(userId, pin);
      if (result.retryAfterSeconds) {
        throw new Error(`Has alcanzado el límite de intentos. Espera ${result.retryAfterSeconds} segundos.`);
      }
      if (!result.configured) {
        throw new Error("No hay un PIN configurado. Crea uno para este PC.");
      }
      if (!result.valid) {
        const remaining = result.attemptsRemaining === 1
          ? " Queda 1 intento antes de una pausa."
          : ` Quedan ${result.attemptsRemaining} intentos antes de una pausa.`;
        throw new Error(`El PIN no es correcto.${remaining}`);
      }
    }

    if (currentUser?.uid !== userId || vaultSessionId !== sessionId || pendingPinKey !== activeKey) {
      return;
    }
    pinInput.value = "";
    pinConfirmInput.value = "";
    activateVaultKey(activeKey);
  } catch (error) {
    if (currentUser?.uid === userId && vaultSessionId === sessionId) {
      pinInput.value = "";
      pinInput.focus();
      showAuthMessage(error.message || "No se pudo validar el PIN.");
    }
  } finally {
    vaultSubmitButton.disabled = false;
  }
}

function openPinSettingsDialog() {
  if (!vaultKey || !currentUser) {
    return;
  }
  form.hidden = true;
  masterPasswordForm.hidden = true;
  biometricSetupForm.hidden = true;
  pinSettingsForm.hidden = false;
  pinSettingsForm.reset();
  pinSettingsError.hidden = true;
  document.querySelector("#dialog-title").textContent = "Cambiar PIN";
  dialog.showModal();
  currentPinInput.focus();
}

async function changePin(event) {
  event.preventDefault();
  if (!currentUser || !vaultKey || !pinSettingsForm.reportValidity()) {
    return;
  }
  if (newPinInput.value !== confirmPinInput.value) {
    confirmPinInput.value = "";
    confirmPinInput.focus();
    pinSettingsError.textContent = "Los PIN nuevos no coinciden.";
    pinSettingsError.hidden = false;
    return;
  }

  const userId = currentUser.uid;
  const sessionId = vaultSessionId;
  const saveButton = document.querySelector("#save-pin");
  saveButton.disabled = true;
  pinSettingsError.hidden = true;
  try {
    const result = await window.bovedaDesktop.verifyPin(userId, currentPinInput.value);
    if (result.retryAfterSeconds) {
      throw new Error(`Has alcanzado el límite de intentos. Espera ${result.retryAfterSeconds} segundos.`);
    }
    if (!result.configured || !result.valid) {
      throw new Error("El PIN actual no es correcto.");
    }
    if (newPinInput.value === currentPinInput.value) {
      throw new Error("Elige un PIN distinto del actual.");
    }
    await window.bovedaDesktop.setPin(userId, newPinInput.value);
    if (currentUser?.uid !== userId || vaultSessionId !== sessionId) {
      return;
    }
    dialog.close();
    showToast("PIN cambiado en este PC.");
  } catch (error) {
    pinSettingsError.textContent = error.message || "No se pudo cambiar el PIN.";
    pinSettingsError.hidden = false;
    currentPinInput.value = "";
    currentPinInput.focus();
  } finally {
    saveButton.disabled = false;
  }
}

function getBiometricErrorMessage(error) {
  if (error?.name === "NotAllowedError" || error?.name === "AbortError") {
    return "No se completó la verificación del dispositivo. Puedes intentarlo de nuevo o usar la clave de recuperación.";
  }
  if (error?.name === "NotSupportedError") {
    return "Este dispositivo no admite esta forma de desbloqueo seguro. Usa la clave de recuperación.";
  }
  if (error?.name === "OperationError") {
    return "No se pudo validar la llave de este dispositivo. Usa la clave de recuperación.";
  }
  return error?.message || "No se pudo desbloquear PaSSword. Revisa la conexión e inténtalo de nuevo.";
}

function openMasterPasswordDialog() {
  if (!vaultKey || !currentUser) {
    return;
  }

  form.hidden = true;
  masterPasswordForm.hidden = false;
  masterPasswordForm.reset();
  masterPasswordError.hidden = true;
  document.querySelector("#dialog-title").textContent = "Cambiar clave de recuperación";
  dialog.showModal();
  currentMasterPasswordInput.focus();
}

function openBiometricSetupDialog() {
  if (!vaultKey || !currentUser || !biometricUnlockAvailable) {
    return;
  }

  form.hidden = true;
  masterPasswordForm.hidden = true;
  biometricSetupForm.hidden = false;
  biometricSetupForm.reset();
  biometricSetupError.hidden = true;
  document.querySelector("#dialog-title").textContent = hasBiometricVaultRecord
    ? "Reconfigurar desbloqueo del dispositivo"
    : "Configurar desbloqueo del dispositivo";
  dialog.showModal();
  biometricMasterPasswordInput.focus();
}

async function setupBiometricUnlock(event) {
  event.preventDefault();
  if (!currentUser || !vaultKey || !biometricSetupForm.reportValidity()) {
    return;
  }

  const user = currentUser;
  const activeKey = vaultKey;
  const sessionId = vaultSessionId;
  const isCurrentSession = () =>
    vaultSessionId === sessionId && currentUser?.uid === user.uid && vaultKey === activeKey;
  confirmBiometricSetupButton.disabled = true;
  biometricSetupError.hidden = true;
  let keyMaterial;
  try {
    const salt = firebaseClient.decodeVaultSalt(currentVaultMetadata);
    keyMaterial = await deriveVaultKeyMaterial(biometricMasterPasswordInput.value, salt);
    const verifiedKey = await importVaultKeyMaterial(keyMaterial);
    const verifier = firebaseClient.validateVaultVerifier(currentVaultMetadata);
    if (
      !await verifyVaultKey(verifiedKey, user.uid, verifier)
      || !await verifyVaultKey(activeKey, user.uid, verifier)
    ) {
      throw new Error("La clave de recuperación no es correcta para PaSSword.");
    }
    if (!isCurrentSession()) {
      return;
    }

    const biometricRecord = await createBiometricVaultRecord(
      user.uid,
      keyMaterial,
      firebaseClient.getVaultKeyGeneration(currentVaultMetadata),
    );
    if (!isCurrentSession()) {
      return;
    }
    await saveBiometricVaultRecord(user.uid, biometricRecord);
    if (!isCurrentSession()) {
      return;
    }

    hasBiometricVaultRecord = true;
    hasRememberedVaultKey = true;
    dialog.close();
    updateSyncStatus();
    showToast("Desbloqueo del dispositivo activado. La clave de recuperación sigue siendo necesaria en equipos nuevos.");
  } catch (error) {
    if (isCurrentSession()) {
      biometricMasterPasswordInput.value = "";
      biometricMasterPasswordInput.focus();
      biometricSetupError.textContent = getBiometricErrorMessage(error);
      biometricSetupError.hidden = false;
    }
  } finally {
    keyMaterial?.fill(0);
    confirmBiometricSetupButton.disabled = false;
  }
}

async function changeMasterPassword(event) {
  event.preventDefault();
  if (!masterPasswordForm.reportValidity()) {
    return;
  }
  if (!currentUser || !vaultKey || !currentVaultMetadata || !firebaseClient) {
    masterPasswordError.textContent = "Desbloquea PaSSword antes de cambiar la contraseña.";
    masterPasswordError.hidden = false;
    return;
  }
  if (
    !navigator.onLine
    || pendingWriteCount > 0
    || pendingDocumentCount > 0
    || snapshotFromCache
    || syncError
  ) {
    masterPasswordError.textContent = "Conéctate y espera a que todos los cambios estén sincronizados antes de continuar.";
    masterPasswordError.hidden = false;
    return;
  }

  const userId = currentUser.uid;
  const sessionId = vaultSessionId;
  const activeKey = vaultKey;
  const expectedMetadata = currentVaultMetadata;
  const currentPassword = currentMasterPasswordInput.value;
  const newPassword = newMasterPasswordInput.value;
  const confirmation = confirmMasterPasswordInput.value;
  const isCurrentSession = () =>
    vaultSessionId === sessionId
    && currentUser?.uid === userId
    && vaultKey === activeKey;

  if (currentPassword.normalize("NFKC") === newPassword.normalize("NFKC")) {
    masterPasswordError.textContent = "La nueva contraseña debe ser distinta de la actual.";
    masterPasswordError.hidden = false;
    newMasterPasswordInput.focus();
    return;
  }
  if (newPassword !== confirmation) {
    masterPasswordError.textContent = "Las nuevas contraseñas no coinciden.";
    masterPasswordError.hidden = false;
    confirmMasterPasswordInput.focus();
    return;
  }

  changeMasterPasswordSubmit.disabled = true;
  masterPasswordError.hidden = true;
  let newKey;
  let newSalt;
  let newVerifier;
  try {
    const oldSalt = firebaseClient.decodeVaultSalt(expectedMetadata);
    const oldKey = await deriveVaultKey(currentPassword, oldSalt);
    if (!isCurrentSession()) {
      return;
    }
    const oldVerifier = firebaseClient.validateVaultVerifier(expectedMetadata);
    if (
      !await verifyVaultKey(oldKey, userId, oldVerifier)
      || !await verifyVaultKey(activeKey, userId, oldVerifier)
    ) {
      throw new Error("La contraseña actual no es correcta.");
    }

    newSalt = createVaultSalt();
    newKey = await deriveVaultKey(newPassword, newSalt);
    if (!isCurrentSession()) {
      return;
    }
    newVerifier = await createVaultVerifier(newKey, userId);
    if (!isCurrentSession()) {
      return;
    }

    keyRotationInProgress = true;
    credentialsUnsubscribe?.();
    credentialsUnsubscribe = null;
    const result = await firebaseClient.reencryptVault(
      userId,
      expectedMetadata,
      oldKey,
      newKey,
      newSalt,
      newVerifier,
    );
    if (!isCurrentSession()) {
      return;
    }

    currentVaultMetadata = {
      version: 1,
      kdf: firebaseClient.KDF_NAME,
      iterations: 600_000,
      keyGeneration: result.keyGeneration,
      salt: btoa(String.fromCharCode(...newSalt)),
      verifier: newVerifier,
    };
    vaultKey = newKey;
    vaultKeyGeneration = result.keyGeneration;
    let rememberFailed = false;
    let biometricRemoved = false;
    if (hasBiometricVaultRecord) {
      try {
        await forgetRememberedVaultKey(userId);
        hasRememberedVaultKey = false;
        hasBiometricVaultRecord = false;
        biometricRemoved = true;
      } catch {
        rememberFailed = true;
      }
    } else {
      try {
        await saveRememberedVaultKey(userId, newKey);
        hasRememberedVaultKey = true;
      } catch {
        rememberFailed = true;
      }
    }
    if (!isCurrentSession()) {
      return;
    }
    keyRotationInProgress = false;
    startCredentialListener();
    dialog.close();
    const message = `Clave de recuperación cambiada; ${result.credentialCount} ${result.credentialCount === 1 ? "acceso recifrado" : "accesos recifrados"}.${biometricRemoved ? " Vuelve a activar el desbloqueo del dispositivo con la nueva clave de recuperación." : ""}${rememberFailed ? " La próxima vez tendrás que introducir la nueva clave de recuperación." : ""}`;
    showToast(message, rememberFailed ? "error" : "success");
  } catch (error) {
    if (isCurrentSession()) {
      if (keyRotationInProgress) {
        keyRotationInProgress = false;
        startCredentialListener();
      }
      masterPasswordError.textContent = error.message
        || "No se pudo cambiar la contraseña. No se aplicó ningún cambio.";
      masterPasswordError.hidden = false;
      currentMasterPasswordInput.value = "";
      newMasterPasswordInput.value = "";
      confirmMasterPasswordInput.value = "";
      currentMasterPasswordInput.focus();
    }
  } finally {
    changeMasterPasswordSubmit.disabled = false;
  }
}

async function signIn() {
  if (!firebaseClient) {
    showAuthMessage("Firebase todavía no está disponible. Recarga la página cuando haya conexión.");
    return;
  }

  googleSignInButton.disabled = true;
  showAuthMessage("");
  authDiagnosticActions.hidden = true;
  try {
    await firebaseClient.signInWithGoogle();
  } catch (error) {
    const messages = new Map([
      ["desktop/oauth-client-missing", "Falta configurar el cliente OAuth de escritorio."],
      ["desktop/oauth-client-invalid", "Google rechazó el cliente OAuth. Comprueba que pertenece al proyecto gestor-pass-b60d6."],
      ["desktop/oauth-redirect-invalid", "Google rechazó el retorno local. Comprueba que el cliente es de tipo Aplicación de escritorio."],
      ["desktop/oauth-ipc-failed", "Falló la comunicación interna de PaSSword. Cierra la aplicación por completo y vuelve a abrirla."],
      ["desktop/oauth-bridge-failed", "La aplicación no pudo comunicar el error de inicio de sesión. Actualiza PaSSword y vuelve a intentarlo."],
      ["desktop/oauth-cancelled", "Se canceló el inicio de sesión con Google."],
      ["desktop/oauth-timeout", "Se agotó el tiempo de inicio de sesión. Vuelve a intentarlo."],
      ["desktop/oauth-token-exchange", "Google no pudo completar el intercambio OAuth."],
      ["desktop/oauth-token-network", "No se pudo conectar con el servicio de autenticación de Google."],
      ["desktop/oauth-google-invalid-client", "Google rechazó el ID de cliente OAuth."],
      ["desktop/oauth-google-invalid-grant", "Google rechazó el código temporal de inicio de sesión. Vuelve a intentarlo."],
      ["desktop/oauth-google-unauthorized-client", "Google no autorizó este cliente OAuth."],
      ["desktop/oauth-google-invalid-request", "Google rechazó la solicitud OAuth."],
      ["desktop/oauth-google-invalid-scope", "Google rechazó los permisos solicitados por la app."],
      ["auth/unauthorized-domain", "Este dominio no está autorizado en Firebase Authentication."],
      ["auth/operation-not-allowed", "Google Sign-In no está habilitado en Firebase Authentication."],
      ["auth/invalid-credential", "Firebase rechazó las credenciales de Google."],
      ["auth/invalid-idp-response", "Firebase rechazó la respuesta de Google."],
      ["auth/network-request-failed", "No se pudo conectar con Google. Comprueba tu conexión."],
    ]);
    const code = typeof error.code === "string" && /^(auth|desktop)\/[a-z0-9-]{1,80}$/.test(error.code)
      ? error.code
      : "unknown";
    const stage = ["oauth", "firebase"].includes(error.signInStage)
      ? error.signInStage
      : code.startsWith("desktop/")
        ? "oauth"
        : code.startsWith("auth/")
          ? "firebase"
          : "unknown";
    const errorType = typeof error.name === "string" && /^[A-Za-z][A-Za-z0-9]{0,39}$/.test(error.name)
      ? error.name
      : "Error";

    authDiagnosticActions.hidden = !window.bovedaDesktop;
    let logStatus = "";
    if (window.bovedaDesktop) {
      try {
        await window.bovedaDesktop.logSignInFailure({
          code,
          stage,
          errorType,
          detail: error.diagnosticDetail,
        });
      } catch {
        logStatus = " No se pudo escribir el registro local.";
      }
    }
    const message = messages.get(code) ?? "No se pudo iniciar sesión con Google.";
    const detail = typeof error.diagnosticDetail === "string"
      && /^[a-z0-9_-]{1,48}$/i.test(error.diagnosticDetail)
      ? ` Detalle técnico: ${error.diagnosticDetail}.`
      : "";
    showAuthMessage(`${message} Etapa: ${stage}; código: ${code}.${detail}${logStatus}`);
  } finally {
    googleSignInButton.disabled = false;
  }
}

openAuthDiagnosticsButton.addEventListener("click", async () => {
  try {
    await window.bovedaDesktop.openSignInDiagnostics();
  } catch {
    showAuthMessage("Windows no pudo abrir el registro. Puedes encontrarlo en los datos locales de PaSSword.");
  }
});

async function signOut() {
  clearVaultState();
  try {
    await firebaseClient.signOutUser();
  } catch {
    setVaultFormMode(currentVaultMetadata ? "unlock" : "create");
    showAuthMessage("No se pudo cerrar la sesión de Google. PaSSword quedó bloqueado; inténtalo de nuevo.");
  }
}

async function unlockWithBiometric() {
  if (!currentUser || !currentVaultMetadata || !hasBiometricVaultRecord) {
    return;
  }

  const userId = currentUser.uid;
  const sessionId = vaultSessionId;
  biometricUnlockButton.disabled = true;
  showAuthMessage("");
  try {
    const record = await loadBiometricVaultRecord(userId);
    if (!record || currentUser?.uid !== userId || vaultSessionId !== sessionId) {
      throw new Error("No se encontró la configuración de desbloqueo de este dispositivo. Usa la clave de recuperación.");
    }
    if (record.keyGeneration !== firebaseClient.getVaultKeyGeneration(currentVaultMetadata)) {
      throw new Error("La llave biométrica está desactualizada. Desbloquea con la clave de recuperación.");
    }

    const key = await unlockBiometricVaultKey(userId, record);
    if (currentUser?.uid !== userId || vaultSessionId !== sessionId) {
      return;
    }
    const verifier = firebaseClient.validateVaultVerifier(currentVaultMetadata);
    if (!await verifyVaultKey(key, userId, verifier)) {
      throw new Error("La llave del dispositivo ya no coincide con PaSSword. Usa la clave de recuperación.");
    }
    activateVaultKey(key);
  } catch (error) {
    if (currentUser?.uid === userId && vaultSessionId === sessionId) {
      showAuthMessage(getBiometricErrorMessage(error));
    }
  } finally {
    biometricUnlockButton.disabled = false;
  }
}

async function forgetDeviceKey() {
  if (!currentUser || !hasRememberedVaultKey) {
    return;
  }
  const userId = currentUser.uid;
  try {
    await forgetRememberedVaultKey(userId);
    if (currentUser?.uid !== userId) {
      return;
    }
    hasRememberedVaultKey = false;
    hasBiometricVaultRecord = false;
    if (!vaultKey) {
      setVaultFormMode("unlock", "Este dispositivo ya no conserva una llave. Introduce tu clave de recuperación.");
    }
    updateSyncStatus();
    showToast("Se olvidó el desbloqueo guardado en este dispositivo. La próxima vez necesitarás la clave de recuperación.");
  } catch (error) {
    showToast(error.message || "No se pudo olvidar la llave de este navegador.", "error");
  }
}

function makeIconButton(label, iconName, action) {
  const button = document.createElement("button");
  button.className = "icon-button";
  button.type = "button";
  button.setAttribute("aria-label", label);
  button.title = label;
  button.append(createIcon(iconName));
  button.addEventListener("click", action);
  return button;
}

function selectedCredential() {
  return credentials.find((credential) => credential.id === selectedId) ?? null;
}

function renderList() {
  const query = searchInput.value.trim().toLocaleLowerCase("es");
  const filtered = credentials
    .filter((credential) =>
      `${credential.site} ${credential.email}`.toLocaleLowerCase("es").includes(query),
    )
    .sort((first, second) =>
      first.site.localeCompare(second.site, "es", { sensitivity: "base", numeric: true }),
    );

  emptyState.hidden = credentials.length > 0;
  detailPanel.hidden = credentials.length === 0;
  contentGrid.classList.toggle("is-empty", credentials.length === 0);
  contentGrid.classList.toggle("has-selection", Boolean(selectedCredential()));
  listToolbar.classList.toggle("is-empty", credentials.length === 0);
  listElement.hidden = credentials.length === 0;
  listElement.replaceChildren();

  for (const credential of filtered) {
    const item = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.className = "credential-row";
    button.setAttribute("aria-pressed", String(credential.id === selectedId));

    const mark = document.createElement("span");
    mark.className = "site-mark";
    mark.dataset.tone = String(credential.site.length % 4);
    mark.setAttribute("aria-hidden", "true");
    mark.textContent = credential.site.trim().charAt(0) || "?";

    const copy = document.createElement("span");
    copy.className = "row-copy";
    const site = document.createElement("strong");
    site.textContent = credential.site;
    const username = document.createElement("span");
    username.textContent = credential.email;
    copy.append(site);
    if ((passwordExposureCounts[credential.id] ?? 0) > 0) {
      const risk = document.createElement("span");
      risk.className = "credential-risk";
      risk.textContent = "Contraseña expuesta";
      copy.append(risk);
    }
    copy.append(username);

    const chevron = document.createElement("span");
    chevron.className = "row-chevron";
    chevron.setAttribute("aria-hidden", "true");
    chevron.textContent = "›";
    button.append(mark, copy, chevron);
    button.addEventListener("click", () => {
      selectedId = credential.id;
      clearRevealedPassword();
      render();
    });
    item.append(button);
    listElement.append(item);
  }

  if (credentials.length > 0 && filtered.length === 0) {
    const emptyResult = document.createElement("li");
    emptyResult.className = "no-results";
    emptyResult.textContent = "No hay accesos que coincidan con la búsqueda.";
    listElement.append(emptyResult);
  }
}

function clearRevealedPassword() {
  window.clearTimeout(revealTimeout);
  revealTimeout = undefined;
}

function renderDetail() {
  const credential = selectedCredential();
  detailPlaceholder.hidden = Boolean(credential);
  detailElement.hidden = !credential;

  if (!credential) {
    detailElement.replaceChildren();
    return;
  }

  detailElement.replaceChildren();
  const heading = document.createElement("header");
  heading.className = "detail-heading";
  const mark = document.createElement("span");
  mark.className = "site-mark";
  mark.dataset.tone = String(credential.site.length % 4);
  mark.setAttribute("aria-hidden", "true");
  mark.textContent = credential.site.trim().charAt(0) || "?";
  const title = document.createElement("div");
  const site = document.createElement("h3");
  site.textContent = credential.site;
  const caption = document.createElement("p");
  caption.textContent = "Acceso personal";
  title.append(site, caption);
  heading.append(mark, title);
  detailElement.append(heading);

  const emailField = createDetailField("Email o usuario", credential.email, {
    copy: true,
    valueToCopy: credential.email,
  });
  const passwordField = createDetailField("Contraseña", credential.password, {
    copy: true,
    valueToCopy: credential.password,
    password: true,
  });
  detailElement.append(emailField, passwordField);
  const exposureCount = passwordExposureCounts[credential.id] ?? 0;
  if (exposureCount > 0) {
    const warning = document.createElement("p");
    warning.className = "exposure-warning";
    warning.setAttribute("role", "alert");
    warning.textContent =
      `Esta contraseña aparece ${exposureCount} veces en filtraciones conocidas. Cámbiala en ese servicio y no la reutilices.`;
    detailElement.append(warning);
  }

  const actions = document.createElement("footer");
  actions.className = "detail-actions";
  if (/^[^\s@]+@[^\s@]+$/.test(credential.email)) {
    const checkEmail = document.createElement("button");
    checkEmail.type = "button";
    checkEmail.className = "text-button email-breach-check";
    checkEmail.textContent = "Comprobar exposición del correo";
    checkEmail.addEventListener("click", openEmailBreachCheck);
    actions.append(checkEmail);
  }
  const edit = document.createElement("button");
  edit.type = "button";
  edit.className = "text-button";
  edit.textContent = "Editar acceso";
  edit.addEventListener("click", () => openDialog(credential));

  const remove = document.createElement("button");
  remove.type = "button";
  remove.className = "text-button danger";
  remove.textContent = "Eliminar";
  remove.addEventListener("click", () => removeCredential(credential));
  actions.append(edit, remove);
  detailElement.append(actions);
}

function createDetailField(label, value, options = {}) {
  const field = document.createElement("div");
  field.className = "detail-field";
  const labelElement = document.createElement("span");
  labelElement.className = "detail-label";
  labelElement.textContent = label;
  const valueRow = document.createElement("div");
  valueRow.className = "detail-value-row";
  const valueElement = document.createElement("span");
  valueElement.className = "detail-value";
  valueElement.textContent = options.password ? "••••••••••••" : value;

  if (options.password) {
    valueElement.classList.add("password-hidden");
  }

  const buttons = document.createElement("span");
  buttons.className = "inline-actions";

  if (options.password) {
    let isRevealed = false;
    const reveal = makeIconButton("Mostrar contraseña durante 10 segundos", "eye", () => {
      if (isRevealed) {
        isRevealed = false;
        window.clearTimeout(revealTimeout);
        valueElement.textContent = "••••••••••••";
        valueElement.classList.add("password-hidden");
        reveal.setAttribute("aria-label", "Mostrar contraseña durante 10 segundos");
        reveal.title = "Mostrar contraseña durante 10 segundos";
        return;
      }

      isRevealed = true;
      valueElement.textContent = value;
      valueElement.classList.remove("password-hidden");
      reveal.setAttribute("aria-label", "Ocultar contraseña");
      reveal.title = "Ocultar contraseña";
      window.clearTimeout(revealTimeout);
      revealTimeout = window.setTimeout(() => {
        isRevealed = false;
        valueElement.textContent = "••••••••••••";
        valueElement.classList.add("password-hidden");
        reveal.setAttribute("aria-label", "Mostrar contraseña durante 10 segundos");
        reveal.title = "Mostrar contraseña durante 10 segundos";
      }, 10_000);
    });
    buttons.append(reveal);
  }

  if (options.copy) {
    const copy = makeIconButton(`Copiar ${label.toLocaleLowerCase("es")}`, "copy", () => {
      copyToClipboard(options.valueToCopy, label);
    });
    buttons.append(copy);
  }

  valueRow.append(valueElement, buttons);
  field.append(labelElement, valueRow);
  return field;
}

function render() {
  renderList();
  renderDetail();
  renderPasswordExposureBanner();
}

function renderPasswordExposureBanner() {
  const exposedCount = Object.values(passwordExposureCounts)
    .filter((count) => count > 0).length;
  exposureBanner.hidden = !passwordExposureError
    && exposedCount === 0
    && !passwordExposureIsScanning;
  exposureBanner.dataset.kind = exposedCount > 0 || passwordExposureError
    ? "warning"
    : "checking";
  if (passwordExposureError) {
    exposureBanner.textContent = exposedCount > 0
      ? `${exposedCount} acceso(s) tienen contraseñas expuestas. Además, ${passwordExposureError}`
      : passwordExposureError;
  } else if (exposedCount > 0) {
    exposureBanner.textContent =
      `Se encontraron ${exposedCount} acceso(s) con contraseñas expuestas en filtraciones conocidas. Cámbialas cuanto antes.`;
  } else if (passwordExposureIsScanning) {
    exposureBanner.textContent =
      "Comprobando las contraseñas guardadas. Solo se consulta un fragmento del hash; nunca se envía la contraseña.";
  }
}

function openEmailBreachCheck() {
  if (!window.confirm(
    "Se abrirá Have I Been Pwned. PaSSword no enviará tu correo; tendrás que escribirlo tú en esa página. ¿Continuar?",
  )) {
    return;
  }
  window.bovedaDesktop.openEmailBreachCheck()
    .then(() => showToast("Se abrió Have I Been Pwned. PaSSword no envió tu correo."))
    .catch(() => showToast("No se pudo abrir Have I Been Pwned.", "error"));
}

function openDialog(credential = null) {
  form.reset();
  setPasswordInputVisibility(false);
  form.hidden = false;
  masterPasswordForm.hidden = true;
  pinSettingsForm.hidden = true;
  formError.hidden = true;
  document.querySelector("#credential-id").value = credential?.id ?? "";
  document.querySelector("#site-input").value = credential?.site ?? "";
  document.querySelector("#email-input").value = credential?.email ?? "";
  passwordInput.value = credential?.password ?? "";
  document.querySelector("#dialog-title").textContent = credential ? "Editar acceso" : "Añadir acceso";
  document.querySelector("#save-credential").textContent = credential ? "Guardar cambios" : "Guardar acceso";
  dialog.showModal();
  document.querySelector("#site-input").focus();
}

async function saveCredential(event) {
  event.preventDefault();
  if (!vaultKey || !currentUser || !form.reportValidity()) {
    return;
  }

  const activeKey = vaultKey;
  const userId = currentUser.uid;
  const sessionId = vaultSessionId;
  const id = document.querySelector("#credential-id").value;
  const credential = {
    id: id || crypto.randomUUID(),
    site: document.querySelector("#site-input").value.trim(),
    email: document.querySelector("#email-input").value.trim(),
    password: passwordInput.value,
  };

  if (!credential.site || !credential.email || !credential.password) {
    formError.textContent = "Completa el sitio, el email o usuario y la contraseña.";
    formError.hidden = false;
    return;
  }

  const fields = {
    site: credential.site,
    email: credential.email,
    password: credential.password,
  };
  const saveButton = document.querySelector("#save-credential");
  saveButton.disabled = true;
  let encrypted;
  try {
    encrypted = await encryptCredential(activeKey, userId, credential.id, fields, vaultKeyGeneration);
  } catch {
    saveButton.disabled = false;
    formError.textContent = "No se pudo cifrar el acceso. No se guardó ningún dato.";
    formError.hidden = false;
    return;
  }
  saveButton.disabled = false;
  if (vaultSessionId !== sessionId || vaultKey !== activeKey || currentUser?.uid !== userId) {
    return;
  }

  const existingIndex = credentials.findIndex((entry) => entry.id === id);
  if (existingIndex >= 0) {
    credentials[existingIndex] = credential;
  } else {
    credentials.unshift(credential);
  }

  selectedId = credential.id;
  clearRevealedPassword();
  dialog.close();
  render();
  try {
    trackPendingWrite(
      firebaseClient.saveEncryptedCredential(userId, credential.id, encrypted),
      "No se pudo sincronizar el acceso. Sigue disponible en esta sesión y volverá a intentarse al reconectar.",
    );
    showToast(existingIndex >= 0 ? "Cambios cifrados; sincronización en curso." : "Acceso cifrado; sincronización en curso.");
  } catch {
    syncError = true;
    updateSyncStatus();
    showToast("No se pudo iniciar la sincronización del acceso.", "error");
  }
}

function removeCredential(credential) {
  if (!window.confirm(`¿Eliminar el acceso de ${credential.site}?`)) {
    return;
  }

  const index = credentials.findIndex((entry) => entry.id === credential.id);
  if (index < 0) {
    showToast("No se encontró el acceso. Actualiza la lista e inténtalo de nuevo.", "error");
    return;
  }

  credentials.splice(index, 1);
  selectedId = credentials[0]?.id ?? null;
  clearRevealedPassword();
  render();
  try {
    trackPendingWrite(
      firebaseClient.deleteEncryptedCredential(currentUser.uid, credential.id),
      "No se pudo sincronizar la eliminación. Vuelve a intentarlo cuando haya conexión.",
    );
    showToast("Acceso eliminado; sincronización en curso.");
  } catch {
    syncError = true;
    updateSyncStatus();
    showToast("No se pudo iniciar la sincronización de la eliminación.", "error");
  }
}

async function copyToClipboard(value, label) {
  if (!navigator.clipboard?.writeText) {
    showToast("El portapapeles no está disponible en este navegador o contexto.", "error");
    return;
  }

  try {
    await navigator.clipboard.writeText(value);
    showToast(`${label} copiado al portapapeles.`);
  } catch {
    showToast("No se pudo copiar. Revisa los permisos del portapapeles e inténtalo de nuevo.", "error");
  }
}

function handleGeneratePassword() {
  try {
    passwordInput.value = generatePassword();
    setPasswordInputVisibility(true);
    passwordInput.focus();
    showToast("Contraseña de 12 caracteres generada. Puedes editarla.");
    window.clearTimeout(passwordVisibilityTimeout);
    passwordVisibilityTimeout = window.setTimeout(() => {
      setPasswordInputVisibility(false);
    }, 5000);
  } catch {
    showToast("No se pudo acceder a la aleatoriedad segura de este navegador.", "error");
  }
}

function setPasswordInputVisibility(visible) {
  window.clearTimeout(passwordVisibilityTimeout);
  passwordVisibilityTimeout = undefined;
  passwordInput.type = visible ? "text" : "password";
  passwordVisibilityButton.setAttribute("aria-pressed", String(visible));
  passwordVisibilityButton.setAttribute("aria-label", visible ? "Ocultar contraseña" : "Ver contraseña");
  passwordVisibilityButton.title = visible ? "Ocultar contraseña" : "Ver contraseña";
  passwordVisibilityButton.querySelector("span").textContent = visible ? "Ocultar" : "Ver";
}

document.querySelector("#add-credential").addEventListener("click", () => openDialog());
document.querySelector("#detail-back").addEventListener("click", () => {
  selectedId = null;
  clearRevealedPassword();
  render();
});
document.querySelector("#generate-password").addEventListener("click", handleGeneratePassword);
pinRecoveryButton.addEventListener("click", () => {
  if (!currentUser || !pendingPinKey) {
    return;
  }
  pinResetRequested = true;
  pendingPinKey = null;
  setVaultFormMode("unlock", "Introduce la clave de recuperación para elegir un PIN nuevo.");
  masterPasswordInput.focus();
});
passwordVisibilityButton.addEventListener("click", () => {
  setPasswordInputVisibility(passwordInput.type === "password");
});
changePinButton.addEventListener("click", openPinSettingsDialog);
configureBiometricButton.addEventListener("click", openBiometricSetupDialog);
googleSignInButton.addEventListener("click", signIn);
vaultForm.addEventListener("submit", (event) => {
  if (vaultMode === "pin-create" || vaultMode === "pin-unlock") {
    void submitPin(event);
  } else {
    void submitVault(event);
  }
});
biometricUnlockButton.addEventListener("click", unlockWithBiometric);
masterPasswordForm.addEventListener("submit", changeMasterPassword);
pinSettingsForm.addEventListener("submit", changePin);
biometricSetupForm.addEventListener("submit", setupBiometricUnlock);
document.querySelector("#sign-out").addEventListener("click", signOut);
forgetDeviceKeyButton.addEventListener("click", forgetDeviceKey);
accountMenu.addEventListener("click", (event) => {
  if (event.target.closest("button")) {
    accountMenu.open = false;
  }
});
document.addEventListener("pointerdown", (event) => {
  if (!accountMenu.contains(event.target)) {
    accountMenu.open = false;
  }
});
document.querySelectorAll(".close-dialog").forEach((button) => {
  button.addEventListener("click", () => dialog.close());
});
form.addEventListener("submit", saveCredential);
searchInput.addEventListener("input", renderList);
document.addEventListener("keydown", (event) => {
  if (event.key === "/" && !dialog.open && !["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) {
    event.preventDefault();
    searchInput.focus();
  }
});
dialog.addEventListener("close", () => {
  form.hidden = false;
  masterPasswordForm.hidden = true;
  biometricSetupForm.hidden = true;
  pinSettingsForm.hidden = true;
  document.querySelector("#dialog-title").textContent = "Añadir acceso";
  setPasswordInputVisibility(false);
  passwordInput.value = "";
  currentMasterPasswordInput.value = "";
  newMasterPasswordInput.value = "";
  confirmMasterPasswordInput.value = "";
  biometricMasterPasswordInput.value = "";
  currentPinInput.value = "";
  newPinInput.value = "";
  confirmPinInput.value = "";
  masterPasswordError.hidden = true;
  biometricSetupError.hidden = true;
  pinSettingsError.hidden = true;
});

window.addEventListener("online", updateSyncStatus);
window.addEventListener("offline", updateSyncStatus);

render();
setVaultFormMode("sign-in");
updateSyncStatus();

async function startApplication() {
  try {
    biometricUnlockAvailable = await isBiometricUnlockAvailable();
  } catch {
    showToast("No se pudo comprobar la disponibilidad del desbloqueo del dispositivo.", "error");
  }

  try {
    firebaseClient = await import("./firebase-client.js");
    await firebaseClient.getSignInRedirectResult();
    googleSignInButton.disabled = false;
    firebaseClient.observeAuth(
      (user) => void handleAuthState(user),
      () => showAuthMessage("No se pudo comprobar la sesión de Google. Recarga la página e inténtalo de nuevo."),
    );
    updateSyncStatus();
  } catch {
    showAuthMessage("No se pudo iniciar Firebase. Comprueba la conexión y la configuración de esta aplicación.");
  }
}

void startApplication();
