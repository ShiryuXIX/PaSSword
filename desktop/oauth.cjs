const crypto = require("node:crypto");
const http = require("node:http");

const GOOGLE_AUTHORIZATION_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const OAUTH_TIMEOUT_MS = 5 * 60 * 1000;

async function requestGoogleIdentityToken(
  clientId,
  {
    clientSecret,
    openExternal,
    fetchImpl = fetch,
    timeoutMs = OAUTH_TIMEOUT_MS,
  },
) {
  if (
    typeof clientId !== "string"
    || !clientId.endsWith(".apps.googleusercontent.com")
  ) {
    throw createOAuthError(
      "desktop/oauth-client-missing",
      "Configura el cliente OAuth de escritorio para iniciar sesión.",
    );
  }
  if (typeof openExternal !== "function" || typeof fetchImpl !== "function") {
    throw new TypeError("Faltan dependencias para iniciar la autenticación de escritorio.");
  }
  if (clientSecret !== undefined && typeof clientSecret !== "string") {
    throw new TypeError("El secreto opcional del cliente OAuth no es válido.");
  }

  const codeVerifier = crypto.randomBytes(32).toString("base64url");
  const codeChallenge = crypto
    .createHash("sha256")
    .update(codeVerifier)
    .digest("base64url");

  try {
    const authorization = await requestAuthorizationCode(clientId, codeChallenge, {
      openExternal,
      timeoutMs,
      silent: true,
    }).catch((error) => {
      if (error.code !== "desktop/oauth-interaction-required") {
        throw error;
      }
      return requestAuthorizationCode(clientId, codeChallenge, {
        openExternal,
        timeoutMs,
        silent: false,
      });
    });

    let tokenResponse;
    try {
      const tokenParameters = new URLSearchParams({
        client_id: clientId,
        code: authorization.code,
        code_verifier: codeVerifier,
        grant_type: "authorization_code",
        redirect_uri: authorization.redirectUri,
      });
      if (clientSecret) {
        tokenParameters.set("client_secret", clientSecret);
      }
      tokenResponse = await fetchImpl(GOOGLE_TOKEN_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: tokenParameters,
      });
    } catch (error) {
      throw createOAuthError(
        "desktop/oauth-token-network",
        "No se pudo conectar con el servicio de autenticación de Google.",
        error?.cause?.code,
      );
    }

    const tokens = await tokenResponse.json().catch(() => null);
    if (!tokenResponse.ok || typeof tokens?.id_token !== "string") {
      const googleErrorCodes = new Map([
        ["invalid_client", "desktop/oauth-google-invalid-client"],
        ["invalid_grant", "desktop/oauth-google-invalid-grant"],
        ["unauthorized_client", "desktop/oauth-google-unauthorized-client"],
        ["invalid_request", "desktop/oauth-google-invalid-request"],
        ["invalid_scope", "desktop/oauth-google-invalid-scope"],
      ]);
      if (googleErrorCodes.has(tokens?.error)) {
        const code = googleErrorCodes.get(tokens.error);
        throw createOAuthError(
          code,
          "Google rechazó la solicitud de inicio de sesión.",
          tokens.error === "invalid_request"
            ? classifyInvalidRequest(tokens, tokenResponse.status)
            : tokens.error,
        );
      }
      throw createOAuthError(
        "desktop/oauth-token-exchange",
        "Google no pudo completar el inicio de sesión.",
        `http-${tokenResponse.status}`,
      );
    }

    return tokens.id_token;
  } catch (error) {
    if (typeof error?.code === "string" && error.code.startsWith("desktop/oauth-")) {
      throw error;
    }
    throw createOAuthError(
      "desktop/oauth-internal-error",
      "Se produjo un error inesperado durante el inicio de sesión.",
      safeDiagnosticCode(error?.code),
    );
  }
}

async function requestAuthorizationCode(clientId, codeChallenge, {
  openExternal,
  timeoutMs,
  silent,
}) {
  const state = crypto.randomBytes(32).toString("base64url");
  const server = http.createServer();

  try {
    const port = await listenOnLoopback(server);
    const redirectUri = `http://127.0.0.1:${port}`;
    const authorizationUrl = new URL(GOOGLE_AUTHORIZATION_ENDPOINT);
    const parameters = new URLSearchParams({
      client_id: clientId,
      code_challenge: codeChallenge,
      code_challenge_method: "S256",
      redirect_uri: redirectUri,
      response_type: "code",
      scope: "openid email profile",
      state,
    });
    if (silent) {
      parameters.set("prompt", "none");
    }
    authorizationUrl.search = parameters.toString();

    const code = await waitForAuthorizationCode({
      server,
      state,
      authorizationUrl: authorizationUrl.toString(),
      openExternal,
      timeoutMs,
    });
    return { code, redirectUri };
  } finally {
    try {
      await closeServer(server);
    } catch (error) {
      throw createOAuthError(
        "desktop/oauth-cleanup",
        "No se pudo cerrar el servicio local de inicio de sesión.",
        safeDiagnosticCode(error?.code),
      );
    }
  }
}

function waitForAuthorizationCode({
  server,
  state,
  authorizationUrl,
  openExternal,
  timeoutMs,
}) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const timeout = setTimeout(() => {
      finish(createOAuthError(
        "desktop/oauth-timeout",
        "Se agotó el tiempo de inicio de sesión. Vuelve a intentarlo.",
      ));
    }, timeoutMs);

    function finish(error, code) {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timeout);
      if (error) {
        reject(error);
      } else {
        resolve(code);
      }
    }

    server.on("request", (request, response) => {
      const callbackUrl = new URL(request.url, "http://127.0.0.1");
      if (request.method !== "GET" || callbackUrl.pathname !== "/") {
        response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
        response.end("No encontrado.");
        return;
      }

      const receivedState = callbackUrl.searchParams.get("state");
      if (!sameSecret(receivedState, state)) {
        response.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
        response.end("La solicitud de inicio de sesión no es válida.");
        return;
      }

      const providerError = callbackUrl.searchParams.get("error");
      if (providerError) {
        response.writeHead(200, callbackHeaders());
        const oauthErrors = new Map([
          ["access_denied", ["desktop/oauth-cancelled", "Se canceló el inicio de sesión con Google."]],
          ["login_required", ["desktop/oauth-interaction-required", "Google necesita que confirmes el inicio de sesión."]],
          ["interaction_required", ["desktop/oauth-interaction-required", "Google necesita que confirmes el inicio de sesión."]],
          ["consent_required", ["desktop/oauth-interaction-required", "Google necesita que confirmes el acceso de PaSSword."]],
          ["account_selection_required", ["desktop/oauth-interaction-required", "Google necesita que confirmes la cuenta."]],
          ["invalid_client", ["desktop/oauth-client-invalid", "Google rechazó el cliente OAuth de escritorio."]],
          ["redirect_uri_mismatch", ["desktop/oauth-redirect-invalid", "Google rechazó la dirección de retorno OAuth."]],
        ]);
        const [errorCode, errorMessage] = oauthErrors.get(providerError)
          ?? ["desktop/oauth-provider-failed", "Google no pudo completar la autorización."];
        response.end(callbackPage());
        finish(createOAuthError(errorCode, errorMessage));
        return;
      }

      const authorizationCode = callbackUrl.searchParams.get("code");
      if (!authorizationCode) {
        response.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
        response.end("Google no devolvió un código de autorización.");
        finish(createOAuthError(
          "desktop/oauth-response-invalid",
          "Google devolvió una respuesta de inicio de sesión no válida.",
        ));
        return;
      }

      response.writeHead(200, callbackHeaders());
      response.end(callbackPage());
      finish(null, authorizationCode);
    });

    try {
      void Promise.resolve(openExternal(authorizationUrl)).catch(() => {
        finish(createOAuthError(
          "desktop/oauth-browser",
          "No se pudo abrir el navegador para iniciar sesión.",
        ));
      });
    } catch {
      finish(createOAuthError(
        "desktop/oauth-browser",
        "No se pudo abrir el navegador para iniciar sesión.",
      ));
    }
  });
}

function sameSecret(received, expected) {
  if (typeof received !== "string" || received.length !== expected.length) {
    return false;
  }
  return crypto.timingSafeEqual(Buffer.from(received), Buffer.from(expected));
}

function callbackPage() {
  return '<!doctype html><html><head><meta charset="utf-8"><meta name="referrer" content="no-referrer"><title></title></head><body><script>window.close();window.location.replace("about:blank");</script></body></html>';
}

function callbackHeaders() {
  return {
    "Cache-Control": "no-store",
    "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
    "Content-Type": "text/html; charset=utf-8",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
  };
}

function listenOnLoopback(server) {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.removeListener("error", reject);
      resolve(server.address().port);
    });
  });
}

function closeServer(server) {
  if (!server.listening) {
    return Promise.resolve();
  }
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
    server.closeAllConnections();
  });
}

function createOAuthError(code, message, diagnosticDetail) {
  const error = new Error(message);
  error.code = code;
  if (typeof diagnosticDetail === "string" && /^[a-z0-9_-]{1,48}$/i.test(diagnosticDetail)) {
    error.diagnosticDetail = diagnosticDetail;
  }
  return error;
}

function safeDiagnosticCode(code) {
  return typeof code === "string" && /^[a-z0-9_-]{1,48}$/i.test(code)
    ? code
    : "unclassified";
}

function classifyInvalidRequest(response, status) {
  const description = typeof response.error_description === "string"
    ? response.error_description.toLowerCase()
    : "";
  const missingParameter = description.match(
    /missing (?:the )?required parameter\s*[:'"`']?\s*(client_id|code|code_verifier|grant_type|redirect_uri)\b/,
  )?.[1];
  if (missingParameter) {
    return `http-${status}-missing-${missingParameter.replaceAll("_", "-")}`;
  }
  const invalidParameter = description.match(
    /invalid (?:parameter|value)(?:\s+for)?\s*[:'"`']?\s*(client_id|code|code_verifier|grant_type|redirect_uri)\b/,
  )?.[1];
  if (invalidParameter) {
    return `http-${status}-invalid-${invalidParameter.replaceAll("_", "-")}`;
  }
  if (/client[_ -]?secret.{0,30}(?:missing|required|invalid|unsupported|not supported)/.test(description)) {
    const reason = description.match(
      /(?:missing|required|invalid|unsupported|not supported)/,
    )?.[0]?.replaceAll(" ", "-");
    return `http-${status}-client-secret-${reason}`;
  }
  if (/(?:missing|required|invalid|unsupported|not supported).{0,30}client[_ -]?secret/.test(description)) {
    const reason = description.match(
      /(?:missing|required|invalid|unsupported|not supported)/,
    )?.[0]?.replaceAll(" ", "-");
    return `http-${status}-client-secret-${reason}`;
  }
  if (!description) {
    return `http-${status}-no-description`;
  }
  const mentionedParameter = [
    ["redirect_uri", /\bredirect[_ -]?uri\b/],
    ["code_verifier", /\bcode[_ -]?verifier\b|\bpkce\b|\bchallenge\b/],
    ["client_id", /\bclient[_ -]?id\b/],
    ["client_secret", /\bclient[_ -]?secret\b/],
    ["grant_type", /\bgrant[_ -]?type\b/],
    ["code", /\bauthorization code\b|\bauthentication code\b/],
  ].find(([, pattern]) => pattern.test(description))?.[0];
  if (mentionedParameter) {
    return `http-${status}-mentions-${mentionedParameter.replaceAll("_", "-")}`;
  }
  return `http-${status}-generic-description`;
}

module.exports = { requestGoogleIdentityToken };
