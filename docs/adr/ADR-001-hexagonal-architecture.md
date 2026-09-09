# ADR-001: Arquitectura Hexagonal (Puertos y Adaptadores)
**Estado:** Aceptado
**Fecha:** 2026-09-08
**Autor:** Líder de ingeniería y seguridad
---
## Contexto
El orquestador de transacciones debe seguir siendo mantenible y comprobable de forma independiente a medida que evolucionan los adaptadores de infraestructura. Las reglas comerciales, como la aplicación de idempotencia, la validación de cantidades y las transiciones de estado de transacciones, no deben combinarse con preocupaciones específicas del marco, como anotaciones JPA, tipos Spring HTTP o llamadas al SDK de AWS. Acoplar la lógica empresarial a la infraestructura hace que las reglas sensibles a la seguridad sean más difíciles de auditar, probar de forma aislada y evolucionar de forma segura.
---
## Decisión
Adoptar **Arquitectura hexagonal (puertos y adaptadores)** como patrón estructural para el servicio.
Estructura:
- `domain/` — modelo de dominio Java puro; sin dependencias del marco
- `application/`: servicios de casos de uso e interfaces de puerto; sin JPA, sin HTTP, sin AWS
- `adapter/in/` — adaptadores entrantes (REST controller, consumidores)
- `adapter/out/`: adaptadores salientes (persistencia JPA, cliente HTTP del proveedor)
- `infrastructure/` — Cableado Spring Boot, configuración, migraciones de Flyway
Los puertos son interfaces Java definidas en `application/port/`; los adaptadores los implementan. El núcleo de la aplicación nunca importa desde paquetes de infraestructura o adaptadores.
---
## Consecuencias
**Positivo:**
- Las capas de dominio y aplicación son independientes del marco y trivialmente comprobables por unidad sin un contexto Spring en ejecución.
- La lógica empresarial crítica para la seguridad (idempotencia, validación, máquina de estado) está aislada y auditable independientemente de los problemas de HTTP o de la base de datos.
- Los adaptadores se pueden intercambiar (por ejemplo, reemplazar el cliente proveedor HTTP con un consumidor de cola de mensajes) sin tocar las reglas comerciales.
**Negativo:**
- Gastos generales repetitivos menores: cada llamada entrante requiere un mapeo desde DTO → Comando → Modelo de dominio → Entidad y viceversa.
- Se debe aplicar una disciplina de paquete más estricta mediante pruebas de ArchUnit o revisión manual para evitar fugas de dependencia.
---
## Alternativas consideradas
| Alternative | Reason Rejected |
|---|---|
| **Layered (N-tier) architecture** | Business logic tends to leak into service or repository layers over time; harder to enforce isolation in a security-sensitive context |
| **CQRS (Command Query Responsibility Segregation)** | Adds read-model complexity not justified by the current single-service, single-database scope; can be adopted later if read scaling becomes a concern |
