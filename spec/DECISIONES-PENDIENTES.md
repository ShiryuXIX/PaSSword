# Decisiones pendientes

No tomar decisiones silenciosas en estos temas. Si afectan a seguridad o al alcance de compartir, consultar al propietario antes de implementar.

| Tema | Pregunta que debe resolverse | Estado |
|---|---|---|
| Desbloqueo de bóveda | Google identifica la cuenta pero no cifra por sí solo. | Elegido y autorizado: llave AES aleatoria guardada en Firestore para recuperación automática al iniciar sesión con Google. El administrador del proyecto Firebase también puede leerla y descifrar la bóveda. Las bóvedas heredadas se migran una vez con su llave anterior. |
| Bloqueo por inactividad | Bloquear tras 5 minutos; reiniciar el intervalo con actividad del usuario. | Elegido por el propietario |
| Acceso offline | ¿Qué política se aplica a un dispositivo compartido o perdido y cómo se protege el acceso a la clave mientras está desbloqueada? | Elegido: solo dispositivos personales de confianza. Firestore conserva credenciales cifradas y la llave recuperable; el SDK puede mantener datos en caché local. La llave activa en memoria se borra al bloquear/cerrar sesión. |
| Conflictos offline | ¿Cómo resolver ediciones concurrentes de una credencial? | Elegido: last-write-wins; gana la escritura que Firestore confirme al final. Puede sobrescribir cambios más recientes si un dispositivo sincroniza tarde. |
| Compartir | ¿Se incluye en la primera versión? ¿Qué diseño de identidad/intercambio de claves y aceptación se aprobará? No implementar si no puede validarse de extremo a extremo. | Excluido de la primera versión; no implementar hasta aprobar un diseño seguro y verificable. |
| Identidad del producto | Confirmar nombre/marca. | Elegido: PaSSword; se mantiene el icono, los colores y la identidad visual ya implementados. |
| Firebase | Proyecto nuevo dedicado, con Google Authentication y Firestore Standard. | Proyecto `gestor-pass-b60d6`, cliente Firebase requerido por el SDK de escritorio y apps Android registradas; Authentication habilitada. Las reglas existentes deben actualizarse antes de activar la recuperación Google. |
| Clientes instalados | ¿Cómo evitar que los clientes dependan del código servido públicamente? | Elegido y validado: app de escritorio empaquetada y app Android Flutter nativa; Firestore sincroniza credenciales cifradas y almacena la llave de recuperación aprobada por el propietario. |
| OAuth de escritorio | ¿Cómo autenticar Google sin popup embebido? | Elegido: navegador del sistema con OAuth de aplicación instalada, PKCE y callback loopback; falta crear/configurar el ID OAuth del proyecto propietario. |
| Proyecto de referencia | `gestor.md` menciona CompraLista, pero no está presente en el workspace actual. | No disponible en este workspace; se continúa con la arquitectura ya documentada de PaSSword. |
