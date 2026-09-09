# Política de seguridad
## Informar de una vulnerabilidad
No abra una edición pública por una vulnerabilidad sospechosa. Denúncialo
de forma privada al propietario del repositorio con una descripción, revisión afectada,
Pasos de reproducción y posible impacto. Evite incluir credenciales reales o
datos de la transacción.
El mantenedor debe reconocer el informe, evaluar la gravedad y coordinar una
arreglar antes de la divulgación pública. Las correcciones de seguridad deberían recibir una prueba de regresión
cuando sea práctico y se publicará a través del flujo normal de solicitud de extracción revisada.
## Alcance admitido
Este repositorio es una implementación de MVP/desafío. Su base de datos local predeterminada
Las credenciales y la API no autenticada no están listas para producción. Ver
`docs/security.md`, `docs/threat-model.md` y
`docs/limitations-roadmap-ai.md` para controles implementados, controles previstos
y lagunas conocidas.
## Expectativas de desarrollo seguras
- Nunca confirmes secretos, archivos `.env`, claves privadas o datos de transacciones reales.
- Utilice los controles de CI suministrados como puertas de revisión; investigar los hallazgos en lugar de
  reprimiéndolos silenciosamente.
- Mantener las dependencias y referencias de acciones revisadas y fijadas según corresponda.
- Trate las políticas de firma de imágenes, IaC y Kubernetes como controles que requieren
  verificación del entorno implementado, no como un sustituto de la misma.
