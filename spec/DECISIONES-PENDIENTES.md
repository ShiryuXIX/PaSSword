# Decisiones pendientes

No tomar decisiones silenciosas en estos temas. Si afectan a seguridad o al alcance de compartir, consultar al propietario antes de implementar.

| Tema | Pregunta que debe resolverse | Estado |
|---|---|---|
| Desbloqueo de bóveda | Google identifica la cuenta pero no cifra por sí solo. | Elegido: contraseña maestra al crear la bóveda y una vez por cada navegador/dispositivo; la clave AES-GCM no exportable se recuerda localmente en IndexedDB y Google autoriza su reutilización en ese dispositivo. Un dispositivo nuevo necesita la maestra. |
| Bloqueo por inactividad | Bloquear tras 5 minutos; reiniciar el intervalo con actividad del usuario. | Elegido por el propietario |
| Acceso offline | ¿Qué política se aplica a un dispositivo compartido o perdido y cómo se protege el acceso a la clave mientras está desbloqueada? | Elegido: solo dispositivos personales de confianza; Firestore conserva documentos cifrados y el navegador recuerda localmente la clave no exportable. La clave activa en memoria se borra al bloquear/cerrar sesión. La opción «Olvidar este dispositivo» elimina la clave local; si se pierde el dispositivo, también se deben borrar los datos del navegador. |
| Conflictos offline | ¿Cómo resolver ediciones concurrentes de una credencial? | Elegido: last-write-wins; gana la escritura que Firestore confirme al final. Puede sobrescribir cambios más recientes si un dispositivo sincroniza tarde. |
| Compartir | ¿Se incluye en la primera versión? ¿Qué diseño de identidad/intercambio de claves y aceptación se aprobará? No implementar si no puede validarse de extremo a extremo. | Excluido de la primera versión; no implementar hasta aprobar un diseño seguro y verificable. |
| Identidad del producto | Confirmar nombre/marca. | Elegido: PaSSword; se mantiene el icono, los colores y la identidad visual ya implementados. |
| Firebase | Proyecto nuevo dedicado, con Google Authentication y Firestore Standard. | Proyecto `gestor-pass-b60d6`, cliente Firebase requerido por el SDK de escritorio y apps Android registradas; Authentication habilitada y reglas e índices publicados. El contenido del sitio Hosting predeterminado se retiró con una respuesta 404 porque Firebase no permite borrar ese sitio. |
| Clientes instalados | ¿Cómo evitar que los clientes dependan del código servido públicamente? | Elegido y validado: app de escritorio empaquetada y app Android Flutter nativa; Firestore se conserva solo para sincronizar contenido cifrado. El propietario confirma que la APK abre y sincroniza. |
| OAuth de escritorio | ¿Cómo autenticar Google sin popup embebido? | Elegido: navegador del sistema con OAuth de aplicación instalada, PKCE y callback loopback; falta crear/configurar el ID OAuth del proyecto propietario. |
| Proyecto de referencia | `gestor.md` menciona CompraLista, pero no está presente en el workspace actual. | No disponible en este workspace; se continúa con la arquitectura ya documentada de PaSSword. |
