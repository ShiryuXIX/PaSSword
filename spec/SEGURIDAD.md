# Modelo y límites de seguridad

## Activos que proteger

- Sitios web, emails y contraseñas guardados.
- Claves de cifrado y cualquier material de desbloqueo de la bóveda.
- Copias offline, cambios pendientes de sincronización, exportaciones y contenido copiado.
- Autorización para leer, modificar, eliminar o compartir cada credencial.

## Controles obligatorios

- Cifrado autenticado en cliente antes de cualquier escritura a Firestore.
- Aleatoriedad criptográfica para claves, sales, nonces y generación de contraseñas; derivación de claves con sal aleatoria.
- Contraseña maestra nunca persistida. La `CryptoKey` no exportable se guarda en IndexedDB por UID para comodidad en dispositivos de confianza; la referencia activa y el material descifrado se borran al bloquear o cerrar sesión.
- Reglas Firestore con denegación por defecto y autorización por identidad y recurso; no confiar en controles de interfaz.
- Secretos ocultos por defecto y ausencia de secretos en URLs, logs, telemetría, notificaciones y mensajes de error.
- Estados offline/sincronización explícitos; no afirmar éxito mientras existan escrituras pendientes o fallidas.

## Comprobaciones de exposición

- Con la bóveda abierta, PaSSword comprueba las contraseñas guardadas con
  Pwned Passwords de Have I Been Pwned cada siete días; una contraseña nueva
  o modificada se comprueba al sincronizar el cambio.
- El SHA-1 completo se calcula en el dispositivo. Solo se solicita el rango de
  los primeros cinco caracteres, por HTTPS y con padding; la contraseña y el
  hash completo no se envían ni se guardan. La consulta de rango puede revelar
  información parcial, especialmente para contraseñas débiles.
- El resultado, el identificador de acceso, la fecha y una huella SHA-256 del
  documento cifrado se guardan solo en el dispositivo para detectar cambios y
  evitar avisos repetidos. En Android se usa almacenamiento seguro; en Windows,
  almacenamiento local de la aplicación. No se sincronizan esos resultados.
- La comprobación de emails es manual: tras confirmarlo, PaSSword abre la
  página general de Have I Been Pwned sin incluir el email en la URL. La persona
  escribe allí el correo; ese servicio recibe la consulta.
- Los resultados reflejan las contraseñas y filtraciones conocidas por HIBP.
  No garantizan cobertura de todas las filtraciones ni de toda la dark web.
  Si no hay conexión, la comprobación falla visiblemente y se vuelve a intentar.

## Diseño criptográfico implementado

- Derivación con PBKDF2-HMAC-SHA-256, 600 000 iteraciones y sal aleatoria de 16 bytes.
- Cifrado autenticado AES-256-GCM, nonce aleatorio de 12 bytes y clave no exportable.
- AAD liga cada documento cifrado a la versión, al UID autenticado y al identificador de credencial.
- Los nuevos documentos vinculan además la generación de clave en el AAD. La rotación cifra todos los documentos, asigna IDs nuevas y cambia la generación en una operación Firestore atómica, con un máximo de 249 credenciales (499 escrituras). Un bloqueo temporal en metadata impide escrituras o borrados concurrentes durante la preparación; las IDs nuevas evitan que un borrado antiguo en cola afecte al documento recifrado. Las reglas aceptan documentos heredados sin generación solo mientras la generación activa sea 1 y bloquean escrituras antiguas tras rotar.
- La meta de bóveda almacena la sal y un verificador cifrado, no la contraseña maestra ni la clave. Esto permite comprobar el desbloqueo incluso cuando aún no hay credenciales.
- Contraseña maestra separada de Google. Se pide al crear la bóveda y una vez en cada navegador/dispositivo nuevo. La clave AES no exportable se recuerda en IndexedDB por UID y se reutiliza solo después de iniciar sesión con Google. Perder la maestra y no disponer de ningún dispositivo configurado hace irrecuperable la bóveda.
- El desbloqueo opcional del dispositivo usa WebAuthn con verificación de usuario obligatoria y la extensión PRF. La salida PRF, ligada a la credencial y a una sal aleatoria, envuelve la llave de la bóveda con AES-GCM; IndexedDB conserva la credencial y el texto cifrado, no la llave en claro. Google sigue identificando la cuenta y la contraseña maestra sigue siendo el método de recuperación. El dispositivo puede solicitar huella, rostro o PIN según el autenticador; la aplicación no controla cuál.
- No se consultan ni almacenan datos biométricos, y la salida PRF y la llave envuelta permanecen en el dispositivo. Si el navegador/autenticador no admite PRF, se mantiene el desbloqueo con contraseña maestra. Al cambiar la contraseña maestra se elimina el registro biométrico local para evitar conservar una llave obsoleta; el usuario puede volver a configurarlo tras desbloquear con la nueva contraseña.
- Los bytes temporales de contraseña/datos se limpian en lo posible; JavaScript no permite garantizar la eliminación inmediata de strings o copias del heap.

La capa criptográfica cuenta con pruebas para ida/vuelta, formato, campos exactos, integridad, vinculación a UID/ID y contraseña incorrecta. La integración Firebase completa aún debe probarse antes de considerar resuelta la seguridad.

## Riesgos y decisiones pendientes

La autenticación de Google identifica la cuenta, pero no constituye por sí sola una clave de cifrado. En los dispositivos configurados, Google autoriza la reutilización de una `CryptoKey` no exportable guardada localmente; en dispositivos nuevos sigue siendo necesaria la contraseña maestra. No hay recuperación si se pierde la contraseña maestra y no queda ningún dispositivo configurado.

Compartir queda fuera de la primera versión. Requeriría un mecanismo de cifrado de extremo a extremo y distribución de claves por destinatario, así como aceptación y autorización verificables; no se implementará sin poder validar el flujo completo.

La persistencia offline puede dejar datos cifrados localmente y cambios pendientes. Se eligió permitirla solo en dispositivos personales de confianza. Además de los documentos cifrados de Firestore, el navegador conserva la clave no exportable en IndexedDB; el código del mismo origen puede utilizarla, por lo que un XSS o compromiso del sitio puede exponer la bóveda durante una sesión autenticada. El bloqueo tras 5 minutos cierra también la sesión de Google; volver a iniciar sesión permite reutilizar la clave local. «Olvidar este dispositivo» elimina esa clave. Se probó una cola offline en Brave mientras otro cliente sincronizaba un cambio: al reconectar, Brave confirmó su escritura y esta prevaleció.

Con el desbloqueo WebAuthn PRF, la llave de la bóveda no se recupera automáticamente al iniciar sesión con Google: la persona debe activar expresamente el gesto de desbloqueo del dispositivo. La contraseña maestra permite recuperar el acceso; no se debe habilitar el autodesbloqueo simple de la CryptoKey mientras un registro biométrico esté activo. La compatibilidad PRF depende del navegador y del autenticador y debe validarse en cada dispositivo antes de confiar en esta opción.

El propietario limita el uso offline a dispositivos personales de confianza. Firestore puede conservar localmente documentos cifrados incluso después de bloquear o cerrar sesión; el bloqueo borra la clave y los datos descifrados de memoria, pero la clave no exportable recordada permanece hasta olvidarla o borrar los datos del navegador. No equivale a protección frente a código malicioso del mismo origen ni frente a alguien que controle una sesión Google autenticada en ese perfil. Ante pérdida o uso compartido de un dispositivo, se deben revocar sesiones de Google y borrar los datos del navegador; no se puede borrar remotamente esa caché ni la clave local desde este producto.

El propietario eligió last-write-wins para ediciones concurrentes. Firestore no compara la antigüedad semántica de los cambios: la última escritura confirmada gana, por lo que una edición offline antigua puede sobrescribir datos más recientes cuando se reconecte. La prueba con dos clientes independientes confirmó este comportamiento: la edición offline sincronizada al final sobrescribió el valor online anterior. El usuario debe considerar este riesgo al usar la bóveda en varios dispositivos.

El cambio de contraseña solo se permite con conexión y sin cambios pendientes; si supera el límite de 249 accesos, la operación se aborta. El bloqueo evita cambios concurrentes mientras se recifra, la generación rechaza escrituras antiguas y las IDs nuevas evitan borrados antiguos sobre documentos recifrados. No resuelve conflictos offline normales antes de cambiar la contraseña: esos siguen sujetos a last-write-wins.
