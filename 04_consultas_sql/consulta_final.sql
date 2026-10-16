/* LIBROMUNDO - MySQL 8.0+
   Rentabilidad operativa = SUM(margen de ventas) - SUM(importe_devuelto).
   IMPORTANTE: es una aproximacion; no se conoce el costo recuperado por devolucion.
   DDL no contiene estado de cancelacion: no se pueden excluir ventas canceladas.
   Devoluciones se atribuyen al periodo de devolucion y region de venta original.
   Evitamos bridge N:M. Grano de fact_ventas: un item por venta.
   Se requiere que venta_id + item_key identifique la venta original.
*/
USE dm_libromundo;

WITH ventas_periodo AS (
    SELECT s.region, i.item_key, i.item_id, i.nombre,
           CASE WHEN f.fecha < '2026-04-01' THEN 1 ELSE 2 END AS periodo,
           SUM(v.margen) AS monto, COUNT(*) AS registros
    FROM dm_libromundo.fact_ventas AS v
    INNER JOIN dm_libromundo.dim_fecha AS f ON f.fecha_key = v.fecha_key
    INNER JOIN dm_libromundo.dim_sucursal AS s ON s.sucursal_key = v.sucursal_key
    INNER JOIN dm_libromundo.dim_item AS i ON i.item_key = v.item_key
    WHERE (f.fecha >= '2026-01-01' AND f.fecha < '2026-04-01')
       OR (f.fecha >= '2026-04-01' AND f.fecha < '2026-07-01')
    GROUP BY s.region, i.item_key, i.item_id, i.nombre,
             CASE WHEN f.fecha < '2026-04-01' THEN 1 ELSE 2 END
),
devoluciones_periodo AS (
    SELECT s.region, i.item_key, i.item_id, i.nombre,
           CASE WHEN f.fecha < '2026-04-01' THEN 1 ELSE 2 END AS periodo,
           -SUM(dev.importe_devuelto) AS monto, COUNT(*) AS registros
    FROM dm_libromundo.fact_devoluciones AS dev
    INNER JOIN dm_libromundo.fact_ventas AS v
      ON v.venta_id = dev.venta_id AND v.item_key = dev.item_key
    INNER JOIN dm_libromundo.dim_fecha AS f ON f.fecha_key = v.fecha_key
    INNER JOIN dm_libromundo.dim_sucursal AS s ON s.sucursal_key = v.sucursal_key
    INNER JOIN dm_libromundo.dim_item AS i ON i.item_key = dev.item_key
    WHERE (f.fecha >= '2026-01-01' AND f.fecha < '2026-04-01')
       OR (f.fecha >= '2026-04-01' AND f.fecha < '2026-07-01')
    GROUP BY s.region, i.item_key, i.item_id, i.nombre,
             CASE WHEN f.fecha < '2026-04-01' THEN 1 ELSE 2 END
),
movimientos AS (
    SELECT region, item_key, item_id, nombre, periodo, monto, registros FROM ventas_periodo
    UNION ALL
    SELECT region, item_key, item_id, nombre, periodo, monto, registros FROM devoluciones_periodo
),
resumen AS (
    SELECT region, item_key, item_id, nombre,
           CAST(SUM(CASE WHEN periodo = 2 THEN monto ELSE 0 END) AS DECIMAL(18,2)) AS rentabilidad_q2,
           CAST(SUM(CASE WHEN periodo = 1 THEN monto ELSE 0 END) AS DECIMAL(18,2)) AS rentabilidad_q1,
           SUM(CASE WHEN periodo = 2 THEN registros ELSE 0 END) AS registros_q2,
           SUM(CASE WHEN periodo = 1 THEN registros ELSE 0 END) AS registros_q1
    FROM movimientos
    GROUP BY region, item_key, item_id, nombre
),
clasificados AS (
    SELECT region, item_key, item_id, nombre, rentabilidad_q2, rentabilidad_q1,
           registros_q2, registros_q1,
           ROW_NUMBER() OVER (
               PARTITION BY region
               ORDER BY rentabilidad_q2 DESC, item_id, item_key
           ) AS posicion
    FROM resumen
    WHERE registros_q2 > 0
)
SELECT region, posicion, item_id AS producto_id, nombre AS producto,
       rentabilidad_q2, rentabilidad_q1,
       CAST(rentabilidad_q2 - rentabilidad_q1 AS DECIMAL(18,2)) AS variacion_absoluta,
       CASE WHEN rentabilidad_q1 = 0 THEN NULL
            ELSE ROUND(100 * (rentabilidad_q2 - rentabilidad_q1) / ABS(rentabilidad_q1), 2)
       END AS variacion_porcentual,
       CASE WHEN registros_q1 = 0 THEN 1 ELSE 0 END AS sin_datos_periodo_anterior,
       CASE WHEN registros_q1 > 0 AND rentabilidad_q1 = 0 THEN 1 ELSE 0 END AS base_anterior_cero
FROM clasificados
WHERE posicion <= 5
ORDER BY region, posicion;
