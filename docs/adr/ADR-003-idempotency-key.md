# ADR-003: Encabezado de clave de idempotencia para retrys seguros
**Estado:** Aceptado
**Fecha:** 2026-09-08
**Autor:** Líder de ingeniería y seguridad
---
## Contexto
Es posible que los clientes que se comunican a través de redes no confiables no reciban una respuesta incluso cuando el servidor haya procesado exitosamente la solicitud. Sin un mecanismo de deduplicación, un retry de un cliente después de un timeout de la red enviaría una transacción idéntica dos veces, lo que podría provocar un doble cargo. Este es un problema crítico de corrección en cualquier sistema de procesamiento de pagos.
---
## Decisión
Acepte un encabezado HTTP `Idempotency-Key` opcional al enviar la transacción.
Implementación:
- La clave persiste junto con el registro de transacción en PostgreSQL con una restricción `UNIQUE` en la columna `idempotency_key`.
- Al recibir una clave duplicada, el servicio devuelve el resultado de la transacción previamente almacenado sin volver a ejecutar la lógica empresarial ni llamar al proveedor externo.
- La clave la genera el cliente (se recomienda UUID) y debe ser única por operación lógica.
- Las claves se almacenan indefinidamente en la implementación actual; una política de vencimiento basada en TTL es una mejora futura.
---
## Consecuencias
**Positivo:**
- Evita el doble cobro en el retry del cliente: los retrys seguros son una garantía de primera clase.
- La restricción UNIQUE a nivel de base de datos proporciona un respaldo de deduplicación sólido y sin condiciones de carrera.
- Se alinea con los estándares de la industria (Stripe, Adyen y la mayoría de las API de pago implementan el mismo patrón).
**Brechas negativas/conocidas:**
- **No cubre el escenario de estado ambiguo:** si el proveedor de pago externo ejecutó exitosamente el cargo pero la aplicación falló antes de persistir la transacción y su clave de idempotencia, un retry posterior con la misma clave volverá a ejecutar la llamada al proveedor, lo que podría resultar en un cargo duplicado a nivel de proveedor. Esta brecha requiere un **trabajo de conciliación** (elemento de la hoja de ruta) que detecte ejecuciones de proveedores no reconocidas y resuelva su estado.
- La clave de idempotencia es opcional; los clientes que no proporcionan uno no tienen seguridad de retry.
- La caducidad de claves y el crecimiento del almacenamiento no se abordan en la implementación inicial.
> **Importante:** La clave de idempotencia es un mecanismo de seguridad de retry, no un sustituto de la conciliación. La brecha conocida anteriormente se documenta explícitamente aquí para impulsar el elemento de la hoja de ruta de conciliación.
---
## Alternativas consideradas
| Alternative | Reason Rejected |
|---|---|
| **Request fingerprinting (hash of body fields)** | Brittle — minor payload variations produce different hashes; clients lose control over deduplication scope |
| **Rely on provider's own idempotency** | Does not protect against duplicates introduced before the provider call; also provider-specific, reducing portability |
| **No deduplication (accept duplicate risk)** | Unacceptable for a financial transaction service |
