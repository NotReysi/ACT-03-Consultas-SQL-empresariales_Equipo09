USE dm_libromundo;

-- 1. Llenar Dimensión Fecha (Todo 2026)
SET cte_max_recursion_depth = 4000;
INSERT INTO dim_fecha (fecha_key, fecha, dia, nombre_dia, semana, mes, nombre_mes, trimestre, anio, es_fin_semana)
WITH RECURSIVE fechas AS (
    SELECT CAST('2026-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATE_ADD(d, INTERVAL 1 DAY) FROM fechas WHERE d < '2026-12-31'
)
SELECT 
    DATE_FORMAT(d, '%Y%m%d'), d, DAY(d),
    ELT(DAYOFWEEK(d), 'Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'),
    WEEK(d, 1), MONTH(d),
    ELT(MONTH(d), 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'),
    QUARTER(d), YEAR(d),
    IF(DAYOFWEEK(d) IN (1, 7), TRUE, FALSE)
FROM fechas;

-- 2. Sucursales y Canales
INSERT INTO dim_sucursal (sucursal_id, nombre, ciudad, region) VALUES
(1,'LibroMundo Monterrey Centro','Monterrey','Noreste'),
(2,'LibroMundo San Pedro','San Pedro Garza García','Noreste'),
(3,'LibroMundo CDMX Reforma','Ciudad de México','Centro'),
(4,'LibroMundo Puebla Angelópolis','Puebla','Centro'),
(5,'LibroMundo Guadalajara Andares','Guadalajara','Occidente'),
(6,'LibroMundo León Centro','León','Occidente');

INSERT INTO dim_canal (canal_id, nombre_canal) VALUES (1,'Tienda física'),(2,'E-commerce'),(3,'Venta institucional');

-- 3. Clientes (60 clientes)
INSERT INTO dim_cliente (cliente_id, nombre, tipo_cliente, segmento_cliente, ciudad, limite_credito)
WITH RECURSIVE nums AS ( SELECT 1 AS n UNION ALL SELECT n + 1 FROM nums WHERE n < 60 )
SELECT n, CONCAT('Cliente Demo ', n), 
       ELT((n%4)+1, 'ESCUELA', 'CONSUMIDOR', 'EMPRESA', 'CLUB_LECTURA'),
       IF(n%4 IN (0,2), 'INSTITUCIONAL', 'MINORISTA'),
       ELT((n%5)+1, 'Monterrey', 'Ciudad de México', 'Puebla', 'Guadalajara', 'León'),
       IF(n%4 IN (0,2), 50000 + (n%5)*10000, NULL)
FROM nums;

-- 4. Ítems (40 libros y 20 productos no editoriales)
INSERT INTO dim_item (item_id, tipo_item, sku, nombre, isbn, idioma, fecha_lanzamiento, editorial, categoria_producto, marca)
WITH RECURSIVE nums AS ( SELECT 1 AS n UNION ALL SELECT n + 1 FROM nums WHERE n < 60 )
SELECT n, 
       IF(n<=40, 'LIBRO', 'PRODUCTO_NO_EDITORIAL'), 
       IF(n<=40, NULL, CONCAT('SKU-', LPAD(n,4,'0'))),
       CONCAT(IF(n<=40, 'Libro Demo ', 'Producto Demo '), n),
       IF(n<=40, CONCAT('978-607-', LPAD(n,6,'0')), NULL),
       IF(n<=40, IF(n%10=0, 'Inglés', 'Español'), NULL),
       IF(n<=40, IF(n<=30, DATE_ADD('2025-06-01', INTERVAL n*9 DAY), DATE_ADD('2026-05-01', INTERVAL (n-31)*5 DAY)), NULL),
       IF(n<=40, ELT((n%5)+1, 'Editorial Aurora', 'Editorial Norte', 'Ediciones Sur', 'Letras Vivas', 'Páginas Doradas'), NULL),
       IF(n>40, ELT((n%4)+1, 'Papelería', 'Juegos', 'Regalos', 'Material escolar'), NULL),
       IF(n>40, ELT((n%3)+1, 'MarcaA', 'MarcaB', 'MarcaC'), NULL)
FROM nums;

-- 5. Generar Hechos de Ventas (Uso de un Procedimiento para el ciclo en MySQL)
DELIMITER $$
CREATE PROCEDURE sp_generar_ventas()
BEGIN
    DECLARE v_contador INT DEFAULT 1;
    DECLARE v_fecha DATE;
    DECLARE v_item INT;
    DECLARE v_sucursal INT;
    
    WHILE v_contador <= 1300 DO
        SET v_fecha = DATE_ADD('2026-01-01', INTERVAL FLOOR(RAND() * 180) DAY);
        SET v_item = FLOOR(1 + RAND() * 60);
        SET v_sucursal = FLOOR(1 + RAND() * 6);
        
        INSERT IGNORE INTO fact_ventas (venta_id, fecha_key, cliente_key, item_key, sucursal_key, canal_key, cantidad, precio_unitario, descuento, costo_unitario, es_preventa)
        VALUES (
            v_contador, 
            DATE_FORMAT(v_fecha, '%Y%m%d'), 
            FLOOR(1 + RAND() * 60), 
            v_item, 
            v_sucursal, 
            FLOOR(1 + RAND() * 3), 
            FLOOR(1 + RAND() * 4), 
            80 + (v_item * 5), 
            IF(RAND() < 0.3, 15, 0), 
            40 + (v_item * 2), 
            FALSE
        );
        SET v_contador = v_contador + 1;
    END WHILE;
END$$
DELIMITER ;

CALL sp_generar_ventas();
DROP PROCEDURE sp_generar_ventas;

-- 6. Generar Devoluciones simuladas (basadas en ventas existentes)
INSERT INTO fact_devoluciones (devolucion_id, venta_id, fecha_key, item_key, sucursal_key, motivo_devolucion, importe_devuelto, cantidad_devuelta)
SELECT f.fact_venta_id, f.venta_id, 
       CAST(DATE_FORMAT(DATE_ADD(STR_TO_DATE(CAST(f.fecha_key AS CHAR), '%Y%m%d'), INTERVAL 5 DAY), '%Y%m%d') AS UNSIGNED), 
       f.item_key, f.sucursal_key, 'Error de pedido', f.venta_neta / f.cantidad, 1
FROM fact_ventas f
WHERE f.fact_venta_id % 25 = 0;