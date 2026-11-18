# Aplicación de escritorio PaSSword para Windows

La app de escritorio sirve los recursos incluidos en el instalador desde un
servidor local ligado a `localhost:43183`. Mantiene ese origen fijo para que
Firebase Authentication, Firestore offline y la llave recordada en IndexedDB
se conserven entre aperturas. Si el puerto está ocupado, la app informa el
problema y no cambia a un origen temporal. No abre la web pública de PaSSword.
El código de la interfaz y el SDK de Firebase se empaquetan localmente. Los
accesos se cifran en el cliente antes de sincronizarse. La llave de recuperación
se guarda también en Firestore para permitir el inicio automático con Google;
Firebase y las personas con acceso administrativo al proyecto pueden recuperar
esa llave y descifrar los accesos.

## Desarrollo

1. En [Google Cloud Console](https://console.cloud.google.com/), selecciona el
   mismo proyecto que Firebase: `gestor-pass-b60d6`.
2. En **Google Auth Platform**, completa la pantalla de consentimiento si aún
   no está configurada. Para una cuenta Google personal, elige audiencia
   **Externa**; mientras la aplicación esté en pruebas, añade tu cuenta en
   **Audiencia > Usuarios de prueba**.
3. En **Clientes**, crea un cliente OAuth y elige el tipo **Aplicación de
   escritorio**. Copia el **ID de cliente** que termina en
   `.apps.googleusercontent.com`. No uses un cliente de tipo Web. La app usa
   PKCE y no necesita ni debe guardar el secreto de cliente.
4. Guarda ese ID como variable de entorno de usuario de Windows. Sustituye el
   texto entre comillas por el ID copiado:

   ```powershell
   [Environment]::SetEnvironmentVariable(
     "BOVEDA_GOOGLE_CLIENT_ID",
     "ID_DE_CLIENTE.apps.googleusercontent.com",
     "User"
   )
   ```

   El secreto del cliente de escritorio es opcional según Google. Si Google
   indica que hace falta, se puede configurar localmente, sin compartirlo ni
   guardarlo en el proyecto:

   ```powershell
   [Environment]::SetEnvironmentVariable(
     "BOVEDA_GOOGLE_CLIENT_SECRET",
     "SECRETO_DEL_CLIENTE_DE_ESCRITORIO",
     "User"
   )
   ```

   No lo pegues en chats, capturas, documentación ni archivos del repositorio.
   Las aplicaciones de escritorio son clientes públicos; el secreto no debe
   considerarse confidencial ni sustituye PKCE.

5. Cierra PaSSword y vuelve a iniciar la sesión de Windows para que la app
   abierta desde Inicio herede la variable. Después, abre PaSSword de nuevo.

El ID OAuth identifica la aplicación; no es una contraseña. No se guarda en el
repositorio ni se envía al renderer como configuración persistente. El flujo
primero intenta reutilizar silenciosamente la sesión y el consentimiento de
Google ya concedidos. Si Google requiere interacción, abre el navegador
predeterminado para confirmar el acceso. Usa PKCE y recibe el retorno en un
puerto aleatorio de loopback (`http://127.0.0.1:puerto`, sin barra final); el
callback no muestra una página de PaSSword. No hay que añadir ese retorno a los
dominios autorizados de Firebase: el origen de la app es `localhost`, que sí
debe estar autorizado en Firebase Authentication. Firebase valida después el
token de identidad y conserva la sesión localmente.

Para desarrollo, desde PowerShell se puede establecer solo para esa sesión y
arrancar la app desde la carpeta del proyecto:

```powershell
$env:BOVEDA_GOOGLE_CLIENT_ID = "ID_DE_CLIENTE.apps.googleusercontent.com"
npm run desktop:dev
```

## Crear un instalador

En Windows, con las dependencias instaladas, ejecuta:

```powershell
npm run desktop:build
```

El instalador NSIS se genera en `dist/desktop/`. La distribución inicial es
manual; GitHub Actions publicará instaladores en Releases al subir versiones
nuevas a `main`. Google Play no interviene en la app de escritorio.
El instalador no tiene firma de código porque no se configuró un certificado;
Windows puede mostrar una advertencia de seguridad al instalarlo.

## Actualizaciones desde GitHub

Al subir cambios a `main` del repositorio `ShiryuXIX/PaSSword`, GitHub Actions
crea una Release con el instalador y los archivos de actualización de Windows.
La app empaquetada comprueba esa Release al abrirse: primero pregunta si quieres
descargarla y, cuando termina, pregunta si quieres reiniciar para instalarla.
Las compilaciones de desarrollo no comprueban Releases. El workflow valida que
el instalador indicado en `latest.yml` tenga el mismo nombre que el archivo
subido a la Release para evitar enlaces de actualización rotos.

El estado de sincronización y la versión se muestran, respectivamente, junto a
la cuenta y al final del menú de opciones. En el formulario de alta/edición, la
contraseña se puede ver, generar y copiar.

Para publicar una actualización de escritorio, aumenta `version` en
`package.json` siguiendo la secuencia indicada abajo y sube los cambios a
`main`. No se crea una Release si esa versión ya se publicó. La primera
instalación que incluya el comprobador debe instalarse manualmente; las
instalaciones anteriores no pueden mostrar el aviso.

La versión visible de PaSSword usa `major.minor`: `0.1`, `0.2` … `0.10`,
después `1.0`, `1.1` … `1.10`, y luego `2.0`. El paquete conserva el formato
SemVer con un tercer componente interno `.0`; al preparar una versión nueva,
actualiza `version` en `package.json` y `package-lock.json` siguiendo esa
secuencia (por ejemplo, `0.2.0` para mostrar `0.2`).

## Límites de esta primera fase

- La app de escritorio comparte el cliente Firestore y el esquema cifrado con
  Flutter. Google recupera la llave, pero cada PC exige un PIN local de 4 a 6
  cifras antes de mostrar los accesos. Esto permite también al administrador
  del proyecto recuperar la llave y los accesos.
- Las bóvedas creadas antes de esta versión requieren la clave antigua una vez
  para guardar su llave de recuperación. Las llaves locales de Windows no son
  exportables y no bastan para migrar; si se perdió la clave antigua, la bóveda
  no se puede recuperar en un equipo nuevo.
- Antes de crear o migrar bóvedas, despliega las reglas actualizadas de
  Firestore desde la raíz del proyecto con `firebase deploy --only firestore:rules`.
  Si no están desplegadas, Firestore rechazará la operación.
- En una bóveda antigua que aún no se migró, introduce su clave antigua una
  vez para activar la recuperación con Google y configurar el PIN de este PC.
- «Recuperar PaSSword con Google» cierra la sesión y elimina el PIN y las llaves
  locales de este PC; al volver a iniciar sesión se puede configurar un PIN
  nuevo.
- La app no se bloquea automáticamente por inactividad; usa «Cerrar sesión»
  cuando quieras terminar la sesión.
- El SDK queda incluido en el instalador; la app solo se conecta a
  Google/Firebase para autenticación y sincronización.
- Con la bóveda abierta, PaSSword comprueba las contraseñas cada siete días y
  al detectar cambios. Usa Pwned Passwords con k-anonimato: solo envía por
  HTTPS los cinco primeros caracteres del hash SHA-1, nunca la contraseña ni
  el hash completo. Los resultados se guardan localmente y no se sincronizan.
- La lista muestra «Tus accesos» y alinea el aviso de Huella digital con el
  campo de búsqueda. El detalle separa los campos y permite consultar el email
  manualmente en Have I Been Pwned.
- El detalle de un acceso con email permite abrir Have I Been Pwned tras una
  confirmación. PaSSword no envía ni precompleta el correo; se escribe en la
  página externa. La cobertura depende de los datos conocidos por HIBP y no
  representa todas las filtraciones ni toda la dark web.
- El puerto local `43183` debe estar libre. No lo cambies sin migrar antes los
  datos locales, ya que el origen aloja la sesión de Firebase y las llaves de
  IndexedDB.
- El menú de cuenta permite cambiar el PIN cuando ya está configurado, cerrar
  sesión y recuperar PaSSword con Google.
- La interfaz muestra códigos de error de OAuth/Firebase conocidos y guarda la
  fecha, la etapa del flujo, el código, el tipo genérico y, cuando existe, un
  detalle técnico limitado a códigos HTTP o de red en
  `sign-in-diagnostics.log` dentro de los datos locales de PaSSword. El registro
  incluye la versión de la app y puede incluir códigos HTTP, códigos de error
  de red, códigos técnicos sanitizados o la clasificación de un fallo de
  comunicación interna. No contiene emails, mensajes originales, URLs, códigos
  de autorización, tokens ni secretos; se abre desde «Abrir registro del error»
  después de un fallo.
- Los errores OAuth se transportan como datos serializables entre el preload y
  la interfaz. Electron elimina propiedades personalizadas (`code`,
  `diagnosticDetail`) de los objetos `Error` al cruzar `contextBridge`.
- En el cliente de Windows, la versión del pie se genera desde la versión del
  paquete instalado.
- Para un error `invalid_request` del intercambio de código, el diagnóstico
  conserva el estado HTTP y solo una categoría allowlist del parámetro o tipo
  de solicitud mencionado por Google; nunca guarda la descripción original.
- `BOVEDA_GOOGLE_CLIENT_SECRET` es opcional y solo se envía al intercambio si
  se configuró explícitamente en Windows.
