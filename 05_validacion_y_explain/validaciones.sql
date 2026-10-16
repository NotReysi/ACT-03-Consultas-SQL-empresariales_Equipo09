USE dm_libromundo;
-- Volumen minimo requerido: >= 1000 filas.
SELECT COUNT(*) AS filas_ventas FROM fact_ventas;
-- Cobertura Q2: >= 3 regiones; se necesitan al menos 5 productos por region.
SELECT s.region, COUNT(*) AS filas_q2, COUNT(DISTINCT v.item_key) AS items_q2
FROM fact_ventas v
JOIN dim_fecha f ON f.fecha_key = v.fecha_key
JOIN dim_sucursal s ON s.sucursal_key = v.sucursal_key
WHERE f.fecha >= '2026-04-01' AND f.fecha < '2026-07-01'
GROUP BY s.region ORDER BY s.region;
-- Devoluciones huerfanas: ideal 0 filas. No son atribuibles al reporte.
SELECT d.devolucion_id, d.venta_id, d.item_key, d.importe_devuelto
FROM fact_devoluciones d
LEFT JOIN fact_ventas v ON v.venta_id = d.venta_id AND v.item_key = d.item_key
WHERE v.fact_venta_id IS NULL;
-- Cada devolucion debe encontrar EXACTAMENTE una venta fuente (ideal 0 filas).
SELECT d.fact_devolucion_id, COUNT(*) AS coincidencias
FROM fact_devoluciones d
LEFT JOIN fact_ventas v ON v.venta_id = d.venta_id AND v.item_key = d.item_key
GROUP BY d.fact_devolucion_id HAVING COUNT(v.fact_venta_id) <> 1;
-- Control financiero: margen de ventas sin JOIN que multiplique importes.
SELECT f.trimestre, SUM(v.margen) AS margen_ventas,
       SUM(v.venta_neta) AS ventas_netas, SUM(v.costo_total) AS costos
FROM fact_ventas v JOIN dim_fecha f ON f.fecha_key = v.fecha_key
WHERE f.anio = 2026 AND f.trimestre IN (1,2)
GROUP BY f.trimestre ORDER BY f.trimestre;
-- Validar coherencia de dimension fecha.
SELECT fecha_key, fecha, anio, trimestre FROM dim_fecha
WHERE (anio = 2026 AND trimestre = 1 AND (fecha < '2026-01-01' OR fecha >= '2026-04-01'))
   OR (anio = 2026 AND trimestre = 2 AND (fecha < '2026-04-01' OR fecha >= '2026-07-01'));
-- Validacion del Top 5: sustituir el SELECT final de consulta_final.sql por
-- SELECT region, COUNT(*) AS productos FROM clasificados
-- WHERE posicion <= 5 GROUP BY region HAVING COUNT(*) > 5;
-- Debe devolver 0 filas; CTEs solo existen durante la sentencia actual.
