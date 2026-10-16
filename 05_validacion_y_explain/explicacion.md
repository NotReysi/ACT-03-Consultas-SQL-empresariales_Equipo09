### Optimización de consulta SQL mediante EXPLAIN

**Empresa:** LibroMundo  
**Motor:** MySQL 8  
**Consulta:** Top 5 de productos más rentables por región, comparando Q2 contra Q1 de 2026.

**Análisis inicial**

Se utilizó `EXPLAIN FORMAT=TRADITIONAL` para examinar cómo MySQL ejecutaba la consulta de rentabilidad. Se observaron accesos mediante índices, resultados derivados y operaciones adicionales de ordenamiento y agrupación.

**Mejora propuesta**

Se creó un índice compuesto sobre las columnas `fecha_key`, `sucursal_key` e `item_key` de la tabla `fact_ventas`, dado que participan en las relaciones utilizadas por el reporte.

**Validación posterior**

Después de crear el índice y actualizar las estadísticas con `ANALYZE TABLE`, se ejecutó nuevamente EXPLAIN.

Se observó que MySQL seleccionó el nuevo índice compuesto en el acceso a `fact_ventas`. No obstante, persistieron operaciones `Using temporary` y `Using filesort`, mientras que algunas estimaciones de filas aumentaron ligeramente.

**Conclusión técnica**

La prueba demostró que el índice propuesto modificó el plan de ejecución, pero no confirmó una reducción global del trabajo. Esto permitió comprender que las mejoras de optimización deben justificarse mediante evidencia del plan y, cuando sea posible, mediciones de ejecución, en lugar de asumir que agregar índices siempre mejora el rendimiento.