# Modelo y límites de seguridad

## Activos que proteger

- Sitios web, emails y contraseñas guardados.
- Claves de cifrado y cualquier material de desbloqueo de la bóveda.
- Copias offline, cambios pendientes de sincronización, exportaciones y contenido copiado.
- Autorización para leer, modificar, eliminar o compartir cada credencial.

## Controles obligatorios

- Cifrado autenticado en cliente antes de cualquier escritura a Firestore.
- Aleatoriedad criptográfica para claves, sales, nonces y generación de contraseñas; derivación de claves con sal aleatoria.
- Las nuevas bóvedas usan una llave AES aleatoria guardada en Firestore junto a una verificación cifrada. Los documentos de acceso se cifran en el cliente, pero Firebase y las personas con acceso administrativo al proyecto pueden recuperar la llave y descifrar la bóveda.
- Las bóvedas heredadas conservan su llave derivada de la clave maestra. Tras verificarla, el cliente la guarda una sola vez en el documento de recuperación de Firestore; hasta completar esa migración hace falta la clave maestra o un desbloqueo local existente.
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

- En bóvedas nuevas, llave AES aleatoria de 256 bits. Las bóvedas heredadas conservan la derivación PBKDF2-HMAC-SHA-256 (600 000 iteraciones, sal aleatoria de 16 bytes).
- Cifrado autenticado AES-256-GCM, nonce aleatorio de 12 bytes; el cliente importa la llave como no exportable para operar con ella.
- AAD liga cada documento cifrado a la versión, al UID autenticado y al identificador de credencial.
- Los documentos vinculan además la generación de clave en el AAD. Las reglas conservan la validación de generaciones anteriores; cambiar la llave desde la interfaz ya no está disponible para evitar que una actualización deje obsoleta la recuperación de Google.
- La meta de bóveda almacena la sal y un verificador cifrado. El campo `kdf` identifica las bóvedas nuevas (`RANDOM-AES-256`) y las heredadas (`PBKDF2-SHA-256`). El documento `users/{uid}/vault/recovery` contiene la llave AES codificada en Base64, validada por las reglas Firestore y creada de forma atómica junto a la meta. Las reglas permiten crearla una sola vez; no permiten leerla a otras cuentas, actualizarla ni borrarla.
- Google identifica al usuario y el cliente recupera la llave desde Firestore para abrir automáticamente la bóveda. Esta recuperación sacrifica la protección criptográfica frente al propietario/administrador del proyecto Firebase: el control por UID protege frente a otras cuentas, no frente a un administrador del proyecto.
- Para migrar una bóveda antigua se debe desbloquear una vez con su clave actual; las llaves locales no exportables de Windows no pueden convertirse por sí solas a la llave recuperable. Si se perdió la clave y no se conserva un desbloqueo válido, la bóveda antigua no puede migrarse.
- Algunas bóvedas heredadas aún conservan llaves locales y datos de desbloqueo del dispositivo; esos mecanismos solo sirven como transición y no sustituyen la migración de la llave a Firestore.
- Los bytes temporales de contraseña/datos se limpian en lo posible; JavaScript no permite garantizar la eliminación inmediata de strings o copias del heap.

La capa criptográfica cuenta con pruebas para ida/vuelta, formato, campos exactos, integridad, vinculación a UID/ID, contraseña incorrecta y formato de la llave de recuperación. El emulador Firestore prueba crear meta y llave en una transacción, lectura por el dueño, rechazo de lectura ajena y rechazo de actualización. Antes de activar la función, hay que desplegar las reglas en el proyecto real.

## Riesgos y decisiones pendientes

La autenticación de Google identifica la cuenta y permite recuperar la llave almacenada en Firestore. Cualquier cuenta de servicio o administrador con acceso de lectura al proyecto puede leer esa llave. Las bóvedas heredadas que aún no se hayan migrado siguen sujetas al mecanismo de desbloqueo anterior y no se recuperan solo con Google.

Compartir queda fuera de la primera versión. Requeriría un mecanismo de cifrado de extremo a extremo y distribución de claves por destinatario, así como aceptación y autorización verificables; no se implementará sin poder validar el flujo completo.

La persistencia offline puede dejar datos cifrados localmente y cambios pendientes. Se eligió permitirla solo en dispositivos personales de confianza. Además de los documentos cifrados de Firestore, el navegador conserva la clave no exportable en IndexedDB; el código del mismo origen puede utilizarla, por lo que un XSS o compromiso del sitio puede exponer la bóveda durante una sesión autenticada. El bloqueo tras 5 minutos cierra también la sesión de Google; volver a iniciar sesión permite reutilizar la clave local. «Olvidar este dispositivo» elimina esa clave. Se probó una cola offline en Brave mientras otro cliente sincronizaba un cambio: al reconectar, Brave confirmó su escritura y esta prevaleció.

Las llaves locales o registros biométricos heredados pueden permanecer en perfiles antiguos hasta migrar o borrar sus datos. En instalaciones nuevas, el inicio de sesión con Google recupera la llave desde Firestore.

El propietario limita el uso offline a dispositivos personales de confianza. Firestore puede conservar localmente documentos cifrados incluso después de bloquear o cerrar sesión; el bloqueo borra la clave y los datos descifrados de memoria, pero la clave no exportable recordada permanece hasta olvidarla o borrar los datos del navegador. No equivale a protección frente a código malicioso del mismo origen ni frente a alguien que controle una sesión Google autenticada en ese perfil. Ante pérdida o uso compartido de un dispositivo, se deben revocar sesiones de Google y borrar los datos del navegador; no se puede borrar remotamente esa caché ni la clave local desde este producto.

El propietario eligió last-write-wins para ediciones concurrentes. Firestore no compara la antigüedad semántica de los cambios: la última escritura confirmada gana, por lo que una edición offline antigua puede sobrescribir datos más recientes cuando se reconecte. La prueba con dos clientes independientes confirmó este comportamiento: la edición offline sincronizada al final sobrescribió el valor online anterior. El usuario debe considerar este riesgo al usar la bóveda en varios dispositivos.

La migración de una bóveda heredada requiere conexión para guardar la llave recuperable. La operación crea solo el documento de recuperación que falta y no sobrescribe una llave ya existente; ante una discrepancia se muestra un error en lugar de reemplazarla.
