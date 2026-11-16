# Instrucciones del proyecto

- Escribe toda la interfaz y documentación dirigida al usuario en español.
- Mantén este producto en esta carpeta; no cambies archivos funcionales de otros productos ni reutilices su identidad o configuración de producción.
- La PWA web permanece estática y no tiene backend propio. El cliente de escritorio se empaqueta localmente y no debe abrir la web pública; Android está migrando de TWA a Flutter nativo, y la TWA se conserva hasta validar la sustituta.
- Para el escritorio, empaqueta también la interfaz y el SDK Firebase; no cargues JavaScript de la aplicación desde Hosting ni CDN en tiempo de ejecución. La autenticación Google debe abrir el navegador del sistema con PKCE.
- Trata sitios, emails y contraseñas como datos altamente sensibles. Firestore y su persistencia offline solo pueden recibir datos cifrados autenticados.
- No inventes algoritmos criptográficos, no uses `Math.random` para seguridad, y nunca guardes claves o secretos descifrados en Firestore, `localStorage`, logs, URLs o cachés del service worker.
- No implementes compartir hasta tener un diseño validado de autorización, aceptación del destinatario e intercambio de claves cifrado. Nunca sustituyas ese diseño por enlaces portadores o documentos en claro.
- No añadas configuración, reglas permisivas, credenciales, dominios, identificadores Android ni material de firma ficticios. No despliegues ni publiques sin autorización expresa.
- No leas `maestra.md` nunca. No leas ni uses el archivo OAuth `client_secret_2_*.json` sin permiso explícito del propietario; si hace falta, pídele permiso antes. No copies secretos a documentación, código, logs ni comandos.
- Mantén las contraseñas ocultas por defecto, informa claramente del estado de sincronización y muestra errores en lugar de ocultarlos.
- Sigue `spec/` como fuente de requisitos y respeta las decisiones más recientes del propietario sobre clientes de escritorio y Android nativo. Si una decisión afecta al cifrado, autenticación, seguridad o alcance de compartir datos y no está resuelta, detente y pregunta antes de implementarla.
- Antes de cerrar cambios, ejecuta las comprobaciones disponibles que correspondan a los archivos modificados e informa de lo que no pueda verificarse sin acceso del propietario.
