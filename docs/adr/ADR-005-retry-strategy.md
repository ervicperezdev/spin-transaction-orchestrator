# ADR-005: Estrategia de reintento y disyuntor Resilience4j
**Estado:** Propuesto
**Fecha:** 2026-09-08
**Autor:** Líder de ingeniería y seguridad
---
## Contexto
El orquestador de transacciones llama a un proveedor de pagos externo a través de HTTPS. El proveedor puede no estar disponible temporalmente (errores transitorios de red, mantenimiento breve) o rechazar permanentemente una solicitud (entrada no válida, error de autenticación). La lógica de reintento ingenua corre el riesgo de dos modos de falla críticos:
1. **Operaciones financieras duplicadas:** reintentar una solicitud caducada cuando es posible que el proveedor ya la haya ejecutado.
2. **Saturación del proveedor:** reintentar agresivamente durante una interrupción del proveedor amplifica la carga y empeora la recuperación.
La estrategia de reintento debe distinguir entre clases de error en las que el reintento es seguro, ambiguo o prohibido.
---
## Decisión
Adopte la siguiente política de reintento y disyuntor cuando Resilience4j (o un
equivalente). No está implementado en la aplicación actual.
Hoy en día, el adaptador HTTP solo aplica los tiempos de espera de conexión/lectura configurados y
asigna fallas del proveedor a `PaymentProviderUnavailableException`.
### Configuración
**Tiempos de espera:**
- Tiempo de espera de conexión: 2 segundos
- Tiempo de espera de lectura: 3 segundos
Justificación: las API de pago deben responder en milisegundos a segundos de un solo dígito. Las esperas más largas retienen un hilo y una conexión de base de datos se abre innecesariamente.
**Disyuntor:**
- Umbral de tasa de fracaso: 50% (en una ventana móvil de 10 llamadas)
- Duración de la espera en estado ABIERTO: 10 segundos antes de pasar a HALF_OPEN
- Llamadas permitidas semiabiertas: 3 (sondear llamadas antes de decidir CERRAR o permanecer ABIERTO)
**Política de reintento: clasificación de error explícito:**
| Error Type | Retry? | Rationale |
|---|---|---|
| Connection refused / network unreachable | Yes (up to 2 retries) | Provider was not reached; no financial operation occurred |
| HTTP 503 Service Unavailable | Yes (up to 2 retries) | Provider explicitly signals transient unavailability |
| Read timeout | **NO** | Provider may have processed the request; retrying risks double-charge |
| HTTP 4XX (400, 409, 422) | **NO** | Functional rejection; the provider evaluated the request and refused it; retry will not change the outcome |
| HTTP 5XX (other than 503) | **NO** | Ambiguous server-side error; retry without reconciliation is unsafe |

Reintento de retroceso: exponencial con fluctuación, base 500 ms.
---
## Consecuencias
**Positivo:**
- El disyuntor evita fallas en cascada: una vez que se determina que el proveedor no está en buen estado, llama a fast-fail inmediatamente en lugar de agotar el grupo de subprocesos.
- El no-reintento explícito en el tiempo de espera obliga a abordar el diseño de reconciliación en lugar de ocultarlo detrás de reintentos optimistas.
- No reintentar en 4XX reduce la carga innecesaria y evita enmascarar errores en la construcción de solicitudes.
**Brechas negativas/conocidas:**
- El no reintento explícito en el tiempo de espera significa que las llamadas agotadas aparecen como errores para la persona que llama. Los clientes deben manejarlos como estados potencialmente ambiguos y utilizar `Idempotency-Key` al reintentar.
- Esta estrategia no resuelve el problema del Estado ambiguo: lo hace visible. Se requiere un **trabajo de conciliación** (hoja de ruta) para detectar y resolver transacciones ejecutadas por el proveedor pero no persistentes.
---
## Alternativas consideradas
| Alternative | Reason Rejected |
|---|---|
| **Retry on all errors including timeout** | Unacceptable double-charge risk; hides the reconciliation gap |
| **No retry at all** | Causes unnecessary failures on clearly transient errors (connection refused, 503) where no financial operation occurred |
| **Spring Retry** | Less expressive circuit breaker and rate limiter support compared to Resilience4j; weaker observability integration |
