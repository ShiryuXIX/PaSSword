# PaSSword

> **Restricción de seguridad:** El archivo [../maestra.md](../maestra.md) contiene información sensible y no debe abrirse ni leerse nunca bajo ninguna circunstancia. Está fuera del alcance de la documentación y del desarrollo del proyecto, y no debe reutilizarse ni citarse en ningún proceso de implementación.

Gestor de contraseñas para Windows y Android. Windows usa Electron y Android usa Flutter nativo. La carpeta es independiente de cualquier otro producto.

> **Estado:** la aplicación de escritorio y la APK Flutter están operativas. La APK abre y sincroniza con Firebase. El sitio Hosting predeterminado no se puede borrar en Firebase; se sustituyó su contenido por una respuesta 404.

> **Prioridad actual:** mantener los clientes de escritorio y Android nativo; no desplegar una interfaz web.

> **Recuperación actual:** las bóvedas nuevas guardan su llave AES en Firestore para abrirse automáticamente al iniciar sesión con Google. El administrador del proyecto Firebase también puede leer esa llave y descifrar los accesos. Las bóvedas antiguas requieren su clave actual una vez para activar esta recuperación. Antes de usar o publicar el cambio, hay que desplegar las reglas actualizadas de `desktop/ui/firestore.rules`.

## Estructura

- `AGENTS.md`: instrucciones para trabajar en este proyecto.
- `spec/`: requisitos, arquitectura, seguridad y decisiones pendientes.
- `docs/`: guía de Firebase y pasos para compilar la APK Flutter.
- `package.json`: herramientas para compilar la aplicación de escritorio.
- `desktop/`: cliente Windows e interfaz local empaquetada con Electron; consultar [desktop/README.md](./desktop/README.md).
- `mobile/`: aplicación Android nativa Flutter; consultar [mobile/README.md](./mobile/README.md).

La interfaz de `desktop/ui/` solo se empaqueta en la aplicación de escritorio. Flutter nativo no depende de ella ni de Firebase Hosting; Firebase se usa para autenticación y Firestore.

## Lista de trabajo

### 1. Aclarar requisitos y preparar el entorno

- [x] Leer [spec/REQUISITOS.md](./spec/REQUISITOS.md), [spec/ARQUITECTURA.md](./spec/ARQUITECTURA.md) y [spec/SEGURIDAD.md](./spec/SEGURIDAD.md).
- [x] Revisar y resolver las preguntas aplicables de [spec/DECISIONES-PENDIENTES.md](./spec/DECISIONES-PENDIENTES.md).
- [x] Confirmar el nombre del producto: PaSSword, manteniendo el icono, los colores y la identidad visual ya implementados.
- [x] Revisar la disponibilidad del proyecto de referencia: CompraLista no está incluido en este espacio de trabajo; se continúa con la arquitectura documentada de esta aplicación.
- [x] Método actual: Google identifica a la persona y Firestore recupera la llave AES; las bóvedas heredadas necesitan la clave maestra una vez para migrarse.
- [x] Decidir si compartir entra en la primera versión: queda excluido; no se implementará hasta aprobar y validar un diseño seguro.
- [x] Acordar la política offline: Firestore conserva credenciales cifradas y una llave de recuperación por cuenta; el propietario/administrador del proyecto puede leer esa llave. Los perfiles antiguos también pueden conservar llaves locales.

**Punto de control:** las decisiones necesarias para la primera versión están resueltas. Compartir sigue fuera del alcance hasta que exista un diseño seguro y verificable.

### 2. Crear y configurar Firebase

Seguir también [docs/CONFIGURAR-FIREBASE.md](./docs/CONFIGURAR-FIREBASE.md).

- [x] Crear el proyecto Firebase nuevo, dedicado a este producto e independiente de cualquier otro, con los datos reales del propietario (`gestor-pass-b60d6`).
- [x] Elegir la región de Firestore: Bélgica (`europe-west1`) en el proyecto del propietario.
- [x] Verificar en Firebase Console que Firebase Authentication y el proveedor Google estén habilitados.
- [x] Registrar la configuración cliente de Firebase que usa el SDK de escritorio, sin activar Analytics.
- [x] Verificar/configurar los dominios autorizados de Authentication: `localhost`, `127.0.0.1`, `gestor-pass-b60d6.firebaseapp.com` y `gestor-pass-b60d6.web.app`.
- [x] Crear Firestore Standard en modo de producción; las reglas revisadas ahora limitan acceso a propietarios autenticados.
- [x] Definir un esquema mínimo en código para guardar exclusivamente documentos cifrados.
- [x] Diseñar el modelo de identidad y permisos por usuario/recurso; las reglas locales limitan el acceso al UID autenticado.
- [x] Escribir reglas Firestore con denegación por defecto y permisos mínimos; desplegar la versión actualizada antes de activar la recuperación.
- [x] Añadir la configuración de índices necesaria (sin índices compuestos adicionales).
- [x] Validar las reglas localmente para propietario, UID ajeno, sesión anónima, esquema y operaciones CRUD.
- [x] Registrar Firebase Hosting para servir los recursos estáticos usados por la TWA.
- [x] Mantener la configuración pública de Firebase en `desktop/ui/firebase-config.js`.
- [x] Confirmar que nadie confunde la configuración/API key pública de Firebase con una clave de cifrado.

**Punto de control:** proyecto, Hosting, Firestore, reglas, Google Authentication y dominios autorizados están configurados. Se validaron en el sitio desplegado el acceso, la bóveda, el ciclo de escritura/lectura/edición offline/reconexión/borrado con datos sintéticos y el conflicto last-write-wins entre clientes independientes: la edición offline que se sincronizó al final prevaleció. El registro sintético fue eliminado.

### 3. Diseñar y programar la bóveda

- [x] Definir el formato versionado de los documentos cifrados y el ciclo de vida de claves, sales y nonces con criptografía estándar del navegador.
- [x] Definir cómo se deriva o desbloquea la clave y cómo se bloquea la bóveda; el propietario autorizó recuperar la llave mediante Google y Firebase.
- [x] Integrar y validar autenticación Google con el SDK, el proyecto Firebase y el Hosting publicado, incluido el inicio y cierre de sesión real.
- [x] Crear la interfaz cliente basada en HTML/CSS/JavaScript, compartida durante la transición con la TWA.
- [x] Crear la pantalla principal inicial con lista en memoria y acciones para añadir, seleccionar, editar, eliminar y buscar.
- [x] Definir exactamente tres campos editables por credencial: sitio web, email y contraseña.
- [x] Ocultar contraseñas por defecto y ofrecer revelación explícita y temporal.
- [x] Añadir copia de email y contraseña al portapapeles con confirmación visible y errores explícitos.
- [x] Implementar el generador de contraseñas de 12 caracteres con mayúscula, minúscula, número y símbolo; usar `crypto.getRandomValues`, selección sin sesgo y mezcla segura, nunca `Math.random`.
- [x] Comprobar que una contraseña generada sigue siendo editable manualmente.
- [x] Cifrar en cliente los campos sensibles antes de escribirlos en Firestore; Firestore almacena además la llave de recuperación, accesible a administradores del proyecto.
- [x] Implementar el cifrado autenticado de accesos; la rotación de clave maestra ya no está disponible en los clientes actuales para no invalidar la llave de recuperación de Google.
- [x] No persistir datos descifrados. En bóvedas nuevas, la llave AES se guarda en el documento de recuperación de Firestore; las bóvedas heredadas requieren la clave maestra una vez para migrar.
- [x] Configurar persistencia offline del SDK; se comprobó que los datos cifrados pueden leerse y editarse tras recargar offline y desbloquear la bóveda.
- [x] Implementar bloqueo por inactividad de 5 minutos y cierre de sesión, además del desbloqueo.
- [x] Comprobar los estados visibles de sincronizado y pendiente durante el uso conectado y offline.
- [x] Definir el comportamiento ante ediciones concurrentes: last-write-wins, por decisión del propietario; una escritura antigua puede sobrescribir una más reciente si sincroniza después.
- [x] Implementar el service worker para la carcasa estática y actualizar/inutilizar caché al cambiar activos; no cachear secretos ni datos descifrados.
- [x] Crear el manifiesto inicial, el icono SVG y los metadatos de instalación PWA.
- [x] Omitir compartir: está excluido de la primera versión y no hay un diseño de intercambio de claves aprobado.
- [x] Revisar que secretos no aparezcan en URLs, logs, mensajes de error, telemetría, notificaciones ni cachés. El cliente no añade datos de credenciales a URLs ni los registra; no hay telemetría ni notificaciones. La caché del service worker solo contiene la carcasa estática y recursos del SDK, y guarda las navegaciones bajo una clave fija sin parámetros de URL. Firestore persiste únicamente documentos cifrados mediante el SDK. La corrección local está en `boveda-shell-v7`; aún no se ha desplegado.

### 4. Probar antes de publicar

- [x] Comprobar que la interfaz se adapta a móvil y escritorio sin desbordamiento horizontal.
- [x] Revisar la navegación completa con teclado, etiquetas, foco y mensajes accesibles.
- [x] Corregir la semántica accesible del avatar informativo y del estado de selección de accesos.
- [x] Probar inicio/cierre de sesión, bloqueo, desbloqueo y errores de red.
- [x] Probar el flujo base de crear, listar, seleccionar, editar y eliminar credenciales temporales.
- [x] Probar validaciones de campos vacíos o inválidos según las reglas definidas.
- [x] Probar 50 contraseñas generadas: longitud exacta, categorías requeridas, edición manual y aleatoriedad criptográfica.
- [x] Probar la copia al portapapeles disponible y verificar la confirmación visible.
- [x] Probar el error de copia cuando el portapapeles no está disponible.
- [x] Inspeccionar el documento de prueba en Firestore y confirmar que los campos sensibles no están en claro; sin acceder directamente al almacenamiento local del navegador.
- [x] Probar reglas Firestore en Firebase Emulator con acceso autorizado, ajeno y no autenticado, tanto para lectura como para escritura.
- [x] Probar que la carcasa PWA vuelve a abrirse offline mediante el service worker.
- [x] Probar la consulta y edición offline de datos cifrados previamente desbloqueados, la recarga offline y la sincronización al reconectar con un cliente.
- [x] Comprobar en dos pestañas la propagación en tiempo real y que la última edición secuencial guardada prevalece.
- [x] Probar el conflicto real `last-write-wins` con Brave offline y otro cliente online: la escritura offline encolada, al sincronizar al final, prevaleció sobre la escritura online anterior.
- [x] Verificar que cerrar sesión o bloquear elimina claves activas y datos descifrados de memoria; la clave local recordada permanece hasta olvidarla o borrar los datos del navegador. El service worker no guarda secretos.
- [x] Verificar la sintaxis de los archivos JavaScript y el formato JSON del manifiesto.
- [x] Comprobar la sintaxis de `app.js`, `firebase-client.js`, `vault-crypto.js` y `sw.js` tras implementar la rotación.
- [x] Probar en el sitio real el cambio de contraseña, el desbloqueo con la nueva y la denegación de escrituras en cola de una generación anterior.

**Punto de control:** la validación funcional se completó localmente sin introducir credenciales reales y el propietario confirmó que la aplicación publicada funciona correctamente también en su móvil.

La fase 4 queda cerrada con la confirmación del propietario en el entorno real.

### 5. Publicar la PWA

- [x] Confirmar que el proyecto y el entorno de Firebase son los correctos antes de cualquier comando de despliegue.
- [x] Revisar configuración, reglas e índices antes de publicar las reglas.
- [x] Obtener autorización expresa del propietario para desplegar (mediante permisos del entorno de Firebase y la ejecución del proyecto real).
- [x] Publicar y verificar las reglas revisadas en el proyecto Firebase real del propietario (solo reglas; los índices existentes no se modificaron).
- [x] Publicar la PWA estática en Firebase Hosting.
- [x] Desplegar `boveda-shell-v6` y las reglas de rotación a Hosting/Firestore; confirmar HTTP 200 y presencia de los cambios servidos.
- [x] Desplegar `boveda-shell-v7` solo a Firebase Hosting, sin modificar reglas ni datos de Firestore.
- [x] Verificar que la web, el manifiesto y `sw.js` responden con HTTP 200, y que un navegador activa el service worker y la caché `boveda-shell-v7`.
- [x] Añadir localmente iconos PNG cuadrados de 192/512 píxeles y capturas de instalación `wide`/`narrow` al manifiesto.
- [x] Publicar `boveda-shell-v8` solo a Firebase Hosting y verificar HTTP 200 para manifiesto, service worker, iconos y capturas.
- [x] Publicar `boveda-shell-v9` solo a Firebase Hosting con autorización expresa; verificar el service worker y el módulo de almacenamiento de llaves.
- [x] Publicar `boveda-shell-v10` solo a Firebase Hosting con autorización expresa; verificar el service worker y el manifiesto oscuro.
- [x] Publicar `boveda-shell-v15` solo a Firebase Hosting; verificar HTTP 200 para web, CSS, aplicación y service worker, sin modificar Firestore ni sus reglas.
- [x] Verificar que el Hosting usado por la TWA responde por HTTPS en `https://gestor-pass-b60d6.web.app`.
- [x] Comprobar en Firebase Authentication que Google está habilitado y que `gestor-pass-b60d6.web.app` y `gestor-pass-b60d6.firebaseapp.com` figuran como dominios autorizados.
- [x] Probar Google Sign-In y desbloquear la bóveda con la contraseña maestra en `https://gestor-pass-b60d6.web.app`.
- [x] Probar el funcionamiento offline de la PWA en el dominio publicado.
- [x] Probar la instalación de la PWA en Opera GX para Windows (confirmado por el propietario).
- [x] Dar por válida la actualización de una instalación/caché existente de v9 a v10 (confirmado por el propietario).
- [x] Confirmar que no hace falta configurar un dominio personalizado ni pagar un hosting adicional para el uso personal previsto.

**Punto de control:** no se requiere dominio propio ni hosting de pago. HTTPS, el proveedor Google, ambos dominios autorizados, Google Sign-In, el desbloqueo con contraseña maestra y el funcionamiento offline se comprobaron en producción. v15 está publicada en Hosting; el propietario confirma que la PWA se instala correctamente y da por válida la actualización desde v9 a v10. El propietario confirma que la aplicación actual funciona correctamente en Android.

**Privacidad:** Firebase Hosting sirve públicamente la carcasa de la aplicación; no se debe considerar secreta ni privada la URL. No compartirla reduce su difusión, pero no controla el acceso. La protección de los datos depende de Google Sign-In y de las reglas de Firestore; no guardes datos reales hasta validar el flujo completo y mantener protegido el dispositivo.

### 6. Preparar Android TWA/APK (opcional)

Seguir también [docs/GENERAR-APK.md](./docs/GENERAR-APK.md).

- [x] Confirmar dominio HTTPS (`gestor-pass-b60d6.web.app`), nombre (`PaSSword`), `packageId` (`password.app`), iconos y distribución privada.
- [x] Generar configuración Bubblewrap y proyecto Android con tema oscuro y notificaciones deshabilitadas.
- [x] Compilar localmente una APK sin firma con Android mínimo API 24 (compatible con el móvil Android 13 indicado).
- [x] Documentar el proceso de firma local y generación de APK privada.
- [x] Ejecutar `apk/build-private.ps1`; APK y AAB firmados generados localmente y keystore guardado fuera del repositorio.
- [x] Obtener y verificar la huella SHA-256 real; generar `desktop/ui/.well-known/assetlinks.json` y vincularlo a la configuración TWA.
- [x] Desplegar `assetlinks.json` solo a Firebase Hosting y comprobar HTTP 200 y huella correcta.
- [x] Probar la TWA instalada en Android 13 (confirmado por el propietario; funciona correctamente).

**Punto de control:** la APK y el AAB firmados están generados localmente, el enlace de confianza se sirve desde Hosting con la huella correcta y el propietario confirma que la aplicación funciona correctamente en el móvil. La APK es privada y no se publicará en Google Play.

### 7. Desbloqueo del dispositivo

- [x] Derivar material criptográfico reutilizable sin cambiar la llave ni el formato de cifrado de las bóvedas existentes.
- [x] Añadir alta WebAuthn con PRF, verificación de usuario obligatoria y llave AES-GCM de envoltura; no se guardan datos biométricos ni se envía la huella al servidor.
- [x] Guardar solo la credencial y la llave de bóveda envuelta en IndexedDB; mantener el desbloqueo con contraseña maestra como recuperación.
- [x] Mantener el desbloqueo de dispositivo al usar la contraseña maestra como recuperación; pedir una nueva configuración tras cambiar la contraseña maestra.
- [x] Actualizar y validar localmente la carcasa offline, derivación, almacenamiento, cifrado y solicitud de verificación.
- [x] Probar alta, cierre de sesión, desbloqueo y recuperación con contraseña en el Android del propietario (confirmado por el propietario).
- [x] Publicar v15 en Hosting y validar WebAuthn PRF en Android (confirmado por el propietario).

**Punto de control:** implementación y validación local y móvil completadas. WebAuthn no garantiza que el autenticador use específicamente la huella: puede requerir rostro, PIN u otro método configurado en el dispositivo.

### 8. Ajuste de interfaz móvil

- [x] Reducir los encabezados repetidos y dejar el título de accesos junto a la acción principal en pantallas pequeñas.
- [x] Agrupar las acciones de cuenta en un menú desplegable móvil, manteniéndolas visibles en escritorio.
- [x] Quitar el aviso redundante del flujo móvil, donde el estado de cifrado ya está visible en la cabecera.
- [x] Actualizar la carcasa offline y la versión local a v12.
- [x] Publicar el diseño responsive en Hosting y validar su funcionamiento en Android (confirmado por el propietario).

**Punto de control:** el cambio es responsive y se aplica a la PWA en móviles y a la TWA, no solo a la APK. No altera el diseño de escritorio. Está publicado en Hosting y el propietario confirma que funciona correctamente en su teléfono.

### 9. Simplificar la pantalla de accesos

- [x] Sustituir el titular promocional y los textos repetidos por un único título: «Accesos».
- [x] Retirar el aviso redundante, el contador y las llamadas a la acción duplicadas.
- [x] Mostrar un estado vacío breve y ocultar el panel de detalle mientras no haya accesos.
- [x] Actualizar la versión local y la caché a v15.
- [x] Mover la versión al pie izquierdo y los estados de sincronización/cifrado al pie derecho.
- [x] Publicar en Hosting y comprobar las respuestas HTTP de la web y sus recursos.
- [x] Revisar el pie y la distribución del buscador en escritorio y móvil.

**Punto de control:** la pantalla de trabajo conserva solo el título, la acción principal, la búsqueda y la lista. v15 está publicada; se mantienen el estado de sincronización y la versión.

### 10. Ajuste de pantalla en Android

- [x] Limitar la bóveda abierta al alto visible del móvil, respetando las áreas seguras.
- [x] Dejar la lista como única zona desplazable cuando hay muchas cuentas.
- [x] Mostrar el detalle de una cuenta en la misma zona de trabajo y añadir navegación de vuelta a la lista.
- [x] Mantener el comportamiento de desplazamiento de la pantalla de inicio de sesión para que no se recorte con el teclado.
- [x] Actualizar la versión local y la caché a v17.
- [x] Validar en el dispositivo Android del propietario (confirmado por el propietario).

**Punto de control:** el cambio responsive está implementado y publicado en los recursos que usa la TWA; el propietario confirma que funciona correctamente en el móvil.

### 11. Retoques de interfaz móvil

- [x] Añadir un icono de huella a «Configurar desbloqueo del dispositivo».
- [x] Cerrar el menú «Cuenta» al tocar fuera de él.
- [x] Hacer que la marca PaSSword de la cabecera no ejecute ninguna acción.
- [x] Evitar el resaltado azul al tocar y la selección accidental de textos que abre la búsqueda de Google; los campos editables siguen permitiendo seleccionar texto.
- [x] Quitar la línea duplicada sobre las acciones del detalle de una cuenta.
- [x] Hacer más visible «Volver a los accesos» y añadir una flecha hacia la izquierda.
- [x] Actualizar la versión de la interfaz y la caché offline a v19.

**Punto de control:** retoques publicados como v19 en Firebase Hosting. La publicación modificó únicamente Hosting; Firestore y sus reglas no se tocaron.

### 12. Crear cliente de escritorio local

- [x] Definir como primer objetivo un cliente Windows instalado, conservando el esquema cifrado y la sincronización de Firestore.
- [x] Crear el shell Electron con aislamiento de contexto, sin Node.js en el renderer, servidor local solo en loopback y política CSP.
- [x] Empaquetar la interfaz y el SDK de Firebase en el cliente para no depender de Hosting ni descargar código de la aplicación al ejecutarla.
- [x] Añadir inicio Google mediante navegador del sistema y PKCE, con retorno OAuth en puerto aleatorio y origen local fijo para conservar sesión y claves entre aperturas.
- [x] Configurar en Windows la variable de usuario `BOVEDA_GOOGLE_CLIENT_ID` con el cliente OAuth de escritorio del propietario.
- [x] Resolver el rechazo del intercambio OAuth configurando localmente el secreto del cliente de escritorio; el propietario confirma que el inicio de sesión Google funciona en Windows con PaSSword 0.1.11. El secreto no se incluye en el repositorio ni en el instalador.
- [x] Validar el inicio Google y la sincronización con datos sintéticos en Windows; el propietario confirma que funciona.
- [x] Crear, instalar y probar localmente el instalador Windows privado 0.1.0.
- [x] Revalidar el inicio Google en Windows con diagnóstico explícito de OAuth/Firebase.
- [x] Probar desbloqueo, creación y persistencia de un acceso ficticio en Windows; el propietario confirma que se sincroniza cifrado con Firestore.
- [x] Retomar la migración Android de TWA a app nativa tras validar Windows.

### 13. Usar Android nativo con Flutter

- [x] Revisar la implementación Flutter y validar compatibilidad criptográfica con los documentos web actuales y heredados.
- [x] Analizar estáticamente la app móvil Flutter antes de la compilación final.
- [x] Registrar la app Firebase Android y configurar su certificado de firma y OAuth.
- [x] Compilar la APK Flutter firmada; el propietario confirma que abre y sincroniza correctamente.
- [x] Retirar la TWA, sus recursos PWA y Firebase Hosting. La APK Flutter usa un identificador de paquete propio.
- [x] Validar en el teléfono inicio, desbloqueo, gestión de accesos, bloqueo por inactividad, sincronización cifrada y desbloqueo biométrico disponible.

**Punto de control:** el cliente Windows y la aplicación Android están validados funcionalmente por el propietario. La clave de firma se conserva fuera del repositorio.

### 14. Huella digital

- [x] Revisar las contraseñas guardadas cada siete días mientras la bóveda está abierta y volver a revisar al editar un acceso.
- [x] Consultar Pwned Passwords con k-anonimato; enviar solo el prefijo de cinco caracteres del hash SHA-1.
- [x] Guardar localmente los resultados para detectar nuevas exposiciones y evitar avisos repetidos.
- [x] Avisar en Android y Windows y señalar cada acceso con una contraseña expuesta.
- [x] Permitir la consulta manual del email desde el detalle de un acceso; PaSSword no envía ni precompleta el correo.
- [x] Documentar límites de cobertura y privacidad; verificar con pruebas móviles, de escritorio y builds de ambas plataformas.

**Punto de control:** el escaneo cubre los datos de contraseñas conocidos por Have I Been Pwned; no equivale a rastrear toda la dark web. La consulta del email se hace manualmente en la página del proveedor. La publicación autorizada incluye la APK Flutter vigente y el instalador Windows; la antigua TWA no forma parte del producto.

**Publicación:** [v0.2.2-android-4](https://github.com/ShiryuXIX/PaSSword/releases/tag/v0.2.2-android-4), con la APK Android `1.1.2+4` y la aplicación Windows `0.2.2`.

## Estado final del proyecto

- El proyecto real `gestor-pass-b60d6` está configurado y operativo en Firebase.
- Firebase Authentication y Firestore permanecen activos para los clientes nativos.
- Firebase Hosting, la PWA y la TWA ya no forman parte del producto.
- La APK Android vigente es la aplicación Flutter nativa `password.app.flutter`; el propietario confirma el funcionamiento de inicio, gestión, bloqueo y sincronización.
- La huella digital revisa las contraseñas con k-anonimato y ofrece consulta manual de emails, sin enviar emails automáticamente.
- No se incluye ninguna credencial, keystore ni contraseña de firma en el repositorio ni en la documentación pública.

## Prioridad de trabajo

Windows y Android nativo están validados por el propietario. No desplegar ni reconstruir una versión web/PWA/TWA.

## Seguridad y datos del propietario

- El `packageId` Android de Flutter es `password.app.flutter`; la clave de firma se conserva fuera del repositorio.
- No almacenar contraseñas descifradas en Firestore, `localStorage`, URLs, logs, notificaciones o caché. La llave AES recuperable sí se almacena en Firestore; el propietario aprobó este cambio de seguridad para permitir el inicio automático con Google.
- No incluir archivos de credenciales, keystores ni contraseñas de firma en el repositorio.
- No compartir secretos mediante documentos en claro ni enlaces portadores.
- La revocación no puede retirar copias que un destinatario ya haya descifrado o guardado.
