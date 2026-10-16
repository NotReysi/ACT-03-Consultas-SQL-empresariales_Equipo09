# Definición de Negocio: Rentabilidad Operativa (LibroMundo)

Para la Actividad 3, la rentabilidad se define como la utilidad en pesos de cada ítem, agregada por región y trimestre:
**Rentabilidad = margen de ventas netas - importe devuelto**

*   **Margen:** Se utiliza la columna `fact_ventas.margen` (calculada como `venta_neta - costo_total`).
*   **Importe devuelto:** Se suma `fact_devoluciones.importe_devuelto`. 
*   **Regla de Temporalidad (CORREGIDA):** Las devoluciones se asignan al **trimestre de la venta original**, no al trimestre en el que se realizó la devolución. Esto asegura que el desempeño de un periodo no se vea penalizado por ventas de trimestres anteriores.
*   **Región:** Se obtiene de `dim_sucursal.region`. Las sucursales sin región quedan fuera del Top 5.
*   **Filtros:** Entran todos los canales y clientes. No se excluyen cancelaciones porque el DDL inicial no contempló un campo de estado de venta.