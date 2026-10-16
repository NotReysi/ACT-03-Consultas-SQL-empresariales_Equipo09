# Prompt Inicial utilizado para generar la consulta SQL

**Contexto:**
Actúa como analista SQL para MySQL 8.0+. Trabajamos con la empresa LibroMundo y necesitamos construir un reporte que identifique los cinco productos con mayor rentabilidad en cada región durante el segundo trimestre de 2026, mostrando la variación frente al primer trimestre de 2026.

**Grano:**
El grano de la tabla de hechos (`fact_ventas`) es un ítem vendido dentro de una transacción.

**Esquema disponible:**
*   `fact_ventas` (venta_id, fecha_key, item_key, sucursal_key, margen)
*   `fact_devoluciones` (devolucion_id, venta_id, item_key, fecha_key, importe_devuelto)
*   `dim_fecha` (fecha_key, fecha, trimestre, anio)
*   `dim_sucursal` (sucursal_key, region)
*   `dim_item` (item_key, item_id, nombre)

**Reglas de negocio:**
*   Rentabilidad = `SUM(fact_ventas.margen) - SUM(fact_devoluciones.importe_devuelto)`.
*   Las devoluciones deben vincularse a la fecha de la venta original, no a la fecha de la devolución. Para esto, se debe hacer JOIN de `fact_devoluciones` con `fact_ventas` usando `venta_id` y `item_key`.
*   Periodo actual: 2026-04-01 a 2026-07-01. Periodo anterior: 2026-01-01 a 2026-04-01.

**Salida esperada:**
La salida debe contener: region, posicion, producto_id, producto, rentabilidad_q2, rentabilidad_q1, variacion_absoluta, variacion_porcentual, sin_datos_periodo_anterior, base_anterior_cero. Se debe usar una función de ventana para clasificar el Top 5 por región.

Antes de escribir SQL, enumera tus supuestos. Después explica cada CTE, JOIN y función de ventana.