# Política de seguridad

## Reporte de vulnerabilidades

No abras un issue público para reportar una vulnerabilidad sospechada. Repórtala de forma privada al propietario del repositorio e incluye descripción, revisión afectada, pasos de reproducción e impacto potencial. No incluyas credenciales reales ni datos de transacciones.

La persona responsable del repositorio debe confirmar la recepción, evaluar la severidad y coordinar una corrección antes de cualquier divulgación pública. Siempre que sea viable, las correcciones de seguridad deben incluir una prueba de regresión y publicarse mediante el flujo habitual de Pull Request revisado.

## Alcance admitido

Este repositorio es una implementación MVP para un challenge. Las credenciales predeterminadas de la base de datos local y la API sin autenticación no están preparadas para producción. Consulta `docs/security.md`, `docs/threat-model.md` y `docs/limitations-roadmap-ai.md` para conocer los controles implementados, los controles previstos y las brechas conocidas.

## Expectativas de desarrollo seguro

- Nunca hagas commit de secretos, archivos `.env`, private keys ni datos reales de transacciones.
- Usa los checks de CI incluidos como gates de revisión; investiga los hallazgos en lugar de suprimirlos silenciosamente.
- Mantén revisadas y correctamente fijadas las dependencias y referencias de GitHub Actions.
- Considera image signing, políticas de IaC y políticas de Kubernetes como controles que requieren verificación en el entorno desplegado; no son un sustituto de ella.
