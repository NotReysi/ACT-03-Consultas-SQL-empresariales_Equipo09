/* MySQL 8.0+ - CALL devuelve filas directamente; sin cursores de PostgreSQL. */
USE dm_libromundo;
DROP PROCEDURE IF EXISTS sp_top5_rentabilidad_region;
DELIMITER $$
CREATE PROCEDURE sp_top5_rentabilidad_region(
    IN p_anterior_inicio DATE,
    IN p_anterior_fin DATE,
    IN p_actual_inicio DATE,
    IN p_actual_fin DATE
)
BEGIN
    IF p_anterior_inicio IS NULL OR p_anterior_fin IS NULL
       OR p_actual_inicio IS NULL OR p_actual_fin IS NULL
       OR p_anterior_inicio >= p_anterior_fin
       OR p_actual_inicio >= p_actual_fin
       OR p_anterior_fin <> p_actual_inicio THEN
        SIGNAL SQLSTATE '45000'
           SET MESSAGE_TEXT = 'Periodos invalidos: usar intervalos consecutivos [inicio, fin)';
    END IF;
WITH ventas_periodo AS (
    SELECT s.region, i.item_key, i.item_id, i.nombre,
           CASE WHEN f.fecha < p_actual_inicio THEN 1 ELSE 2 END AS periodo,
           SUM(v.margen) AS monto, COUNT(*) AS registros
    FROM dm_libromundo.fact_ventas AS v
    INNER JOIN dm_libromundo.dim_fecha AS f ON f.fecha_key = v.fecha_key
    INNER JOIN dm_libromundo.dim_sucursal AS s ON s.sucursal_key = v.sucursal_key
    INNER JOIN dm_libromundo.dim_item AS i ON i.item_key = v.item_key
    WHERE (f.fecha >= p_anterior_inicio AND f.fecha < p_anterior_fin)
       OR (f.fecha >= p_actual_inicio AND f.fecha < p_actual_fin)
    GROUP BY s.region, i.item_key, i.item_id, i.nombre,
             CASE WHEN f.fecha < p_actual_inicio THEN 1 ELSE 2 END
),
devoluciones_periodo AS (
    SELECT s.region, i.item_key, i.item_id, i.nombre,
           CASE WHEN f.fecha < p_actual_inicio THEN 1 ELSE 2 END AS periodo,
           -SUM(dev.importe_devuelto) AS monto, COUNT(*) AS registros
    FROM dm_libromundo.fact_devoluciones AS dev
    INNER JOIN dm_libromundo.fact_ventas AS v
      ON v.venta_id = dev.venta_id AND v.item_key = dev.item_key
    INNER JOIN dm_libromundo.dim_fecha AS f ON f.fecha_key = v.fecha_key
    INNER JOIN dm_libromundo.dim_sucursal AS s ON s.sucursal_key = v.sucursal_key
    INNER JOIN dm_libromundo.dim_item AS i ON i.item_key = dev.item_key
    WHERE (f.fecha >= p_anterior_inicio AND f.fecha < p_anterior_fin)
       OR (f.fecha >= p_actual_inicio AND f.fecha < p_actual_fin)
    GROUP BY s.region, i.item_key, i.item_id, i.nombre,
             CASE WHEN f.fecha < p_actual_inicio THEN 1 ELSE 2 END
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
END$$
DELIMITER ;

-- Una sola llamada produce el reporte, sin duplicar la consulta.
CALL sp_top5_rentabilidad_region('2026-01-01','2026-04-01',
                                 '2026-04-01','2026-07-01');
