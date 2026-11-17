# PaSSword para Android

Esta carpeta contiene la aplicación Android Flutter nativa. Usa Firebase
Authentication y Firestore directamente, cifra cada acceso en el dispositivo
antes de sincronizarlo y no depende de la web ni de Firebase Hosting.

## Estado

- La interfaz nativa, el inicio con Google, el desbloqueo con huella/PIN del
  teléfono o con un PIN propio de PaSSword, el cifrado compatible con la web y
  las operaciones de credenciales están implementados.
- La contraseña maestra queda como recuperación manual. El PIN propio tiene
  cuatro cifras y protege localmente la llave de la bóveda; no la sustituye.
- Al crear la bóveda o configurar por primera vez este dispositivo, se activa
  al menos una opción local de desbloqueo.
- El identificador de acceso acepta un email o nombre de usuario; solo exige
  que el campo no esté vacío.
- La app Firebase Android de depuración `password.app.dev` ya está registrada;
  las huellas SHA-1/SHA-256 del certificado debug local están asociadas.
- La app Firebase Android Flutter `password.app.flutter` está registrada como
  `1:899324045825:android:ebd3680a4801d2b32fae00`; su certificado de release
  está configurado en Firebase.
- OAuth de Google utiliza el cliente Web existente
  `899324045825-s28q0rrt4nlfjoptja33boggf0a1etfb.apps.googleusercontent.com`.
- La APK de producción está firmada; el propietario confirma que abre y
  sincroniza. Firebase Hosting no forma parte del cliente.
- El propietario valida en Android el inicio de sesión, desbloqueo, creación,
  edición y borrado de accesos, el bloqueo por inactividad, la sincronización
  cifrada y el desbloqueo biométrico disponible en el dispositivo.
- La comprobación de contraseñas usa Pwned Passwords cada siete días mientras
  la bóveda está abierta; los cambios se comprueban al sincronizarse. Solo se
  envía el prefijo de cinco caracteres del hash SHA-1, nunca la contraseña ni
  el hash completo. El resultado se conserva solo en el almacenamiento seguro
  local del dispositivo.
- Desde el detalle de un acceso con email se puede abrir Have I Been Pwned
  manualmente. PaSSword no envía el correo: la persona lo escribe en la página.
- Esta consulta cubre los datos conocidos por HIBP y no equivale a rastrear
  todas las filtraciones o la dark web.
- Tras estos cambios, falta validar en un teléfono la pantalla de desbloqueo,
  el PIN propio de PaSSword y la recuperación con la contraseña maestra.

## Configuración Firebase y Google

La configuración se pasa al compilar mediante `--dart-define`; no hace falta
añadir `google-services.json` ni credenciales al repositorio.

Los registros Android `password.app.dev` y `password.app.flutter` están
configurados en Firebase. El ID de cliente OAuth Web asociado se pasa como
`serverClientId`; no uses el ID del cliente OAuth de escritorio que usa
PaSSword para Windows. El ID es público. No leas ni compartas el archivo
secreto de OAuth.

Si se usan valores incorrectos o incompletos, la app mostrará un error de
configuración/inicio y no podrá autenticar o sincronizar. No inventes IDs para
superar ese problema. Los builds de producción usan el ID Firebase
`1:899324045825:android:ebd3680a4801d2b32fae00` y el mismo ID OAuth Web.

## Compilar la APK nativa de producción

La nueva app usa el identificador `password.app.flutter`, así puede
instalarse junto a cualquier versión anterior sin reemplazarla. Ejecuta el
script desde la raíz del proyecto:

```powershell
.\mobile\build-production.ps1
```

El script crea una clave independiente en
`%USERPROFILE%\.bubblewrap\password-app-flutter.jks`. Conserva sin cambios
la clave anterior `password-app-native.jks`. Keytool solicita la contraseña
nueva al crear la clave y al exportar el certificado. Al firmar, el script la
solicita dos veces de forma oculta. Usa la misma contraseña para ambas y
guárdala en un gestor seguro. El script registra las huellas en Firebase,
compila y verifica la firma APK con Android `apksigner`, además del
identificador de paquete. La APK final se guarda como
`mobile\PaSSword-app.apk`.
Guarda una copia segura del keystore y de su contraseña: no se pueden
recuperar ni reemplazar para publicar actualizaciones. No compartas la
contraseña ni el archivo de clave. Se usa una unidad temporal para evitar
fallos de Flutter con rutas de Windows que contienen espacios.

## Actualizaciones desde GitHub

Al subir cambios a `main` de `ShiryuXIX/PaSSword`, GitHub Actions compila y
publica una APK firmada junto con el instalador de Windows. La app consulta la
Release al abrirse, pregunta antes de descargar y abre el instalador de Android
solo tras aceptar. Android puede pedir permiso para instalar aplicaciones
desde PaSSword y siempre muestra su propia confirmación final.

Las versiones Android deben aumentar en `mobile/pubspec.yaml` antes de cada
cambio móvil: incrementa el código después de `+` (por ejemplo, `1.1.1+3`).
La versión y el código se comparan por separado; no publiques un código ya
usado. La primera APK con el comprobador debe instalarse manualmente en las
instalaciones existentes, porque la APK anterior no puede mostrar avisos.

En **Settings > Secrets and variables > Actions** del repositorio, configura
estos secretos sin añadirlos al proyecto:

- `BOVEDA_ANDROID_KEYSTORE_BASE64`: contenido Base64 del mismo keystore de
  producción. Se puede obtener localmente con
  `[Convert]::ToBase64String([IO.File]::ReadAllBytes("RUTA_DEL_KEYSTORE"))`.
- `BOVEDA_ANDROID_KEYSTORE_PASSWORD`: contraseña del keystore.
- `BOVEDA_ANDROID_KEY_ALIAS`: alias de firma `passwordappflutter`.
- `BOVEDA_ANDROID_KEY_PASSWORD`: contraseña de la clave.

La Release falla explícitamente si faltan secretos o si la firma/identificador
de paquete no son válidos. El workflow borra el keystore temporal al terminar.

## Validación de la app instalada

El propietario confirma que `password.app.flutter` abre y sincroniza
correctamente, y valida en el teléfono el inicio Google, desbloqueo,
creación/edición/borrado, bloqueo tras cinco minutos, sincronización cifrada y
desbloqueo biométrico disponible. La APK no actualiza la antigua TWA
`password.app`, que usaba una firma distinta y ya no tiene una web activa
detrás. Firebase Hosting no se usa.
