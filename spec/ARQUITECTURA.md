# Arquitectura prevista

## Límites

- `desktop/ui/`: interfaz HTML/CSS/JavaScript local empaquetada por Electron.
- `desktop/`: app Windows Electron con interfaz y SDK Firebase empaquetados localmente, servidor en loopback con origen estable y OAuth externo con PKCE. Firestore conserva solo documentos cifrados.
- Firebase: Authentication con Google y Firestore. La aplicación cifra los datos sensibles en el cliente antes de persistirlos.
- `mobile/`: aplicación Android Flutter nativa, independiente de Hosting.
- `docs/`: procedimientos manuales para el propietario y requisitos de publicación.

## Modelo de datos cifrados

- La meta `users/{uid}/vault/meta` contiene una sal aleatoria de 16 bytes, versión/KDF, 600 000 iteraciones de PBKDF2-SHA-256 y un verificador cifrado para admitir bóvedas vacías. No contiene la contraseña maestra ni la clave.
- Cada `users/{uid}/credentials/{id}` guarda solo `version`, `keyGeneration`, `iv` y `ciphertext`; los documentos anteriores pueden carecer de `keyGeneration` y se leen como generación 1. El texto cifrado autenticado incluye únicamente sitio web, email y contraseña; el AAD vincula el cifrado al UID, al ID del documento y, desde la versión actual, a la generación de clave.
- La clave AES-GCM de 256 bits, no exportable, se deriva con PBKDF2 al crear/desbloquear la bóveda. En cada dispositivo configurado se conserva la `CryptoKey` en IndexedDB, bajo el UID de Firebase; Google Authentication debe restaurar esa misma cuenta antes de reutilizarla. La contraseña maestra nunca se persiste. Bloquear o cerrar sesión elimina la referencia activa en memoria, no la clave recordada.
- Como alternativa local, el usuario puede configurar WebAuthn PRF con verificación obligatoria del dispositivo. La salida PRF deriva una llave AES-GCM que cifra los bytes de la llave de la bóveda; IndexedDB guarda la credencial, la sal y el ciphertext autenticado. El desbloqueo requiere una acción explícita después de Google Sign-In. La contraseña maestra sigue siendo recuperación y al rotarla se elimina la configuración PRF local, que puede configurarse otra vez después.
- PRF y el autenticador de plataforma no están disponibles en todos los navegadores/dispositivos. El autenticador puede pedir huella, rostro o el bloqueo de pantalla; no se debe prometer huella exclusivamente. La compatibilidad y la TWA Android deben validarse en el dispositivo objetivo antes de publicar esta opción.
- El acceso offline se limita a dispositivos personales de confianza. Firestore conserva documentos cifrados en su caché; el dispositivo recuerda la clave no exportable para el siguiente inicio con Google. Un dispositivo nuevo requiere introducir la contraseña maestra una vez. «Olvidar este dispositivo» elimina la clave de IndexedDB. El acceso a IndexedDB desde código del mismo origen implica que una vulnerabilidad XSS o código malicioso ejecutado en el origen podría utilizar la clave aunque no pueda exportarla.
- Las reglas solo permiten al usuario autenticado acceder a su propio UID y validan la forma y tamaño de documentos cifrados. La función de compartir no forma parte de este esquema.

## Estado de implementación

La interfaz local, el cifrado y la integración con Authentication/Firestore están implementados; las primitivas criptográficas y las reglas tienen pruebas automatizadas. Firebase Hosting no forma parte del producto.

El cliente Windows empaqueta la interfaz de `desktop/ui/` y el SDK, y no carga código remoto. Sirve desde `http://localhost:43183` para conservar estable el origen de la sesión de Firebase y las llaves guardadas en IndexedDB. Google OAuth usa navegador externo, PKCE y un callback loopback. Android usa Flutter nativo.

El almacenamiento offline de Firestore usa escrituras por documento y sincronización del SDK. El propietario eligió last-write-wins: gana la escritura que Firestore confirme al final. Una edición antigua que vuelva online más tarde puede sobrescribir una más reciente; no se detectan ni se muestran conflictos. Este caso se verificó con Brave offline y un cliente independiente online: la edición offline se confirmó al reconectar y prevaleció sobre la escritura online anterior.

El cambio de contraseña requiere conexión y cero escrituras pendientes. Un bloqueo temporal en metadata impide crear, modificar o borrar accesos mientras se prepara la rotación. La aplicación recifra todos los documentos y actualiza metadata en una transacción atómica; cada acceso recibe una ID nueva y la antigua se elimina en el mismo commit. El máximo es 249 accesos (499 escrituras por transacción). Las reglas tratan documentos heredados sin generación como generación 1 y rechazan escrituras de generaciones anteriores; las IDs nuevas aíslan las eliminaciones offline antiguas.
