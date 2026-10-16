# LibroMundo — Unidad 3, MySQL 8.0+

Archivos reconstruidos a partir del DDL PostgreSQL que el equipo entrego para la Unidad 2. **No ejecutar el DDL PostgreSQL en MySQL.**

## Orden
1. `01_ddl/LibroMundo_DataMart_DDL_MySQL8.sql`: ejecutar en MySQL Workbench sobre una base nueva. Crea `dm_libromundo` y todas las tablas, constraints, indices y cliente no identificado. No incluye datos simulados.
2. Cargar datos Q1/Q2 2026 **validos** (>= 1000 filas de fact_ventas, >= 3 regiones, >= 5 productos con actividad Q2 en cada region). Sin datos, los reportes estaran vacios.
3. `05_validacion_y_explain/validaciones.sql`: ejecutar pruebas y guardar resultados reales.
4. `04_consultas_sql/consulta_final.sql`: Top 5 para Q2 vs Q1.
5. `05_validacion_y_explain/error_1055.sql`: ejecutar por separado SELECT defectuoso (captura del Error 1055) y SELECT corregido (captura).
6. `05_validacion_y_explain/optimizacion_explain.sql`: ejecutar EXPLAIN original, guardar captura, agregar el indice propuesto, volver a ejecutar EXPLAIN, comparar. El indice no tiene mejora garantizada.
7. `06_stored_procedure/procedimiento_reporte.sql`: crear procedimiento y CALL de prueba.

## Decisiones y limites
- **Grano**: `fact_ventas` = item dentro de transaccion. El DDL restringe `(venta_id, item_key)` a unico.
- **Region**: `dim_sucursal.region`, sucursal de origen de la venta.
- **Rentabilidad monetaria**: `SUM(fact_ventas.margen)` menos `SUM(fact_devoluciones.importe_devuelto)` en fecha de la devolucion. **Provisional**: no equivale a beneficio economico neto cuando la devolucion recupera inventario, pues falta registrar el costo recuperado.
- **Descuentos**: incluidos en `margen` generado de `venta_neta`.
- **Cancelaciones**: modelo no contiene columna de estado; no hay forma de excluirlas mediante una condicion real.
- **Devoluciones**: se agregan por separado, para evitar duplicar margen por JOIN 1:N. Solo entran si `(venta_id,item_key)` identifica una venta original.
- **No se usa bridge de autores/generos/promociones/eventos** en la consulta central: serian uniones con cardinalidad potencialmente multiplica-filas.
- **Q1**: 2026-01-01 inclusive a 2026-04-01 exclusive; **Q2**: 2026-04-01 inclusive a 2026-07-01 exclusive.
- **Porcentaje variacion**: `(Q2-Q1) / ABS(Q1) * 100`; se retorna NULL cuando base monetaria Q1 es cero; indicador diferencia entre sin datos y base cero con registros.
- **Top 5**: `ROW_NUMBER() OVER(PARTITION BY region ORDER BY rentabilidad_q2 DESC, item_id, item_key)`; requiere actividad Q2 (`registros_q2 > 0`). Incluye perdidas si estan entre los cinco primeros.

## Diferencias de motor
PostgreSQL `GENERATED ALWAYS AS IDENTITY` -> MySQL `AUTO_INCREMENT`; `CREATE SCHEMA + SET search_path` -> `CREATE DATABASE + USE`; `ON CONFLICT` -> `ON DUPLICATE KEY UPDATE`; `COMMENT ON TABLE` quitado; `FILTER(WHERE)` -> `SUM(CASE WHEN ...)`; casteo `::numeric` -> `CAST(... AS DECIMAL)`; `ORDER BY NULLS LAST` -> `ORDER BY`; `RAISE EXCEPTION` -> `SIGNAL`; procedimiento PostgreSQL con cursor -> `CALL` que hace `SELECT`.

En MySQL, la demostracion de agrupacion estricta usa **ERROR 1055**, bajo `ONLY_FULL_GROUP_BY`.

**Estado:** scripts adaptados e inspeccionados estaticamente; no hay servidor MySQL ni datos cargados disponibles en este entorno, asi que no se presentan ejecuciones, capturas, ni mejoras observadas como hechos. El esquema necesita >= MySQL 8.0.16 para que CHECK se aplique.
