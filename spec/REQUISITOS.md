# Requisitos del producto

Estos requisitos se derivan de `gestor.md` en la raíz del workspace. Son el alcance objetivo, no una afirmación de que ya esté implementado.

## Producto y experiencia

- Una única pantalla principal para listar y gestionar varias credenciales; se permiten la pantalla de inicio de sesión y diálogos/hojas superpuestas para desbloquear, editar o compartir.
- Cada credencial contiene exactamente tres campos editables: sitio web, email y contraseña.
- Permitir crear, consultar, seleccionar, editar y eliminar credenciales.
- Permitir copiar email y contraseña con confirmación visible y errores explícitos si el portapapeles no está disponible.
- Generar contraseñas de exactamente 12 caracteres, con al menos una mayúscula, una minúscula, un número y un símbolo. Usar `crypto.getRandomValues`, selección sin sesgo y mezcla segura; no usar `Math.random`.
- La contraseña generada debe seguir siendo editable manualmente.
- Interfaz en español, adaptable a móvil y escritorio, accesible por teclado, con identidad propia y contraseñas ocultas por defecto. La revelación debe ser explícita y temporal.

## Cuenta y bóveda

- Inicio de sesión con Google mediante Firebase Authentication, compatible con navegadores restrictivos y sin reutilizar credenciales de otro proyecto.
- Cifrar en el cliente los sitios, emails y contraseñas antes de persistirlos. Usar criptografía estándar autenticada, nonces y claves aleatorios criptográficamente y derivación de claves con sal aleatoria.
- No usar Google Login, una API key de Firebase ni una URL compartida como clave de cifrado.
- No almacenar la contraseña maestra ni datos descifrados en Firestore, almacenamiento local, logs o mensajes de error. Tras introducirla por primera vez en un dispositivo, se puede conservar la clave AES-GCM no exportable en el almacenamiento local seguro, vinculada al UID; solo se reutiliza después de autenticar con Google. La clave activa en memoria se borra al cerrar sesión o bloquear la bóveda.
- Bloquear la bóveda y cerrar sesión tras 5 minutos de inactividad. En un dispositivo ya configurado, volver a iniciar sesión con Google permite reutilizar la clave local; cada navegador o dispositivo nuevo requiere la contraseña maestra una vez. Informar de los riesgos del almacenamiento local y permitir olvidar la clave de este navegador.
- Proteger operaciones de compartir, exportar, copiar y eliminar. No incluir secretos en URLs, telemetría ni notificaciones.
- Aplicar reglas Firestore de mínimo privilegio que validen identidad y permisos por operación. La interfaz no es una frontera de seguridad; no permitir acceso público.
- Compartir únicamente credenciales concretas entre usuarios autenticados y autorizados. El destinatario debe aceptar expresamente y recibir acceso mediante un flujo seguro de claves, nunca claves o secretos en claro. Documentar que no es posible revocar copias ya descifradas o guardadas.
- Si no se puede diseñar, implementar y validar compartir con cifrado seguro, no implementarlo con alternativas inseguras: presentar la limitación y solicitar decisión.

## Offline y sincronización

- Habilitar persistencia offline de Firestore siguiendo el SDK elegido; solo persistir documentos cifrados.
- Permitir consultar y editar offline credenciales ya desbloqueadas previamente en ese dispositivo.
- Al recuperar conexión, sincronizar cambios e informar escrituras pendientes o fallidas. Las ediciones concurrentes siguen la política elegida por el propietario: last-write-wins; una edición antigua que se sincronice después puede sobrescribir una más reciente.
- Distinguir los estados sincronizado, pendiente y error. El login de Google y el primer acceso/descifrado pueden requerir conexión.

## Firebase, publicación y aplicaciones instaladas

- Usar un proyecto Firebase nuevo e independiente con Authentication (Google) y Firestore.
- No reutilizar configuración, base de datos, dominio, reglas ni índices de otros proyectos. No inventar credenciales ni declarar el proyecto configurado/desplegado sin datos reales.
- Documentar el proyecto, proveedor Google, registro de clientes y reglas. Añadir los índices que requiera el modelo final.
- No desplegar ni publicar datos sin autorización expresa.
- El cliente de escritorio debe empaquetar localmente la interfaz y el SDK; no debe cargar código de aplicación desde Hosting ni CDN. Google OAuth debe abrir el navegador del sistema con PKCE y callback local.
- Android usa una app Flutter nativa; no depende de una web ni de Firebase Hosting. La TWA anterior está retirada.
- No reutilizar package ID ni keystore ajenos. Mantener la clave de firma fuera del repositorio y documentar los pasos de compilación.
- No incluir secretos, contraseñas de firma, keystores ni archivos de credenciales.

## Entrega y validación

- Mantener toda la implementación y documentación del producto en esta carpeta independiente.
- Revisar interfaz, autenticación, reglas, caché offline, límites del cliente de escritorio y Android nativo.
- Validar sintaxis JavaScript y las comprobaciones Android disponibles cuando existan fuentes/dependencias.
- Informar qué se implementó, qué pruebas pasaron, qué limitaciones de seguridad quedan y qué configuración requiere el propietario. No declarar seguros el cifrado o el compartir sin validar sus flujos completos.
