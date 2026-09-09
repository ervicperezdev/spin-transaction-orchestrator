# Limitaciones, hoja de ruta y uso de IA
## Limitaciones actuales
- La API no tiene autenticación ni autorización. Es adecuado sólo para un
  entorno local/demo controlado hasta que se implemente un límite de identidad.
- El proveedor de pago configurado es una dependencia externa; el repositorio
  suministra su contrato HTTP pero no un simulador de proveedor local.
- La idempotencia es opcional. Una clave duplicada devuelve una transacción almacenada, pero una
  llamada al proveedor que tiene éxito antes de que la aplicación persista, el resultado permanece
  un estado ambiguo y aún puede conducir a una operación externa duplicada.
- Las llamadas de proveedores utilizan tiempos de espera de conexión/lectura configurados. Sin retry, circuito
  interruptor, trabajador de conciliación, seguimiento de auditoría, exportación de métricas o alertas.
  implementado en la aplicación.
- Las credenciales de PostgreSQL Docker Compose son predeterminadas solo para desarrollo.
  No deben reutilizarse fuera del desarrollo local.
## Hoja de ruta priorizada
1. Agregue autenticación OAuth2/JWT, política de autorización y un modelo de eventos de auditoría.
2. Conservar un registro de operación/bandeja de salida antes de la interacción con el proveedor y crear un
   proceso de conciliación para resultados ambiguos del proveedor.
3. Agregue propagación de idempotencia específica del proveedor, clasificación de retry seguro,
   corte de circuito y métricas/alertas operativas.
4. Proveer y verificar los controles AWS/EKS/RDS representados por el IaC y
   Artefactos de Helm, incluidos TLS, aplicación de NetworkPolicy, IRSA y secretos
   rotación.
5. Agregue pruebas por contrato con un simulador de proveedor y preparación para la producción.
   pruebas (copia de seguridad/restauración, carga, ejercicios de fallas e incidentes).
## Uso de la IA
La asistencia de IA se utilizó para acelerar la redacción y revisión de la documentación y
cambios de código. No es una autoridad de seguridad, corrección financiera o
preparación para la producción. Pruebas de repositorio, revisión humana, escaneo de dependencias y
La validación específica del entorno sigue siendo necesaria antes del lanzamiento. Sin credenciales,
Los datos de los clientes o los datos de las transacciones de producción deben suministrarse a las herramientas de IA.
