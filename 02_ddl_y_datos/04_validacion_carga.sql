USE dm_libromundo;

-- 1) Volumen (requisito: >= 1,000 filas en fact_ventas)
SELECT 'fact_ventas' AS tabla, COUNT(*) AS filas FROM fact_ventas
UNION ALL SELECT 'ventas distintas', COUNT(DISTINCT venta_id) FROM fact_ventas
UNION ALL SELECT 'devoluciones', COUNT(*) FROM fact_devoluciones;

-- 2) Cobertura por trimestre y región (>= 3 regiones, Top 5 posible)
SELECT d.trimestre, s.region, COUNT(*) AS filas, COUNT(DISTINCT f.item_key) AS productos
FROM fact_ventas f
JOIN dim_fecha d USING (fecha_key)
JOIN dim_sucursal s USING (sucursal_key)
GROUP BY d.trimestre, s.region ORDER BY 1, 2;

-- 3) Rango de fechas (debe ser 2026-01-01 a 2026-06-30)
SELECT MIN(d.fecha), MAX(d.fecha) FROM fact_ventas f JOIN dim_fecha d USING (fecha_key);

-- 4) Revisiones de integridad (todas deben dar 0)
SELECT 'grano duplicado (venta_id,item_key)' AS revision, COUNT(*) AS problemas
FROM (SELECT venta_id, item_key FROM fact_ventas GROUP BY 1,2 HAVING COUNT(*) > 1) x
UNION ALL SELECT 'margen negativo', COUNT(*) FROM fact_ventas WHERE margen < 0
UNION ALL SELECT 'venta_neta negativa', COUNT(*) FROM fact_ventas WHERE venta_neta < 0
UNION ALL SELECT 'devolución sin venta origen', COUNT(*)
  FROM fact_devoluciones dv
  LEFT JOIN fact_ventas f ON f.venta_id = dv.venta_id AND f.item_key = dv.item_key
  WHERE f.fact_venta_id IS NULL
UNION ALL SELECT 'devuelto > vendido', COUNT(*)
  FROM fact_devoluciones dv
  JOIN fact_ventas f ON f.venta_id = dv.venta_id AND f.item_key = dv.item_key
  WHERE dv.cantidad_devuelta > f.cantidad OR dv.importe_devuelto > f.venta_neta;

-- 5) Productos con ventas en Q2 pero NO en Q1 (para probar el caso "sin periodo anterior")
SELECT COUNT(DISTINCT f.item_key) AS productos_solo_q2
FROM fact_ventas f JOIN dim_fecha d USING (fecha_key)
WHERE d.trimestre = 2 AND f.item_key NOT IN (
    SELECT f2.item_key FROM fact_ventas f2 JOIN dim_fecha d2 USING (fecha_key) WHERE d2.trimestre = 1);
