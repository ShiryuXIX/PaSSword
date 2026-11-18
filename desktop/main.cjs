const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const http = require("node:http");
const path = require("node:path");
const { app, BrowserWindow, dialog, ipcMain, safeStorage, shell } = require("electron");
const { autoUpdater } = require("electron-updater");
const { appendAuthFailure } = require("./auth-diagnostics.cjs");
const { setDesktopAppVersion } = require("./index-html.cjs");
const { requestGoogleIdentityToken } = require("./oauth.cjs");
const { createPinStore } = require("./pin-store.cjs");

const DESKTOP_SERVER_PORT = 43183;

const CONTENT_TYPES = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".webmanifest", "application/manifest+json; charset=utf-8"],
]);

let localServer;
let localOrigin;
let mainWindow;
let pinStore;

app.whenReady().then(async () => {
  try {
    localOrigin = await startLocalServer();
    pinStore = createPinStore({
      filePath: path.join(app.getPath("userData"), "desktop-pin.json"),
      safeStorage,
    });
    registerOAuthHandler();
    registerPinHandlers();
    registerEmailBreachCheckHandler();
    await createMainWindow();
    checkForUpdates();
  } catch (error) {
    console.error("No se pudo iniciar PaSSword.", error);
    dialog.showErrorBox(
      "PaSSword no pudo iniciarse",
      error.code === "EADDRINUSE"
        ? `El puerto local ${DESKTOP_SERVER_PORT} está ocupado. Cierra la aplicación que lo está usando e inténtalo de nuevo.`
        : "No se pudieron preparar los archivos locales de la aplicación. Reinstala PaSSword o consulta la guía de escritorio.",
    );
    app.quit();
  }
});

app.on("before-quit", () => {
  localServer?.close();
});

app.on("window-all-closed", () => {
  app.quit();
});

async function startLocalServer() {
  const uiRoot = path.join(app.getAppPath(), "desktop", "ui");
  const bundlePath = path.join(app.getAppPath(), "desktop", "generated", "app.bundle.js");
  const server = http.createServer(async (request, response) => {
    const address = server.address();
    const expectedHost = `localhost:${address.port}`;
    if (request.headers.host !== expectedHost) {
      response.writeHead(421).end();
      return;
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      response.writeHead(405, { Allow: "GET, HEAD" }).end();
      return;
    }

    let filePath;
    let isDesktopBundle = false;
    try {
      const requestUrl = new URL(request.url, localOrigin || "http://localhost");
      const decodedPath = decodeURIComponent(requestUrl.pathname);
      isDesktopBundle = decodedPath === "/desktop-app.bundle.js";
      const relativePath = decodedPath === "/" ? "index.html" : decodedPath.slice(1);
      if (isDesktopBundle) {
        filePath = bundlePath;
      } else {
        filePath = path.resolve(uiRoot, relativePath);
        const fromRoot = path.relative(uiRoot, filePath);
        if (fromRoot.startsWith("..") || path.isAbsolute(fromRoot)) {
          response.writeHead(404).end();
          return;
        }
      }
    } catch {
      response.writeHead(400).end();
      return;
    }

    let contents;
    try {
      contents = await fs.readFile(filePath);
    } catch (error) {
      response.writeHead(error.code === "ENOENT" ? 404 : 500).end();
      return;
    }

    const headers = {
      "Cache-Control": "no-store",
      "Content-Type": CONTENT_TYPES.get(path.extname(filePath).toLowerCase()) ?? "application/octet-stream",
      "Content-Security-Policy": createContentSecurityPolicy(),
      "Permissions-Policy": "publickey-credentials-create=(self), publickey-credentials-get=(self)",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
    };
    if (path.basename(filePath) === "index.html") {
      contents = Buffer.from(setDesktopAppVersion(contents.toString("utf8"), app.getVersion())
        .replace(/<script type="importmap">[\s\S]*?<\/script>\s*/, "")
        .replace(
          '<script type="module" src="./app.js"></script>',
          '<script type="module" src="/desktop-app.bundle.js"></script>',
        ));
    }

    response.writeHead(200, headers);
    response.end(request.method === "HEAD" ? undefined : contents);
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(DESKTOP_SERVER_PORT, "127.0.0.1", () => {
      server.removeListener("error", reject);
      resolve();
    });
  });
  localServer = server;
  return `http://localhost:${DESKTOP_SERVER_PORT}`;
}

async function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 820,
    minWidth: 920,
    minHeight: 660,
    title: "PaSSword",
    backgroundColor: "#111214",
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
      devTools: !app.isPackaged,
    },
  });

  mainWindow.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  mainWindow.webContents.on("will-navigate", (event, url) => {
    if (new URL(url).origin !== localOrigin) {
      event.preventDefault();
    }
  });
  await mainWindow.loadURL(localOrigin);
}

function checkForUpdates() {
  if (!app.isPackaged) return;

  autoUpdater.autoDownload = false;
  autoUpdater.autoInstallOnAppQuit = false;
  autoUpdater.on("update-available", async (update) => {
    const choice = await dialog.showMessageBox(mainWindow, {
      type: "info",
      title: "Actualización disponible",
      message: `Hay una nueva versión de PaSSword (${update.version}).`,
      detail: "¿Quieres descargarla e instalarla ahora?",
      buttons: ["Actualizar", "Más tarde"],
      defaultId: 0,
      cancelId: 1,
      noLink: true,
    });
    if (choice.response !== 0) return;

    try {
      await autoUpdater.downloadUpdate();
    } catch (error) {
      await showUpdateError("No se pudo descargar la actualización.", error);
    }
  });
  autoUpdater.on("update-downloaded", async (update) => {
    const choice = await dialog.showMessageBox(mainWindow, {
      type: "info",
      title: "Actualización lista",
      message: `PaSSword ${update.version} ya está descargada.`,
      detail: "Cierra y reinicia la aplicación para completar la actualización.",
      buttons: ["Reiniciar ahora", "Más tarde"],
      defaultId: 0,
      cancelId: 1,
      noLink: true,
    });
    if (choice.response === 0) autoUpdater.quitAndInstall();
  });

  autoUpdater.checkForUpdates().catch((error) => {
    void showUpdateError("No se pudo comprobar si hay actualizaciones.", error);
  });
}

async function showUpdateError(message, error) {
  console.error(message, error);
  if (mainWindow && !mainWindow.isDestroyed()) {
    await dialog.showMessageBox(mainWindow, {
      type: "warning",
      title: "Actualización de PaSSword",
      message,
      detail: "Comprueba tu conexión e inténtalo de nuevo al abrir la aplicación.",
      buttons: ["Aceptar"],
      noLink: true,
    });
  }
}

function registerOAuthHandler() {
  ipcMain.handle("desktop:google-sign-in", async (event) => {
    if (!isTrustedRenderer(event)) {
      return { error: { code: "desktop/request-denied", message: "La solicitud no está permitida." } };
    }

    try {
      const idToken = await requestGoogleIdentityToken(
        process.env.BOVEDA_GOOGLE_CLIENT_ID,
        {
          clientSecret: process.env.BOVEDA_GOOGLE_CLIENT_SECRET,
          openExternal: (url) => shell.openExternal(url),
        },
      );
      return { idToken };
    } catch (error) {
      const safeErrors = new Map([
        ["desktop/oauth-browser", "No se pudo abrir el navegador para iniciar sesión."],
        ["desktop/oauth-cancelled", "Se canceló el inicio de sesión con Google."],
        ["desktop/oauth-client-missing", "Configura el cliente OAuth de escritorio para iniciar sesión."],
        ["desktop/oauth-timeout", "Se agotó el tiempo de inicio de sesión. Vuelve a intentarlo."],
      ]);
      const errorCode = typeof error.code === "string" && error.code.startsWith("desktop/oauth-")
        ? error.code
        : "desktop/oauth-failed";
      return {
        error: {
          code: errorCode,
          message: safeErrors.get(errorCode) ?? "No se pudo completar el inicio de sesión con Google.",
          diagnosticDetail: error.diagnosticDetail,
        },
      };
    }
  });

  ipcMain.handle("desktop:log-auth-failure", async (event, details) => {
    if (!isTrustedRenderer(event)) {
      return { error: "No se puede guardar el diagnóstico desde esta ventana." };
    }

    const safeDetails = details && typeof details === "object" ? details : {};
    const logPath = await appendAuthFailure(app.getPath("userData"), {
      ...safeDetails,
      appVersion: app.getVersion(),
    });
    return { path: logPath };
  });

  ipcMain.handle("desktop:open-auth-diagnostics", async (event) => {
    if (!isTrustedRenderer(event)) {
      return { error: "No se puede abrir el diagnóstico desde esta ventana." };
    }

    const logPath = path.join(app.getPath("userData"), "sign-in-diagnostics.log");
    const openError = await shell.openPath(logPath);
    return openError
      ? { error: "Windows no pudo abrir el archivo de diagnóstico." }
      : { path: logPath };
  });
}

function registerPinHandlers() {
  ipcMain.handle("desktop:pin-status", async (event, userId) => {
    if (!isTrustedRenderer(event)) {
      return { error: "La solicitud del PIN no está permitida." };
    }
    return { configured: await pinStore.hasPin(userId) };
  });

  ipcMain.handle("desktop:set-pin", async (event, userId, pin) => {
    if (!isTrustedRenderer(event)) {
      return { error: "La solicitud del PIN no está permitida." };
    }
    await pinStore.setPin(userId, pin);
    return { saved: true };
  });

  ipcMain.handle("desktop:forget-pin", async (event, userId) => {
    if (!isTrustedRenderer(event)) {
      return { error: "La solicitud del PIN no está permitida." };
    }
    await pinStore.forgetPin(userId);
    return { forgotten: true };
  });

  ipcMain.handle("desktop:verify-pin", async (event, userId, pin) => {
    if (!isTrustedRenderer(event)) {
      return { error: "La solicitud del PIN no está permitida." };
    }
    return pinStore.verifyPin(userId, pin);
  });
}

function registerEmailBreachCheckHandler() {
  ipcMain.handle("desktop:open-email-breach-check", async (event) => {
    if (!isTrustedRenderer(event)) {
      return { error: "La solicitud no está permitida." };
    }
    await shell.openExternal("https://haveibeenpwned.com/");
    return { opened: true };
  });
}

function isTrustedRenderer(event) {
  if (
    event.sender !== mainWindow?.webContents
    || event.senderFrame?.url === undefined
  ) {
    return false;
  }
  try {
    return new URL(event.senderFrame.url).origin === localOrigin;
  } catch {
    return false;
  }
}

function createContentSecurityPolicy(nonce = "") {
  const scriptNonce = nonce ? ` 'nonce-${nonce}'` : "";
  return [
    "default-src 'self'",
    `script-src 'self'${scriptNonce}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: https://*.googleusercontent.com",
    "connect-src 'self' https://*.googleapis.com https://*.firebaseio.com wss://*.firebaseio.com https://*.firebaseapp.com https://api.pwnedpasswords.com",
    "frame-src https://*.firebaseapp.com",
    "worker-src 'self' blob:",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join("; ");
}
