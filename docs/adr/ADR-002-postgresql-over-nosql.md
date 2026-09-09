# ADR-002: PostgreSQL sobre NoSQL para almacenamiento de transacciones
**Estado:** Aceptado
**Fecha:** 2026-09-08
**Autor:** Líder de ingeniería y seguridad
---
## Contexto
Las transacciones financieras son la entidad de dominio principal de este servicio. La capa de almacenamiento debe garantizar propiedades de corrección que no son negociables en un contexto fintech: escrituras atómicas (una transacción persiste por completo o no persiste en absoluto), almacenamiento duradero, aritmética monetaria precisa y la capacidad de hacer cumplir restricciones de unicidad (clave de idempotencia). La elección del motor de base de datos afecta directamente la integridad de cada registro financiero.
---
## Decisión
Utilice **PostgreSQL** como almacén de datos principal. Amazon RDS es el sistema administrado
opción de implementación de producción; este repositorio no demuestra una implementación
Instancia RDS.
Opciones clave de implementación:
- Montos monetarios almacenados como `NUMERIC(19,2)`, nunca `FLOAT` o `DOUBLE`, que introducen errores de redondeo binarios de punto flotante inaceptables en los cálculos financieros.
- `BigDecimal` utilizado en todo el modelo de dominio Java; nunca `double` o `float`.
- La columna `idempotency_key` lleva una restricción `UNIQUE` aplicada en el nivel de la base de datos, lo que evita duplicados incluso en retrys simultáneos.
- RDS implementado en una subred privada con modo de espera Multi-AZ para alta disponibilidad.
- Flyway gestiona todas las migraciones de esquemas con scripts SQL controlados por versión revisados ​​en PR.
---
## Consecuencias
**Positivo:**
- Garantías ACID totales: las escrituras de transacciones simultáneas están a salvo de anomalías de escritura parcial.
- `NUMERIC(19,2)` elimina los errores de precisión de punto flotante, fundamentales para el cumplimiento normativo y la confianza del cliente.
- Herramientas maduras: migraciones Flyway, JPA/Hibernate, instantáneas RDS, recuperación en un momento dado.
- La restricción ÚNICA en `idempotency_key` impone la deduplicación en la capa de almacenamiento como última línea de defensa.
**Negativo:**
- Límites de escala vertical en comparación con las tiendas NoSQL fragmentadas horizontalmente; mitigado por RDS Multi-AZ y réplicas de lectura.
- Las migraciones de esquemas requieren coordinación y revisión cuidadosa; Flyway impone el orden, pero no la corrección de la lógica SQL.
---
## Alternativas consideradas
| Alternative | Reason Rejected |
|---|---|
| **Amazon DynamoDB** | No multi-item ACID transactions in the general case (DynamoDB Transactions exist but add complexity); eventual consistency model requires additional application-level conflict resolution |
| **MongoDB** | Document schema flexibility is not needed here; ACID multi-document transactions added in v4.0 but less battle-tested than PostgreSQL for financial workloads; no native `NUMERIC` equivalent to prevent floating-point errors |
