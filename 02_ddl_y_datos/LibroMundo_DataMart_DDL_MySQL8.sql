/* ================================================================
   DATA MART DE VENTAS - LIBROMUNDO
   Motor: MySQL 8.0.16+

   Objetivo:
   Crear el modelo dimensional para analizar:
   - Ventas
   - Margen
   - Preventas
   - Clientes
   - Productos / libros
   - Autores y géneros
   - Temporadas
   - Promociones
   - Eventos
   - Devoluciones

   GRANO PRINCIPAL:
   FactVentas:
   Una fila representa un ITEM vendido dentro de una transacción de venta.

   IMPORTANTE:
   Algunos atributos relacionados con eventos, promociones y cantidad
   devuelta son extensiones propuestas por el equipo para permitir
   análisis que la fuente original no soporta directamente.
================================================================ */

CREATE DATABASE IF NOT EXISTS dm_libromundo CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE dm_libromundo;

/* =========================
   DIMENSIÓN FECHA
========================= */
CREATE TABLE dim_fecha (
    fecha_key       INTEGER PRIMARY KEY,
    fecha           DATE NOT NULL UNIQUE,
    dia             SMALLINT NOT NULL CHECK (dia BETWEEN 1 AND 31),
    nombre_dia      VARCHAR(15) NOT NULL,
    semana          SMALLINT NOT NULL CHECK (semana BETWEEN 1 AND 53),
    mes             SMALLINT NOT NULL CHECK (mes BETWEEN 1 AND 12),
    nombre_mes      VARCHAR(15) NOT NULL,
    trimestre       SMALLINT NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
    anio            SMALLINT NOT NULL,
    es_fin_semana   BOOLEAN NOT NULL DEFAULT FALSE
);



/* =========================
   DIMENSIÓN CLIENTE
========================= */
CREATE TABLE dim_cliente (
    cliente_key        BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    cliente_id         BIGINT,
    nombre             VARCHAR(200),
    tipo_cliente       VARCHAR(50),
    segmento_cliente   VARCHAR(50),
    ciudad             VARCHAR(100),
    limite_credito     NUMERIC(14,2)
                       CHECK (limite_credito IS NULL OR limite_credito >= 0),
    UNIQUE (cliente_id)
);

/* =========================
   DIMENSIÓN SUCURSAL
========================= */
CREATE TABLE dim_sucursal (
    sucursal_key    BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    sucursal_id     BIGINT NOT NULL UNIQUE,
    nombre          VARCHAR(150) NOT NULL,
    ciudad          VARCHAR(100),
    region          VARCHAR(100)
);

/* =========================
   DIMENSIÓN CANAL
========================= */
CREATE TABLE dim_canal (
    canal_key       BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    canal_id        BIGINT NOT NULL UNIQUE,
    nombre_canal    VARCHAR(80) NOT NULL
);



/* =========================
   DIMENSIÓN ITEM
========================= */
CREATE TABLE dim_item (
    item_key                BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    item_id                 BIGINT NOT NULL UNIQUE,
    tipo_item               VARCHAR(30) NOT NULL
                            CHECK (tipo_item IN ('LIBRO','PRODUCTO_NO_EDITORIAL')),
    sku                     VARCHAR(100),
    nombre                  VARCHAR(250) NOT NULL,
    isbn                    VARCHAR(20),
    idioma                  VARCHAR(50),
    fecha_lanzamiento       DATE,
    editorial               VARCHAR(150),
    categoria_producto      VARCHAR(120),
    marca                   VARCHAR(120),
    CHECK (
        (tipo_item = 'LIBRO' AND isbn IS NOT NULL)
        OR
        (tipo_item = 'PRODUCTO_NO_EDITORIAL' AND sku IS NOT NULL)
    )
);

/* =========================
   DIMENSIÓN AUTOR
========================= */
CREATE TABLE dim_autor (
    autor_key       BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    autor_id        BIGINT NOT NULL UNIQUE,
    nombre_autor    VARCHAR(200) NOT NULL
);

/* =========================
   BRIDGE ITEM - AUTOR
========================= */
CREATE TABLE bridge_item_autor (
    item_key            BIGINT NOT NULL,
    autor_key           BIGINT NOT NULL,
    factor_asignacion   NUMERIC(9,6) NOT NULL
                        CHECK (factor_asignacion > 0 AND factor_asignacion <= 1),
    PRIMARY KEY (item_key, autor_key),
    FOREIGN KEY (item_key) REFERENCES dim_item(item_key),
    FOREIGN KEY (autor_key) REFERENCES dim_autor(autor_key)
);

/* =========================
   DIMENSIÓN GÉNERO
========================= */
CREATE TABLE dim_genero (
    genero_key       BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    genero_id        BIGINT NOT NULL UNIQUE,
    nombre_genero    VARCHAR(120) NOT NULL
);

/* =========================
   BRIDGE ITEM - GÉNERO
========================= */
CREATE TABLE bridge_item_genero (
    item_key            BIGINT NOT NULL,
    genero_key          BIGINT NOT NULL,
    factor_asignacion   NUMERIC(9,6) NOT NULL
                        CHECK (factor_asignacion > 0 AND factor_asignacion <= 1),
    PRIMARY KEY (item_key, genero_key),
    FOREIGN KEY (item_key) REFERENCES dim_item(item_key),
    FOREIGN KEY (genero_key) REFERENCES dim_genero(genero_key)
);

/* =========================
   DIMENSIÓN TEMPORADA
========================= */
CREATE TABLE dim_temporada (
    temporada_key      BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    temporada_id       BIGINT NOT NULL UNIQUE,
    nombre_temporada   VARCHAR(120) NOT NULL,
    fecha_inicio       DATE NOT NULL,
    fecha_fin          DATE NOT NULL,
    CHECK (fecha_fin >= fecha_inicio)
);

/* =========================
   DIMENSIÓN PROMOCIÓN
========================= */
CREATE TABLE dim_promocion (
    promocion_key      BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    promocion_id       BIGINT NOT NULL UNIQUE,
    nombre             VARCHAR(200) NOT NULL,
    tipo_promocion     VARCHAR(80),
    descripcion        TEXT,
    fecha_inicio       DATE NOT NULL,
    fecha_fin          DATE NOT NULL,
    CHECK (fecha_fin >= fecha_inicio)
);

/* =========================
   DIMENSIÓN EVENTO
========================= */
CREATE TABLE dim_evento (
    evento_key       BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    evento_id        BIGINT NOT NULL UNIQUE,
    tipo_evento      VARCHAR(100),
    tema             VARCHAR(250)
);

/* =========================
   FACT VENTAS
   Grano: un ITEM vendido dentro de una transacción.
========================= */
CREATE TABLE fact_ventas (
    fact_venta_id       BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    venta_id            BIGINT NOT NULL,
    fecha_key           INTEGER NOT NULL,
    cliente_key         BIGINT NOT NULL,
    item_key            BIGINT NOT NULL,
    sucursal_key        BIGINT NOT NULL,
    canal_key           BIGINT NOT NULL,
    temporada_key       BIGINT,
    cantidad            NUMERIC(14,3) NOT NULL CHECK (cantidad > 0),
    precio_unitario     NUMERIC(14,2) NOT NULL CHECK (precio_unitario >= 0),
    descuento           NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (descuento >= 0),
    costo_unitario      NUMERIC(14,2) NOT NULL CHECK (costo_unitario >= 0),

    venta_bruta NUMERIC(14,2)
        GENERATED ALWAYS AS (ROUND(cantidad * precio_unitario, 2)) STORED,

    venta_neta NUMERIC(14,2)
        GENERATED ALWAYS AS (
            ROUND((cantidad * precio_unitario) - descuento, 2)
        ) STORED,

    costo_total NUMERIC(14,2)
        GENERATED ALWAYS AS (ROUND(cantidad * costo_unitario, 2)) STORED,

    margen NUMERIC(14,2)
        GENERATED ALWAYS AS (
            ROUND(((cantidad * precio_unitario) - descuento)
                  - (cantidad * costo_unitario), 2)
        ) STORED,

    es_preventa         BOOLEAN NOT NULL DEFAULT FALSE,

    FOREIGN KEY (fecha_key) REFERENCES dim_fecha(fecha_key),
    FOREIGN KEY (cliente_key) REFERENCES dim_cliente(cliente_key),
    FOREIGN KEY (item_key) REFERENCES dim_item(item_key),
    FOREIGN KEY (sucursal_key) REFERENCES dim_sucursal(sucursal_key),
    FOREIGN KEY (canal_key) REFERENCES dim_canal(canal_key),
    FOREIGN KEY (temporada_key) REFERENCES dim_temporada(temporada_key),

    CONSTRAINT uq_fact_ventas_grano UNIQUE (venta_id, item_key),
    CHECK (descuento <= cantidad * precio_unitario)
);



/* =========================
   BRIDGE VENTA - PROMOCIÓN
   EXTENSIÓN PROPUESTA
========================= */
CREATE TABLE bridge_venta_promocion (
    fact_venta_id          BIGINT NOT NULL,
    promocion_key          BIGINT NOT NULL,
    descuento_atribuido    NUMERIC(14,2) NOT NULL DEFAULT 0
                           CHECK (descuento_atribuido >= 0),
    PRIMARY KEY (fact_venta_id, promocion_key),
    FOREIGN KEY (fact_venta_id) REFERENCES fact_ventas(fact_venta_id),
    FOREIGN KEY (promocion_key) REFERENCES dim_promocion(promocion_key)
);

/* =========================
   FACT EVENTOS
   Grano: un evento realizado en una sucursal y fecha.
========================= */
CREATE TABLE fact_eventos (
    fact_evento_id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    evento_key             BIGINT NOT NULL,
    fecha_key              INTEGER NOT NULL,
    sucursal_key           BIGINT NOT NULL,

    -- Extensiones propuestas para evaluar desempeño/ROI.
    asistentes_registrados INTEGER
                           CHECK (asistentes_registrados IS NULL
                                  OR asistentes_registrados >= 0),
    costo_evento           NUMERIC(14,2)
                           CHECK (costo_evento IS NULL OR costo_evento >= 0),

    FOREIGN KEY (evento_key) REFERENCES dim_evento(evento_key),
    FOREIGN KEY (fecha_key) REFERENCES dim_fecha(fecha_key),
    FOREIGN KEY (sucursal_key) REFERENCES dim_sucursal(sucursal_key),

    CONSTRAINT uq_fact_eventos_grano
        UNIQUE (evento_key, fecha_key, sucursal_key)
);

/* =========================
   BRIDGE VENTA - EVENTO
   EXTENSIÓN PROPUESTA
========================= */
CREATE TABLE bridge_venta_evento (
    fact_venta_id       BIGINT NOT NULL,
    fact_evento_id      BIGINT NOT NULL,
    tipo_relacion       VARCHAR(30) NOT NULL
                        CHECK (tipo_relacion IN ('DIRECTA','ASOCIADA_TEMPORAL')),
    PRIMARY KEY (fact_venta_id, fact_evento_id),
    FOREIGN KEY (fact_venta_id) REFERENCES fact_ventas(fact_venta_id),
    FOREIGN KEY (fact_evento_id) REFERENCES fact_eventos(fact_evento_id)
);

/* =========================
   FACT DEVOLUCIONES
   Grano: un registro de devolución de un ITEM asociado a una venta.
========================= */
CREATE TABLE fact_devoluciones (
    fact_devolucion_id    BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    devolucion_id         BIGINT NOT NULL UNIQUE,
    venta_id              BIGINT NOT NULL,
    fecha_key             INTEGER NOT NULL,
    item_key              BIGINT NOT NULL,
    sucursal_key          BIGINT,
    motivo_devolucion     VARCHAR(250) NOT NULL,
    importe_devuelto      NUMERIC(14,2) NOT NULL CHECK (importe_devuelto >= 0),

    -- Extensión propuesta: la fuente original no incluye cantidad devuelta.
    cantidad_devuelta     NUMERIC(14,3)
                          CHECK (cantidad_devuelta IS NULL
                                 OR cantidad_devuelta > 0),

    FOREIGN KEY (fecha_key) REFERENCES dim_fecha(fecha_key),
    FOREIGN KEY (item_key) REFERENCES dim_item(item_key),
    FOREIGN KEY (sucursal_key) REFERENCES dim_sucursal(sucursal_key)
);

/* =========================
   ÍNDICES ANALÍTICOS
========================= */
CREATE INDEX idx_fact_ventas_fecha       ON fact_ventas(fecha_key);
CREATE INDEX idx_fact_ventas_item        ON fact_ventas(item_key);
CREATE INDEX idx_fact_ventas_cliente     ON fact_ventas(cliente_key);
CREATE INDEX idx_fact_ventas_sucursal    ON fact_ventas(sucursal_key);
CREATE INDEX idx_fact_ventas_canal       ON fact_ventas(canal_key);
CREATE INDEX idx_fact_ventas_temporada   ON fact_ventas(temporada_key);
CREATE INDEX idx_fact_ventas_preventa    ON fact_ventas(es_preventa);
CREATE INDEX idx_fact_ventas_venta_id    ON fact_ventas(venta_id);

CREATE INDEX idx_bridge_item_autor_autor
    ON bridge_item_autor(autor_key);

CREATE INDEX idx_bridge_item_genero_genero
    ON bridge_item_genero(genero_key);

CREATE INDEX idx_bridge_venta_promocion_promocion
    ON bridge_venta_promocion(promocion_key);

CREATE INDEX idx_fact_eventos_fecha
    ON fact_eventos(fecha_key);

CREATE INDEX idx_fact_eventos_sucursal
    ON fact_eventos(sucursal_key);

CREATE INDEX idx_bridge_venta_evento_evento
    ON bridge_venta_evento(fact_evento_id);

CREATE INDEX idx_fact_devoluciones_fecha
    ON fact_devoluciones(fecha_key);

CREATE INDEX idx_fact_devoluciones_item
    ON fact_devoluciones(item_key);

CREATE INDEX idx_fact_devoluciones_sucursal
    ON fact_devoluciones(sucursal_key);

CREATE INDEX idx_fact_devoluciones_venta
    ON fact_devoluciones(venta_id);

/* =========================
   CLIENTE NO IDENTIFICADO
========================= */
INSERT INTO dim_cliente (
    cliente_id,
    nombre,
    tipo_cliente,
    segmento_cliente,
    ciudad,
    limite_credito
)
VALUES (
    -1,
    'Cliente no identificado',
    'NO_IDENTIFICADO',
    'NO_IDENTIFICADO',
    NULL,
    NULL
)
ON DUPLICATE KEY UPDATE cliente_id = cliente_id;

/* =========================
   FIN DEL DDL
========================= */
