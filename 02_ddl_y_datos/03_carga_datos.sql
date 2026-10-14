/* ================================================================
   CARGA DE DATOS SIMULADOS - DATA MART LIBROMUNDO (PostgreSQL)
   Ejecutar DESPUÉS del DDL (01/02). Datos 100% ficticios.
   Cobertura: 1-ene-2026 a 30-jun-2026 (Q1 y Q2), 3 regiones.
   Es determinista: setseed fija el azar, así todos obtienen
   los mismos datos al correrlo.
================================================================ */
SET search_path TO dm_libromundo;
SELECT setseed(0.42);

/* ---------- DIM_FECHA (todo 2026) ---------- */
INSERT INTO dim_fecha (fecha_key, fecha, dia, nombre_dia, semana, mes,
                       nombre_mes, trimestre, anio, es_fin_semana)
SELECT to_char(d,'YYYYMMDD')::INT,
       d::DATE,
       EXTRACT(DAY FROM d)::SMALLINT,
       (ARRAY['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'])[EXTRACT(ISODOW FROM d)::INT],
       EXTRACT(WEEK FROM d)::SMALLINT,
       EXTRACT(MONTH FROM d)::SMALLINT,
       (ARRAY['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])[EXTRACT(MONTH FROM d)::INT],
       EXTRACT(QUARTER FROM d)::SMALLINT,
       EXTRACT(YEAR FROM d)::SMALLINT,
       EXTRACT(ISODOW FROM d) IN (6,7)
FROM generate_series('2026-01-01'::DATE, '2026-12-31'::DATE, '1 day') AS d;

/* ---------- DIM_SUCURSAL (6 sucursales, 3 regiones) ---------- */
INSERT INTO dim_sucursal (sucursal_id, nombre, ciudad, region) VALUES
 (1,'LibroMundo Monterrey Centro','Monterrey','Noreste'),
 (2,'LibroMundo San Pedro','San Pedro Garza García','Noreste'),
 (3,'LibroMundo CDMX Reforma','Ciudad de México','Centro'),
 (4,'LibroMundo Puebla Angelópolis','Puebla','Centro'),
 (5,'LibroMundo Guadalajara Andares','Guadalajara','Occidente'),
 (6,'LibroMundo León Centro','León','Occidente');

/* ---------- DIM_CANAL (preventa NO es canal) ---------- */
INSERT INTO dim_canal (canal_id, nombre_canal) VALUES
 (1,'Tienda física'),(2,'E-commerce'),(3,'Venta institucional');

/* ---------- DIM_CLIENTE (60 ficticios; el -1 ya existe en el DDL) ---------- */
INSERT INTO dim_cliente (cliente_id, nombre, tipo_cliente, segmento_cliente, ciudad, limite_credito)
SELECT n,
       CASE WHEN n%4=0 THEN 'Escuela Demo '||n
            WHEN n%4=1 THEN 'Consumidor Demo '||n
            WHEN n%4=2 THEN 'Empresa Demo '||n
            ELSE 'Club de lectura Demo '||n END,
       CASE n%4 WHEN 0 THEN 'ESCUELA' WHEN 1 THEN 'CONSUMIDOR'
                WHEN 2 THEN 'EMPRESA'  ELSE 'CLUB_LECTURA' END,
       CASE WHEN n%4 IN (0,2) THEN 'INSTITUCIONAL' ELSE 'MINORISTA' END,
       (ARRAY['Monterrey','Ciudad de México','Puebla','Guadalajara','León'])[1 + n%5],
       CASE WHEN n%4 IN (0,2) THEN 50000 + (n%5)*10000 ELSE NULL END
FROM generate_series(1,60) AS n;

/* ---------- AUTORES, GÉNEROS ---------- */
INSERT INTO dim_autor (autor_id, nombre_autor)
SELECT n, 'Autor Ficticio '||n FROM generate_series(1,25) n;

INSERT INTO dim_genero (genero_id, nombre_genero) VALUES
 (1,'Novela'),(2,'Juvenil'),(3,'Infantil'),(4,'Ciencia ficción'),
 (5,'Historia'),(6,'Negocios'),(7,'Poesía'),(8,'Texto escolar');

/* ---------- DIM_ITEM: 40 libros + 20 no editoriales ----------
   Libros 31-40 se lanzan en mayo/junio 2026 => no tendrán ventas
   en Q1 (sirven para probar el caso "sin datos en periodo anterior"). */
INSERT INTO dim_item (item_id, tipo_item, sku, nombre, isbn, idioma,
                      fecha_lanzamiento, editorial, categoria_producto, marca)
SELECT n, 'LIBRO', NULL, 'Libro Demo '||n,
       '978-607-'||lpad(n::TEXT,6,'0'),
       CASE WHEN n%10=0 THEN 'Inglés' ELSE 'Español' END,
       CASE WHEN n<=30 THEN DATE '2025-06-01' + (n*9)
            ELSE DATE '2026-05-01' + ((n-31)*5) END,
       (ARRAY['Editorial Aurora','Editorial Norte','Ediciones Sur','Letras Vivas','Páginas Doradas'])[1 + n%5],
       NULL, NULL
FROM generate_series(1,40) n;

INSERT INTO dim_item (item_id, tipo_item, sku, nombre, isbn, idioma,
                      fecha_lanzamiento, editorial, categoria_producto, marca)
SELECT 100+n, 'PRODUCTO_NO_EDITORIAL', 'SKU-'||lpad(n::TEXT,4,'0'),
       (ARRAY['Cuaderno','Plumas','Juego de mesa','Mochila','Agenda'])[1 + n%5]||' Demo '||n,
       NULL, NULL, NULL, NULL,
       (ARRAY['Papelería','Juegos','Regalos','Material escolar'])[1 + n%4],
       (ARRAY['MarcaA','MarcaB','MarcaC'])[1 + n%3]
FROM generate_series(1,20) n;

/* ---------- BRIDGES item-autor / item-género ---------- */
INSERT INTO bridge_item_autor (item_key, autor_key, factor_asignacion)
SELECT i.item_key, a.autor_key, 1.0
FROM dim_item i JOIN dim_autor a ON a.autor_id = 1 + (i.item_id % 25)
WHERE i.tipo_item='LIBRO' AND i.item_id % 4 <> 0;

INSERT INTO bridge_item_autor (item_key, autor_key, factor_asignacion)
SELECT i.item_key, a.autor_key, 0.5            -- libros con 2 coautores
FROM dim_item i
JOIN dim_autor a ON a.autor_id IN (1 + (i.item_id % 25), 1 + ((i.item_id+7) % 25))
WHERE i.tipo_item='LIBRO' AND i.item_id % 4 = 0;

INSERT INTO bridge_item_genero (item_key, genero_key, factor_asignacion)
SELECT i.item_key, g.genero_key, 1.0
FROM dim_item i JOIN dim_genero g ON g.genero_id = 1 + (i.item_id % 8)
WHERE i.tipo_item='LIBRO' AND i.item_id % 3 <> 0;

INSERT INTO bridge_item_genero (item_key, genero_key, factor_asignacion)
SELECT i.item_key, g.genero_key, 0.5           -- libros con 2 géneros
FROM dim_item i
JOIN dim_genero g ON g.genero_id IN (1 + (i.item_id % 8), 1 + ((i.item_id+3) % 8))
WHERE i.tipo_item='LIBRO' AND i.item_id % 3 = 0;

/* ---------- TEMPORADAS, PROMOCIONES, EVENTOS ---------- */
INSERT INTO dim_temporada (temporada_id, nombre_temporada, fecha_inicio, fecha_fin) VALUES
 (1,'San Valentín','2026-02-07','2026-02-14'),
 (2,'Día del Niño y del Libro','2026-04-20','2026-04-30'),
 (3,'Día de las Madres','2026-05-03','2026-05-10');

INSERT INTO dim_promocion (promocion_id, nombre, tipo_promocion, descripcion, fecha_inicio, fecha_fin) VALUES
 (1,'Febrero lector','PORCENTAJE','10% en libros seleccionados','2026-02-01','2026-02-28'),
 (2,'Mes del libro','PORCENTAJE','Descuento por Día del Libro','2026-04-15','2026-04-30'),
 (3,'Regreso a lo básico','MONTO_FIJO','Descuento en papelería','2026-05-15','2026-06-15');

INSERT INTO dim_evento (evento_id, tipo_evento, tema) VALUES
 (1,'FIRMA_AUTOR','Firma de Autor Ficticio 3'),
 (2,'LANZAMIENTO','Lanzamiento de temporada'),
 (3,'NOCTURNA','Noche de lectura');

/* ---------- FACT_VENTAS ----------
   1,300 ventas con 1 a 3 productos distintos cada una (~2,600 filas).
   Grano: un item por venta. UNIQUE(venta_id,item_key) se respeta
   porque los items de cada venta salen de un solo ORDER BY random()
   LIMIT k sin repetir.
   Precio y costo son funciones deterministas del item_id. */
WITH ventas AS (
    SELECT v AS venta_id,
           DATE '2026-01-01' + (random()*180)::INT AS fecha,
           CASE WHEN random() < 0.12 THEN -1 ELSE 1 + (random()*59)::INT END AS cliente_id,
           1 + (random()*5)::INT AS sucursal_id,
           1 + (random()*2)::INT AS canal_id,
           1 + (random()*2)::INT AS k
    FROM generate_series(1,1300) v
)
INSERT INTO fact_ventas (venta_id, fecha_key, cliente_key, item_key, sucursal_key,
                         canal_key, temporada_key, cantidad, precio_unitario,
                         descuento, costo_unitario, es_preventa)
SELECT v.venta_id,
       to_char(v.fecha,'YYYYMMDD')::INT,
       c.cliente_key, i.item_key, s.sucursal_key, ca.canal_key,
       t.temporada_key,
       q.cant,
       q.precio,
       CASE WHEN random() < 0.30
            THEN ROUND((q.cant*q.precio*(0.05 + random()*0.15))::NUMERIC, 2) ELSE 0 END,
       ROUND(q.precio*(0.50 + (i.item_id % 5)*0.04), 2),
       (i.tipo_item='LIBRO' AND v.fecha < i.fecha_lanzamiento)
FROM ventas v
JOIN dim_cliente  c  ON c.cliente_id  = v.cliente_id
JOIN dim_sucursal s  ON s.sucursal_id = v.sucursal_id
JOIN dim_canal    ca ON ca.canal_id   = v.canal_id
CROSS JOIN LATERAL (
    SELECT i2.* FROM dim_item i2
    WHERE i2.fecha_lanzamiento IS NULL
       OR v.fecha >= i2.fecha_lanzamiento - 20      -- preventa hasta 20 días antes
    ORDER BY random()
    LIMIT v.k
) i
CROSS JOIN LATERAL (
    SELECT (1 + (random()*4)::INT)::NUMERIC AS cant,
           (80 + (i.item_id*37) % 420)::NUMERIC AS precio
) q
LEFT JOIN dim_temporada t ON v.fecha BETWEEN t.fecha_inicio AND t.fecha_fin;

/* ---------- BRIDGE VENTA-PROMOCIÓN (solo ventas con descuento en rango) ---------- */
INSERT INTO bridge_venta_promocion (fact_venta_id, promocion_key, descuento_atribuido)
SELECT f.fact_venta_id, p.promocion_key, f.descuento
FROM fact_ventas f
JOIN dim_fecha d ON d.fecha_key = f.fecha_key
JOIN dim_promocion p ON d.fecha BETWEEN p.fecha_inicio AND p.fecha_fin
WHERE f.descuento > 0;

/* ---------- FACT_EVENTOS + BRIDGE ---------- */
INSERT INTO fact_eventos (evento_key, fecha_key, sucursal_key, asistentes_registrados, costo_evento)
SELECT e.evento_key, to_char(DATE '2026-03-14' + ((e.evento_id-1)*30)::INT, 'YYYYMMDD')::INT, s.sucursal_key, 80 + e.evento_id*35, 3000 + e.evento_id*1500
FROM dim_evento e JOIN dim_sucursal s ON s.sucursal_id = 1 + e.evento_id;

INSERT INTO bridge_venta_evento (fact_venta_id, fact_evento_id, tipo_relacion)
SELECT f.fact_venta_id, fe.fact_evento_id, 'ASOCIADA_TEMPORAL'
FROM fact_eventos fe
JOIN fact_ventas f ON f.fecha_key = fe.fecha_key AND f.sucursal_key = fe.sucursal_key;

/* ---------- FACT_DEVOLUCIONES (~4% de las líneas vendidas) ---------- */
INSERT INTO fact_devoluciones (devolucion_id, venta_id, fecha_key, item_key, sucursal_key,
                               motivo_devolucion, importe_devuelto, cantidad_devuelta)
SELECT ROW_NUMBER() OVER (ORDER BY f.fact_venta_id),
       f.venta_id,
       to_char(d.fecha + (1 + (random()*14)::INT), 'YYYYMMDD')::INT,
       f.item_key, f.sucursal_key,
       (ARRAY['Producto dañado','Error de pedido','Ya no lo necesita','Edición equivocada'])[1 + (random()*3)::INT],
       0, 1
FROM fact_ventas f JOIN dim_fecha d ON d.fecha_key = f.fecha_key
WHERE random() < 0.04;

-- importe proporcional al precio neto de la línea (1 unidad devuelta)
UPDATE fact_devoluciones dv
SET importe_devuelto = ROUND(f.venta_neta / f.cantidad, 2)
FROM fact_ventas f
WHERE f.venta_id = dv.venta_id AND f.item_key = dv.item_key;

ANALYZE;
