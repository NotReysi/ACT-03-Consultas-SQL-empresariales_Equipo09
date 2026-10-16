-- MySQL 8: se exige ONLY_FULL_GROUP_BY para reproducir ERROR 1055.
USE dm_libromundo;
SET SESSION sql_mode = CONCAT_WS(',',
    NULLIF(@@SESSION.sql_mode, ''), 'ONLY_FULL_GROUP_BY');
SELECT @@SESSION.sql_mode AS modo_actual;

-- Ejecutar SOLO este SELECT y capturar el error 1055:
SELECT s.region, i.nombre, SUM(v.margen) AS margen
FROM fact_ventas AS v
JOIN dim_sucursal AS s ON s.sucursal_key = v.sucursal_key
JOIN dim_item AS i ON i.item_key = v.item_key
GROUP BY s.region;

-- Luego ejecutar SOLO esta correccion:
-- Una region tiene varios items; hay que agrupar cada item por region.
SELECT s.region, i.item_id, i.nombre, SUM(v.margen) AS margen
FROM fact_ventas AS v
JOIN dim_sucursal AS s ON s.sucursal_key = v.sucursal_key
JOIN dim_item AS i ON i.item_key = v.item_key
GROUP BY s.region, i.item_id, i.nombre
ORDER BY s.region, margen DESC;
