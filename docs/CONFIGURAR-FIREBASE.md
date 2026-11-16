# Configuración Firebase del proyecto

El proyecto `gestor-pass-b60d6` proporciona Firebase Authentication y Cloud
Firestore a los clientes de escritorio y Android nativo. Firebase Hosting y la
interfaz web ya no forman parte del producto. Firebase no permite borrar el
sitio Hosting predeterminado, así que su contenido se sustituyó por una página
404; la aplicación web y sus recursos ya no se sirven.

La configuración del cliente Firebase incluye una API key pública; no es una
clave de cifrado ni una credencial privada. No añadir cuentas de servicio,
claves privadas, keystores ni contraseñas al repositorio.

## Configuración

- La app Firebase usada por el cliente de escritorio está configurada en
  `desktop/ui/firebase-config.js`.
- Firebase Authentication y el proveedor Google están habilitados.
- `localhost` y `127.0.0.1` están autorizados para el inicio de sesión de
  escritorio.
- Firestore Standard está configurado; sus reglas e índices se mantienen en
  `desktop/ui/firestore.rules` y `desktop/ui/firestore.indexes.json`.
- La app Android Flutter está registrada en Firebase con su identificador
  `password.app.flutter` y su certificado de firma.

## Seguridad

Los datos de sitio, usuario y contraseña se cifran en el cliente antes de
cualquier escritura. La API key pública, una URL o Google Login nunca se usan
como clave de cifrado. No activar Analytics ni añadir contenido real a
Firestore.

La configuración Firebase está en la raíz (`.firebaserc` y `firebase.json`).
`firebase.json` solo declara reglas e índices de Firestore; no contiene una
configuración de Hosting. No vuelvas a desplegar Hosting desde este proyecto.
