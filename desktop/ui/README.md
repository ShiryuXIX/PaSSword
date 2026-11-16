# Interfaz de PaSSword

La interfaz de escritorio está implementada en `index.html`, `styles.css` y `app.js`. Electron la empaqueta desde esta carpeta y la sirve en un origen local estable. No es una aplicación web desplegable: Android usa el cliente Flutter nativo.

## Estado actual

- El proyecto Firebase `gestor-pass-b60d6` se usa para Authentication y Firestore. Firebase Hosting ya no forma parte del producto.
- El código cifra los documentos con AES-256-GCM. La clave de recuperación configura la bóveda y permite configurar dispositivos nuevos. En este PC, la llave no exportable se recuerda en IndexedDB y se desbloquea con un PIN de cuatro cifras protegido por el almacenamiento seguro de Windows.
- El campo de acceso acepta un email o nombre de usuario en texto libre; no exige el carácter `@`.
- El generador produce 12 caracteres con mayúsculas, minúsculas, números y símbolos mediante `crypto.getRandomValues`.
- Se validaron con una credencial sintética el desbloqueo por el propietario, la lectura y escritura cifrada en Firestore, la edición y recarga offline, la sincronización al reconectar y el borrado remoto. Firestore Console confirmó que el documento de prueba ya no existe.
- El avatar informativo no es enfocable como control sin acción y la selección de credenciales se expone con `aria-pressed`.
- El PIN es local a este PC, puede cambiarse desde las opciones de cuenta y puede restablecerse con la clave de recuperación. Tras cinco intentos incorrectos, el acceso al PIN se pausa durante 30 segundos.
- No usar contraseñas reales hasta validar el flujo completo de autenticación, reglas, cifrado, persistencia y sincronización en el entorno real.
- El botón «Olvidar este dispositivo» elimina la clave local recordada. La bóveda permanece abierta hasta cerrar sesión; una vulnerabilidad del mismo origen podría usar la clave recordada en un perfil autenticado.
- La llave local puede olvidarse desde la interfaz. La bóveda no se bloquea automáticamente por inactividad; usa «Cerrar sesión» para bloquearla.

En dos clientes desbloqueados se comprobó la propagación en tiempo real. Además, con un cliente offline y otro conectado, se guardó primero un cambio offline y después otro online. Al reconectar, el cambio offline se sincronizó al final y prevaleció en ambos clientes, tal como establece la política last-write-wins por orden de confirmación de Firestore. La credencial sintética se eliminó al terminar. Esto confirma que una edición offline antigua sincronizada tarde puede sobrescribir datos más recientes.

Consultar [spec/REQUISITOS.md](../../spec/REQUISITOS.md) y [spec/SEGURIDAD.md](../../spec/SEGURIDAD.md).
