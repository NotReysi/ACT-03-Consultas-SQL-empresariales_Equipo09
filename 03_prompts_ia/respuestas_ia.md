Contexto: Actúa como analista SQL para MySQL 8.0+. Trabajamos con la empresa LibroMundo y necesitamos construir un reporte que identifique los cinco productos con mayor rentabilidad en cada región durante el segundo trimestre de 2026, mostrando la variación frente al primer trimestre de 2026.
Grano: El grano de la tabla de hechos (fact_ventas) es un ítem vendido dentro de una transacción.
Esquema disponible:

fact_ventas (venta_id, fecha_key, item_key, sucursal_key, margen)
fact_devoluciones (devolucion_id, venta_id, item_key, fecha_key, importe_devuelto)
dim_fecha (fecha_key, fecha, trimestre, anio)
dim_sucursal (sucursal_key, region)
dim_item (item_key, item_id, nombre)
Reglas de negocio:

Rentabilidad = SUM(fact_ventas.margen) - SUM(fact_devoluciones.importe_devuelto).
Las devoluciones deben vincularse a la fecha de la venta original, no a la fecha de la devolución. Para esto, se debe hacer JOIN de fact_devoluciones con fact_ventas usando venta_id y item_key.
Periodo actual: 2026-04-01 a 2026-07-01. Periodo anterior: 2026-01-01 a 2026-04-01.
Salida esperada: La salida debe contener: region, posicion, producto_id, producto, rentabilidad_q2, rentabilidad_q1, variacion_absoluta, variacion_porcentual, sin_datos_periodo_anterior, base_anterior_cero. Se debe usar una función de ventana para clasificar el Top 5 por región.
Antes de escribir SQL, enumera tus supuestos. Después explica cada CTE, JOIN y función de ventana.

Construyendo el ranking regional con desempate por producto y marcadores.
Reporte Top 5 productos por rentabilidad y región: Q2 2026 vs Q1 2026
1. Supuestos
Grano y unicidad: fact_ventas tiene una fila por (venta_id, item_key), como indica el DDL (uq_fact_ventas_grano). Por eso la llave de enlace con devoluciones es (venta_id, item_key).
Riesgo de fan-out: fact_devoluciones puede tener varias devoluciones para el mismo (venta_id, item_key), por ejemplo devoluciones parciales. Si se hiciera el JOIN directo, margen se duplicaría. Por eso agrego las devoluciones antes del JOIN.
Fecha y región de la venta original: el periodo y la región de una devolución son los de la venta original. No uso fact_devoluciones.fecha_key ni fact_devoluciones.sucursal_key.
Devoluciones huérfanas: una devolución sin venta correspondiente no aparece, porque se parte de fact_ventas con LEFT JOIN a las devoluciones. Una venta sin devoluciones cuenta con importe devuelto = 0.
Rangos semiabiertos: fecha >= inicio AND fecha < fin. Q2 es [2026-04-01, 2026-07-01) y Q1 es [2026-01-01, 2026-04-01).
Dimensión de análisis: producto = item_key dentro de una región. La comparación Q1 vs Q2 es del mismo producto en la misma región.
Universo del ranking: solo entran productos con al menos una fila de venta en Q2 de esa región. El ranking se hace por rentabilidad_q2 descendente, incluyendo valores negativos.
Empates: uso ROW_NUMBER() con desempate por item_id ascendente, para obtener exactamente 5 filas por región y un resultado determinista. Si prefieres incluir empatados, se cambia a RANK() o DENSE_RANK().
Sin datos en Q1: si no hay ninguna fila de venta en Q1, sin_datos_periodo_anterior = 1, rentabilidad_q1 = 0, variacion_absoluta = rentabilidad_q2 y variacion_porcentual = NULL.
Base cero: si hay ventas en Q1 pero la rentabilidad neta es exactamente 0, base_anterior_cero = 1 y variacion_porcentual = NULL, para evitar división entre cero.
Base negativa: el porcentaje se calcula sobre ABS(rentabilidad_q1). Así un cambio de -100 a +50 se muestra como mejora (+150 %) y no como caída.
Región nula: si dim_sucursal.region es NULL, se agrupa como 'SIN REGION'.
Medida: margen es columna generada y NOT NULL, y ya incluye el descuento. Los importes se redondean a 2 decimales.
2. SQL (MySQL 8.0+)
sql
WITH devoluciones_por_venta_item AS (
    SELECT
        d.venta_id,
        d.item_key,
        SUM(d.importe_devuelto) AS importe_devuelto
    FROM fact_devoluciones AS d
    GROUP BY d.venta_id, d.item_key
),
ventas_periodo AS (
    SELECT
        fv.venta_id,
        fv.item_key,
        fv.sucursal_key,
        CASE
            WHEN df.fecha >= '2026-04-01' AND df.fecha < '2026-07-01'
                THEN 'ACTUAL'
            ELSE 'ANTERIOR'
        END AS periodo,
        fv.margen,
        COALESCE(dv.importe_devuelto, 0) AS importe_devuelto
    FROM fact_ventas AS fv
    INNER JOIN dim_fecha AS df
            ON df.fecha_key = fv.fecha_key
    LEFT JOIN devoluciones_por_venta_item AS dv
           ON dv.venta_id = fv.venta_id
          AND dv.item_key = fv.item_key
    WHERE df.fecha >= '2026-01-01'
      AND df.fecha <  '2026-07-01'
),
rentabilidad AS (
    SELECT
        COALESCE(ds.region, 'SIN REGION') AS region,
        di.item_id                        AS producto_id,
        di.nombre                         AS producto,
        SUM(CASE WHEN vp.periodo = 'ACTUAL'
                 THEN vp.margen - vp.importe_devuelto ELSE 0 END) AS rentabilidad_q2,
        SUM(CASE WHEN vp.periodo = 'ANTERIOR'
                 THEN vp.margen - vp.importe_devuelto ELSE 0 END) AS rentabilidad_q1,
        SUM(CASE WHEN vp.periodo = 'ACTUAL'   THEN 1 ELSE 0 END)   AS filas_q2,
        SUM(CASE WHEN vp.periodo = 'ANTERIOR' THEN 1 ELSE 0 END)   AS filas_q1
    FROM ventas_periodo AS vp
    INNER JOIN dim_sucursal AS ds
            ON ds.sucursal_key = vp.sucursal_key
    INNER JOIN dim_item AS di
            ON di.item_key = vp.item_key
    GROUP BY COALESCE(ds.region, 'SIN REGION'), di.item_key, di.item_id, di.nombre
    HAVING SUM(CASE WHEN vp.periodo = 'ACTUAL' THEN 1 ELSE 0 END) > 0
),
ranking AS (
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY r.region
            ORDER BY r.rentabilidad_q2 DESC, r.producto_id ASC
        ) AS posicion
    FROM rentabilidad AS r
)
SELECT
    region,
    posicion,
    producto_id,
    producto,
    ROUND(rentabilidad_q2, 2)                      AS rentabilidad_q2,
    ROUND(rentabilidad_q1, 2)                      AS rentabilidad_q1,
    ROUND(rentabilidad_q2 - rentabilidad_q1, 2)    AS variacion_absoluta,
    CASE
        WHEN filas_q1 = 0 OR rentabilidad_q1 = 0 THEN NULL
        ELSE ROUND((rentabilidad_q2 - rentabilidad_q1)
                   / ABS(rentabilidad_q1) * 100, 2)
    END                                            AS variacion_porcentual,
    CASE WHEN filas_q1 = 0 THEN 1 ELSE 0 END       AS sin_datos_periodo_anterior,
    CASE WHEN filas_q1 > 0 AND rentabilidad_q1 = 0
         THEN 1 ELSE 0 END                         AS base_anterior_cero
FROM ranking
WHERE posicion <= 5
ORDER BY region, posicion;
3. Explicación
CTEs
devoluciones_por_venta_item: reduce fact_devoluciones a una fila por (venta_id, item_key) sumando importe_devuelto. Esto garantiza que el JOIN posterior sea 1:1 con fact_ventas y que el margen no se multiplique cuando hay varias devoluciones de la misma línea.
ventas_periodo: toma las ventas de Q1 y Q2 (un solo filtro de fechas sobre dim_fecha), etiqueta cada fila como ACTUAL o ANTERIOR y le adjunta su importe devuelto (0 si no hubo). Como la fecha sale de la venta, cumple la regla de vincular la devolución a la fecha de la venta original.
rentabilidad: agrupa por región y producto y calcula ambos trimestres en una sola pasada con agregación condicional (SUM(CASE ...)). Sumar margen - importe_devuelto por fila equivale a SUM(margen) - SUM(importe_devuelto). Los contadores filas_q1 y filas_q2 distinguen “sin datos” de “rentabilidad igual a cero”. El HAVING deja solo productos con ventas en Q2.
ranking: añade la posición con la función de ventana. Es una CTE aparte porque MySQL no permite usar una función de ventana en el WHERE de la misma consulta.
JOINs
fact_ventas → dim_fecha (INNER, por fecha_key): obtiene la fecha real para filtrar y clasificar el periodo.
fact_ventas → devoluciones pre-agregadas (LEFT, por venta_id e item_key): conserva las ventas sin devoluciones. Es el JOIN que exige la regla de negocio.
ventas_periodo → dim_sucursal (INNER, por sucursal_key): trae la región.
ventas_periodo → dim_item (INNER, por item_key): trae item_id y nombre.
Función de ventana
ROW_NUMBER() OVER (PARTITION BY region ORDER BY rentabilidad_q2 DESC, producto_id ASC):

PARTITION BY region reinicia el conteo en cada región.
ORDER BY rentabilidad_q2 DESC pone primero al producto más rentable.
producto_id ASC rompe empates para que siempre haya exactamente 5 filas por región con resultado reproducible.
El filtro posicion <= 5 se aplica en el SELECT final, ya sobre la CTE ranking.
Cálculos finales
variacion_absoluta = rentabilidad_q2 - rentabilidad_q1.
variacion_porcentual es NULL cuando no hay datos previos o la base es 0. Si no, usa ABS(rentabilidad_q1) en el denominador.
Los dos indicadores son excluyentes: sin_datos_periodo_anterior significa que no hubo ventas en Q1, y base_anterior_cero que sí las hubo pero la rentabilidad neta fue 0.
Nota de rendimiento: un índice como fact_devoluciones(venta_id, item_key) ayuda al agrupamiento de la primera CTE. En fact_ventas ya existe la restricción única (venta_id, item_key) y el índice por fecha_key. Como no se creó un índice compuesto en fact_devoluciones, vale la pena añadirlo si el volumen es alto.

Verifica cada afirmación de tus supuestos contra el DDL que te di y marca cuáles no están respaldadas literalmente

Preparando la tabla de veredictos y correcciones literales.
Verificación de supuestos contra el DDL
Leyenda: ✅ respaldado literalmente por el DDL · ⚠️ respaldado en parte · ❌ no está en el DDL (decisión mía o interpretación de tu enunciado)

#	Afirmación	Estado	Evidencia o comentario
1	fact_ventas tiene una fila por (venta_id, item_key)	✅	CONSTRAINT uq_fact_ventas_grano UNIQUE (venta_id, item_key) y el comentario “Grano: un ITEM vendido dentro de una transacción”.
2	fact_devoluciones puede tener varias filas por (venta_id, item_key), “por ejemplo devoluciones parciales”	⚠️	Lo respalda que no existe ningún UNIQUE sobre (venta_id, item_key) en fact_devoluciones, solo sobre devolucion_id. Lo de “devoluciones parciales” es inferencia mía. El DDL no lo dice, solo sugiere algo parecido el comentario sobre cantidad_devuelta.
3	Usar fecha y región de la venta original, no fecha_key ni sucursal_key de la devolución	✅	Ambas columnas existen en fact_devoluciones (sucursal_key es nullable). La regla de negocio es tuya. Ojo: sucursal_key está en el DDL pero no en el esquema que listaste en el enunciado.
4	Pueden existir devoluciones huérfanas	✅	fact_devoluciones no declara FK hacia fact_ventas, ni por venta_id ni por (venta_id, item_key). Que no aparezcan en el resultado es consecuencia de mi consulta, no del DDL.
5	Rangos semiabiertos >= inicio AND < fin	❌	Es mi interpretación de “2026-04-01 a 2026-07-01”. Tu texto no dice si el fin es inclusivo. Lo único que el DDL respalda es que dim_fecha.fecha es DATE, así que la comparación funciona.
6	Producto = item_key; dim_item aporta item_id y nombre	✅	item_key es PK, item_id es NOT NULL UNIQUE y nombre es NOT NULL. La región sale de dim_sucursal.region.
7	Solo entran productos con ventas en Q2; el ranking incluye valores negativos	❌	Es decisión de diseño. Lo único respaldado es que un margen negativo es posible: el único CHECK es descuento <= cantidad * precio_unitario y nada impide costo_unitario > precio_unitario.
8	ROW_NUMBER con desempate por item_id da un resultado determinista y “exactamente 5” filas por región	⚠️	item_id es NOT NULL UNIQUE, así que el desempate sí es determinista. “Exactamente 5” es incorrecto: son hasta 5, porque una región con menos de 5 productos devuelve menos.
9	Sin ventas en Q1: rentabilidad_q1 = 0, variacion_porcentual = NULL, bandera = 1	❌	Convención mía.
10	Base cero: variacion_porcentual = NULL, base_anterior_cero = 1	❌	Convención mía.
11	Porcentaje sobre ABS(rentabilidad_q1)	❌	Convención mía. La aritmética del ejemplo (-100 a +50 = +150 %) es correcta, pero la regla no sale del DDL.
12	Región nula se agrupa como 'SIN REGION'	✅	region VARCHAR(100) sin NOT NULL. Además fact_ventas.sucursal_key es NOT NULL con FK, así que el INNER JOIN a dim_sucursal no pierde filas.
13	margen es columna generada, NOT NULL, incluye el descuento y se redondea a 2 decimales	⚠️	Generada (GENERATED ALWAYS AS ... STORED): ✅. Incluye el descuento: ✅. Redondeo a 2 decimales: ✅ (ROUND(..., 2) y tipo NUMERIC(14,2)). NOT NULL: ❌, la columna no lo declara. En la práctica no puede ser nula porque cantidad, precio_unitario, descuento y costo_unitario son NOT NULL, pero eso es deducción, no declaración.
Otras afirmaciones fuera de la lista de supuestos
“El JOIN posterior es 1:1” (CTE de devoluciones): es impreciso. Como es LEFT JOIN, la relación es 1:0..1. Lo que garantiza que no haya fan-out es la unicidad de (venta_id, item_key) en fact_ventas más la agregación previa.
Nota de rendimiento sobre el índice: es incompleta. El DDL sí define idx_fact_devoluciones_venta sobre venta_id. Lo que falta es el índice compuesto (venta_id, item_key). Lo que dije del índice por fecha_key y de la restricción única en fact_ventas sí es correcto (idx_fact_ventas_fecha, uq_fact_ventas_grano).
“MySQL no permite funciones de ventana en el WHERE”: es conocimiento general de MySQL, no del DDL.
Redacciones corregidas
Supuesto 2: “fact_devoluciones no tiene restricción de unicidad sobre (venta_id, item_key), por lo que el DDL permite varias devoluciones para la misma línea de venta. Agrego antes del JOIN para evitar duplicar margen.”
Supuesto 8: “ROW_NUMBER() con desempate por item_id (único y no nulo) devuelve hasta 5 filas por región, de forma determinista.”
Supuesto 13: “margen es una columna generada almacenada que ya descuenta descuento y costo_unitario. No está declarada NOT NULL, pero sus insumos sí lo son, así que no debería ser nula.”
Supuestos 5, 7, 9, 10 y 11: marcarlos como decisiones del analista, no como hechos del esquema. Conviene confirmar con LibroMundo sobre todo el 5 (fin de periodo inclusivo o exclusivo) y el 7 (si deben aparecer productos sin ventas en Q2).
Ninguna de estas correcciones cambia la lógica del SQL. Cambian cómo se documenta lo que el modelo garantiza y lo que decidimos nosotros.

Escríbeme una consulta de diagnóstico que cuente las devoluciones sin venta correspondiente en (venta_id, item_key) y sume su importe_devuelto, para saber cuánto estamos dejando fuera

Flagging order lines where returns surpass net sales.
Flagging order lines where returns surpass net sales.
Diagnóstico: devoluciones que superan venta_neta
Consulta principal
sql
WITH devoluciones_por_linea AS (
    SELECT
        d.venta_id,
        d.item_key,
        COUNT(*)                 AS num_devoluciones,
        SUM(d.importe_devuelto)  AS importe_devuelto_total
    FROM fact_devoluciones AS d
    GROUP BY d.venta_id, d.item_key
)
SELECT
    fv.venta_id,
    fv.item_key,
    di.item_id                                              AS producto_id,
    di.nombre                                               AS producto,
    df.fecha                                                AS fecha_venta,
    fv.venta_neta,
    dl.num_devoluciones,
    dl.importe_devuelto_total,
    ROUND(dl.importe_devuelto_total - fv.venta_neta, 2)     AS exceso,
    ROUND(100 * dl.importe_devuelto_total
              / NULLIF(fv.venta_neta, 0), 2)                AS pct_sobre_venta_neta,
    CASE
        WHEN df.fecha >= '2026-01-01' AND df.fecha < '2026-07-01'
            THEN 1 ELSE 0
    END                                                     AS afecta_reporte
FROM fact_ventas AS fv
INNER JOIN devoluciones_por_linea AS dl
        ON dl.venta_id = fv.venta_id
       AND dl.item_key = fv.item_key
INNER JOIN dim_fecha AS df
        ON df.fecha_key = fv.fecha_key
INNER JOIN dim_item AS di
        ON di.item_key = fv.item_key
WHERE dl.importe_devuelto_total > fv.venta_neta
ORDER BY exceso DESC;
Cómo funciona
CTE devoluciones_por_linea: suma las devoluciones por (venta_id, item_key) antes de comparar. Si se compara fila a fila, dos devoluciones parciales de 60 sobre una venta de 100 pasarían desapercibidas.
INNER JOIN a fact_ventas: la comparación solo tiene sentido donde existe venta. Las huérfanas ya las cubre el diagnóstico anterior.
venta_neta: es una columna generada y almacenada de fact_ventas, así que se compara directamente sin recalcularla.
NULLIF(fv.venta_neta, 0): una línea puede tener venta_neta = 0 (el CHECK permite descuento igual al bruto). En ese caso cualquier devolución positiva es un exceso y el porcentaje queda NULL.
afecta_reporte: marca las líneas cuya venta cae en Q1 o Q2, que son las que distorsionan el reporte.
Resumen de impacto (opcional)
sql
WITH devoluciones_por_linea AS (
    SELECT venta_id, item_key, SUM(importe_devuelto) AS importe_devuelto_total
    FROM fact_devoluciones
    GROUP BY venta_id, item_key
)
SELECT
    COUNT(*)                                                    AS lineas_con_exceso,
    ROUND(SUM(dl.importe_devuelto_total - fv.venta_neta), 2)    AS exceso_total
FROM fact_ventas AS fv
INNER JOIN devoluciones_por_linea AS dl
        ON dl.venta_id = fv.venta_id
       AND dl.item_key = fv.item_key
WHERE dl.importe_devuelto_total > fv.venta_neta;
Qué revisar si aparecen resultados
Comparación contra venta_neta y no contra venta_bruta: el DDL no dice si importe_devuelto se calcula sobre el precio de lista o sobre lo efectivamente pagado. Si es sobre el precio de lista, una línea con descuento puede mostrar un exceso que en realidad es una diferencia de base. Compara también contra venta_bruta para distinguirlo: si el exceso desaparece, el problema es de criterio de cálculo y no de datos.
Devoluciones duplicadas: varias devoluciones con importes idénticos sobre la misma línea suelen indicar una carga repetida en el ETL.
Efecto en el reporte: la regla de rentabilidad resta importe_devuelto completo del margen, así que un exceso resta más de lo que la venta aportó y puede hacer negativa la rentabilidad de un producto.
Validación complementaria por cantidad
El DDL tiene cantidad_devuelta (extensión propuesta, nullable), que permite una segunda prueba independiente del importe:

sql
SELECT
    fv.venta_id,
    fv.item_key,
    fv.cantidad,
    SUM(d.cantidad_devuelta) AS cantidad_devuelta_total
FROM fact_ventas AS fv
INNER JOIN fact_devoluciones AS d
        ON d.venta_id = fv.venta_id
       AND d.item_key = fv.item_key
GROUP BY fv.venta_id, fv.item_key, fv.cantidad
HAVING SUM(d.cantidad_devuelta) > fv.cantidad;
Aquí el JOIN directo no duplica fv.cantidad porque se agrupa por ella y se suma solo del lado de devoluciones. Las filas con cantidad_devuelta nula se ignoran en la suma, así que esta prueba solo cubre las devoluciones que sí traen ese dato.


USE dm_libromundo; -- 1. Llenar Dimensión Fecha (Todo 2026) SET cte_max_recursion_depth = 4000; INSERT INTO dim_fecha (fecha_key, fecha, dia, nombre_dia, semana, mes, nombre_mes, trimestre, anio, es_fin_semana) WITH RECURSIVE fechas AS ( SELECT CAST('2026-01-01' AS DATE) AS d UNION A

pasted

Dame datos mínimos (un producto con devoluciones parciales, uno sin ventas en Q1, uno con Q1 en cero, un empate en el Top 5) y el resultado esperado para cada caso

Identificando qué errores comunes detecta cada caso de prueba.
Datos de prueba mínimos y resultado esperado
Todo va en una región aparte (PRUEBA, sucursal 901) con ítems 9001 a 9006 y venta_id desde 900101. Así no se mezcla con los datos aleatorios del script de carga, que usa venta_id 1 a 1300 y los ítems 1 a 60. Cada línea tiene cantidad = 1, descuento = 0 y costo_unitario = 100, y el precio_unitario es 100 + margen, de modo que el margen sale exacto.

Casos que cubre
Producto	Caso	Líneas
9001	Devoluciones parciales	Q1: margen 220, devolución de 20 fechada en abril. Q2: margen 500, devoluciones de 60 (mayo) y 40 (fechada el 10 de julio)
9002	Sin ventas en Q1	Q2: margen 350. Más una línea del 2026-07-01 con margen 999 que no debe contarse
9003	Q1 en cero	Q1: margen 150 con devolución de 150. Q2: margen 300
9004	Relleno solo Q2	Q2: margen 260
9005 y 9006	Empate en el puesto 5	Ambos con Q2 = 250. 9005 tiene Q1 de 200 y 9006 tiene Q1 de 500
Script de carga
sql
USE dm_libromundo;

-- Sucursal e ítems de prueba
INSERT INTO dim_sucursal (sucursal_id, nombre, ciudad, region)
VALUES (901, 'Sucursal Prueba', 'Prueba', 'PRUEBA');

INSERT INTO dim_item (item_id, tipo_item, nombre, isbn) VALUES
(9001, 'LIBRO', 'P1 Devoluciones parciales', 'TEST-9001'),
(9002, 'LIBRO', 'P2 Sin ventas en Q1',       'TEST-9002'),
(9003, 'LIBRO', 'P3 Q1 en cero',             'TEST-9003'),
(9004, 'LIBRO', 'P4 Relleno solo Q2',        'TEST-9004'),
(9005, 'LIBRO', 'P5 Empate (entra)',         'TEST-9005'),
(9006, 'LIBRO', 'P6 Empate (queda fuera)',   'TEST-9006');

-- Ventas (cliente -1 = no identificado, canal 1)
INSERT INTO fact_ventas
  (venta_id, fecha_key, cliente_key, item_key, sucursal_key, canal_key,
   cantidad, precio_unitario, descuento, costo_unitario, es_preventa)
SELECT t.venta_id, t.fecha_key, c.cliente_key, i.item_key, s.sucursal_key,
       ca.canal_key, 1, 100 + t.margen, 0, 100, FALSE
FROM (
    SELECT 900101 AS venta_id, 9001 AS item_id, 20260310 AS fecha_key, 220 AS margen
    UNION ALL SELECT 900102, 9001, 20260515, 500
    UNION ALL SELECT 900201, 9002, 20260420, 350
    UNION ALL SELECT 900202, 9002, 20260701, 999   -- fuera de Q2 (límite exclusivo)
    UNION ALL SELECT 900301, 9003, 20260214, 150
    UNION ALL SELECT 900302, 9003, 20260602, 300
    UNION ALL SELECT 900401, 9004, 20260505, 260
    UNION ALL SELECT 900501, 9005, 20260101, 200   -- primer día de Q1
    UNION ALL SELECT 900502, 9005, 20260615, 250
    UNION ALL SELECT 900601, 9006, 20260331, 500   -- último día de Q1
    UNION ALL SELECT 900602, 9006, 20260401, 250   -- primer día de Q2
) AS t
JOIN dim_item     i  ON i.item_id      = t.item_id
JOIN dim_sucursal s  ON s.sucursal_id  = 901
JOIN dim_cliente  c  ON c.cliente_id   = -1
JOIN dim_canal    ca ON ca.canal_id    = 1;

-- Devoluciones
INSERT INTO fact_devoluciones
  (devolucion_id, venta_id, fecha_key, item_key, sucursal_key,
   motivo_devolucion, importe_devuelto, cantidad_devuelta)
SELECT t.devolucion_id, t.venta_id, t.fecha_key, i.item_key, s.sucursal_key,
       'Prueba', t.importe, NULL
FROM (
    SELECT 800001 AS devolucion_id, 900101 AS venta_id, 9001 AS item_id,
           20260405 AS fecha_key, 20 AS importe      -- devolución en Q2 de venta de Q1
    UNION ALL SELECT 800002, 900102, 9001, 20260520, 60
    UNION ALL SELECT 800003, 900102, 9001, 20260710, 40   -- devolución fechada en Q3
    UNION ALL SELECT 800004, 900301, 9003, 20260320, 150  -- anula todo el margen de Q1
) AS t
JOIN dim_item     i ON i.item_id     = t.item_id
JOIN dim_sucursal s ON s.sucursal_id = 901;
Cómo ejecutar el reporte
Usa la consulta del reporte tal cual, pero en el SELECT final cambia el filtro a WHERE posicion <= 5 AND region = 'PRUEBA'. Las demás regiones tienen datos aleatorios y no sirven para comparar.

Resultado esperado (5 filas)
region	posicion	producto_id	producto	rentabilidad_q2	rentabilidad_q1	variacion_absoluta	variacion_porcentual	sin_datos_periodo_anterior	base_anterior_cero
PRUEBA	1	9001	P1 Devoluciones parciales	400.00	200.00	200.00	100.00	0	0
PRUEBA	2	9002	P2 Sin ventas en Q1	350.00	0.00	350.00	NULL	1	0
PRUEBA	3	9003	P3 Q1 en cero	300.00	0.00	300.00	NULL	0	1
PRUEBA	4	9004	P4 Relleno solo Q2	260.00	0.00	260.00	NULL	1	0
PRUEBA	5	9005	P5 Empate (entra)	250.00	200.00	50.00	25.00	0	0
Debe quedar fuera el 9006, que sería la posición 6 con Q2 = 250, Q1 = 500, variación de -250.00 y -50.00 %.

Qué error detecta cada caso
Caso	Si el SQL falla, verás
9001, devoluciones parciales	Con JOIN directo sin pre-agregar, Q2 sale 900 en lugar de 400, porque el margen de 500 se duplica por cada devolución
9001, devolución del 05-abr sobre venta de marzo	Si se usara la fecha de la devolución, Q1 saldría 220 y Q2 bajaría 20
9001, devolución del 10-jul	Con la fecha de la devolución, esos 40 se perderían y Q2 saldría 440
9002, sin Q1	sin_datos_periodo_anterior en 0, o variacion_porcentual distinto de NULL
9002, línea del 01-jul	Si el fin fuera inclusivo, Q2 saldría 1349 y pasaría al puesto 1
9003, Q1 en cero	Marcado como sin_datos_periodo_anterior = 1 (error de usar rentabilidad_q1 = 0 como criterio) o error de división entre cero
9005 y 9006, empate	Con RANK() aparecen 6 filas. Sin desempate por item_id, el producto que entra puede cambiar entre ejecuciones
Línea 900602 (01-abr) y 900501 (01-ene)	Si el inicio fuera exclusivo, Q2 o Q1 perderían esas líneas
Limpieza
sql
DELETE FROM fact_devoluciones WHERE devolucion_id BETWEEN 800001 AND 800004;
DELETE FROM fact_ventas       WHERE venta_id BETWEEN 900101 AND 900602;
DELETE FROM dim_item          WHERE item_id BETWEEN 9001 AND 9006;
DELETE FROM dim_sucursal      WHERE sucursal_id = 901;
Calculé los resultados a mano y no ejecuté el script en MySQL. Si algún valor difiere, compara primero la CTE rentabilidad para ver si el desajuste viene del agrupamiento o del ranking. Ninguna devolución supera su venta_neta (20 de 320, 100 de 600, 150 de 250), así que el diagnóstico de excesos debe devolver 0 filas para estos datos.

