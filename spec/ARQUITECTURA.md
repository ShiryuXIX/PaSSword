# Arquitectura prevista

## Límites

- `desktop/ui/`: interfaz HTML/CSS/JavaScript local empaquetada por Electron.
- `desktop/`: app Windows Electron con interfaz y SDK Firebase empaquetados localmente, servidor en loopback con origen estable y OAuth externo con PKCE.
- Firebase: Authentication con Google y Firestore. La aplicación cifra las credenciales en el cliente antes de persistirlas; Firestore almacena también la llave de recuperación que puede leer el administrador del proyecto.
- `mobile/`: aplicación Android Flutter nativa, independiente de Hosting.
- `docs/`: procedimientos manuales para el propietario y requisitos de publicación.

## Modelo de datos cifrados

- La meta `users/{uid}/vault/meta` contiene una sal aleatoria de 16 bytes y un verificador cifrado. En bóvedas nuevas, `kdf` es `RANDOM-AES-256` y `iterations` es 0; las bóvedas heredadas conservan `PBKDF2-SHA-256` con 600 000 iteraciones.
- `users/{uid}/vault/recovery` almacena `version: 1` y la llave AES de 32 bytes codificada en Base64. Se crea atómicamente con los metadatos para una bóveda nueva; en una bóveda heredada se crea solo después de verificar la llave existente.
- Cada `users/{uid}/credentials/{id}` guarda solo `version`, `keyGeneration`, `iv` y `ciphertext`; los documentos anteriores pueden carecer de `keyGeneration` y se leen como generación 1. El texto cifrado autenticado incluye únicamente sitio web, email y contraseña; el AAD vincula el cifrado al UID, al ID del documento y, desde la versión actual, a la generación de clave.
- Las bóvedas nuevas generan una llave AES-GCM aleatoria de 256 bits. Tras autenticar con Google, ambas apps la recuperan desde Firestore, la validan con el verificador y abren automáticamente. El proyecto Firebase y sus administradores pueden leer la llave.
- Las llaves heredadas siguen derivadas con PBKDF2. En Android se pueden migrar tras una verificación maestra o un desbloqueo local válido; en Windows la `CryptoKey` guardada no es exportable, por lo que la migración requiere la clave antigua.
- PRF y el autenticador de plataforma no están disponibles en todos los navegadores/dispositivos. El autenticador puede pedir huella, rostro o el bloqueo de pantalla; no se debe prometer huella exclusivamente. La compatibilidad y la TWA Android deben validarse en el dispositivo objetivo antes de publicar esta opción.
- El acceso offline se limita a dispositivos personales de confianza. Firestore puede conservar credenciales cifradas y la llave de recuperación en caché; cualquier código del mismo origen que comprometa el cliente podría usar la llave durante una sesión autenticada.
- Las reglas solo permiten al usuario autenticado acceder a su propio UID. La llave de recuperación se crea una sola vez; la regla niega actualizarla, borrarla y leerla desde otras cuentas. Las reglas nuevas deben desplegarse antes de usar la función.

## Estado de implementación

La interfaz local, el cifrado y la integración con Authentication/Firestore están implementados; las primitivas criptográficas y las reglas tienen pruebas automatizadas. Firebase Hosting no forma parte del producto.

El cliente Windows empaqueta la interfaz de `desktop/ui/` y el SDK, y no carga código remoto. Sirve desde `http://localhost:43183` para conservar estable el origen de la sesión de Firebase y las llaves guardadas en IndexedDB. Google OAuth usa navegador externo, PKCE y un callback loopback. Android usa Flutter nativo.

El almacenamiento offline de Firestore usa escrituras por documento y sincronización del SDK. El propietario eligió last-write-wins: gana la escritura que Firestore confirme al final. Una edición antigua que vuelva online más tarde puede sobrescribir una más reciente; no se detectan ni se muestran conflictos. Este caso se verificó con Brave offline y un cliente independiente online: la edición offline se confirmó al reconectar y prevaleció sobre la escritura online anterior.

La rotación de la llave ya no está disponible en las interfaces actuales; las reglas bloquean su commit para impedir que una llave nueva deje obsoleto el documento de recuperación.
