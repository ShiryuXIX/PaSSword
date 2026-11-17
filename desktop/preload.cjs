const { contextBridge, ipcRenderer } = require("electron");

function classifyIpcFailure(error) {
  if (typeof error?.code === "string" && /^[a-z0-9_-]{1,48}$/i.test(error.code)) {
    return error.code;
  }
  if (typeof error?.message === "string") {
    if (error.message.includes("No handler registered")) {
      return "no-handler";
    }
    if (error.message.includes("Error invoking remote method")) {
      return "handler-rejected";
    }
    if (error.message.includes("render frame was disposed")) {
      return "renderer-unavailable";
    }
  }
  return "ipc-error";
}

async function invokePin(channel, ...args) {
  const result = await ipcRenderer.invoke(channel, ...args);
  if (result.error) {
    throw new Error(result.error);
  }
  return result;
}

contextBridge.exposeInMainWorld("bovedaDesktop", Object.freeze({
  signInWithGoogle: async () => {
    let result;
    try {
      result = await ipcRenderer.invoke("desktop:google-sign-in");
    } catch (cause) {
      return {
        error: {
          code: "desktop/oauth-ipc-failed",
          diagnosticDetail: classifyIpcFailure(cause),
        },
      };
    }
    return result;
  },
  logSignInFailure: async (details) => {
    const result = await ipcRenderer.invoke("desktop:log-auth-failure", details);
    if (result.error) {
      throw new Error(result.error);
    }
    return result.path;
  },
  openSignInDiagnostics: async () => {
    const result = await ipcRenderer.invoke("desktop:open-auth-diagnostics");
    if (result.error) {
      throw new Error(result.error);
    }
    return result.path;
  },
  getPinStatus: (userId) => invokePin("desktop:pin-status", userId),
  setPin: (userId, pin) => invokePin("desktop:set-pin", userId, pin),
  verifyPin: (userId, pin) => invokePin("desktop:verify-pin", userId, pin),
  openEmailBreachCheck: async () => {
    const result = await ipcRenderer.invoke("desktop:open-email-breach-check");
    if (result.error) {
      throw new Error(result.error);
    }
    return result;
  },
}));
