-- =====================================================================
-- 01_Esquema_y_Datos.sql
-- Proyecto de Base de Datos para un E-commerce
-- Motor objetivo: MySQL 8.0+
-- Contenido: Definición completa del esquema (CREATE TABLE) y carga
--            de datos de ejemplo (INSERT INTO).
-- =====================================================================

CREATE DATABASE IF NOT EXISTS ecommerce_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ecommerce_db;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- Limpieza (permite re-ejecutar el script de forma idempotente)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS log_intentos_login;
DROP TABLE IF EXISTS log_actividad_sospechosa;
DROP TABLE IF EXISTS log_tamano_bd;
DROP TABLE IF EXISTS kpis_mensuales;
DROP TABLE IF EXISTS resumen_ventas_diarias;
DROP TABLE IF EXISTS reporte_ventas_semanales;
DROP TABLE IF EXISTS reporte_rendimiento_proveedores;
DROP TABLE IF EXISTS log_permisos;
DROP TABLE IF EXISTS detalle_ventas_archivado;
DROP TABLE IF EXISTS ventas_archivadas;
DROP TABLE IF EXISTS alertas_stock;
DROP TABLE IF EXISTS historial_estados_pedido;
DROP TABLE IF EXISTS log_clientes_nuevos;
DROP TABLE IF EXISTS log_cambios_precio;
DROP TABLE IF EXISTS resenas_productos;
DROP TABLE IF EXISTS promociones;
DROP TABLE IF EXISTS vistas_producto;
DROP TABLE IF EXISTS carrito_items;
DROP TABLE IF EXISTS carritos;
DROP TABLE IF EXISTS detalle_ventas;
DROP TABLE IF EXISTS ventas;
DROP TABLE IF EXISTS clientes;
DROP TABLE IF EXISTS productos;
DROP TABLE IF EXISTS proveedores;
DROP TABLE IF EXISTS categorias;
DROP TABLE IF EXISTS sucursales;

-- =====================================================================
-- ENTIDADES PRINCIPALES
-- =====================================================================

-- ---------------------------------------------------------------------
-- Sucursales (soporte para segmentación por sucursal, req. de seguridad 19)
-- ---------------------------------------------------------------------
CREATE TABLE sucursales (
    id_sucursal    INT AUTO_INCREMENT PRIMARY KEY,
    nombre         VARCHAR(100) NOT NULL,
    ciudad         VARCHAR(100) NOT NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Categorías
-- ---------------------------------------------------------------------
CREATE TABLE categorias (
    id_categoria     INT AUTO_INCREMENT PRIMARY KEY,
    nombre           VARCHAR(100) NOT NULL UNIQUE,
    descripcion      TEXT,
    total_productos  INT NOT NULL DEFAULT 0   -- mantenido por trigger
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Proveedores
-- ---------------------------------------------------------------------
CREATE TABLE proveedores (
    id_proveedor       INT AUTO_INCREMENT PRIMARY KEY,
    nombre             VARCHAR(150) NOT NULL,
    email_contacto     VARCHAR(150) UNIQUE,
    telefono_contacto  VARCHAR(30)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Productos
-- ---------------------------------------------------------------------
CREATE TABLE productos (
    id_producto         INT AUTO_INCREMENT PRIMARY KEY,
    nombre              VARCHAR(200) NOT NULL UNIQUE,
    descripcion         TEXT,
    precio              DECIMAL(10,2) NOT NULL,
    costo               DECIMAL(10,2) NOT NULL,
    stock               INT NOT NULL DEFAULT 0,
    stock_minimo        INT NOT NULL DEFAULT 5,
    sku                 VARCHAR(50) NOT NULL UNIQUE,
    peso_kg             DECIMAL(6,2) NOT NULL DEFAULT 0.50,
    fecha_creacion      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    veces_visto         INT NOT NULL DEFAULT 0,
    eliminado_en        TIMESTAMP NULL DEFAULT NULL,   -- soft delete
    id_categoria        INT,
    id_proveedor        INT,
    CONSTRAINT ck_producto_precio   CHECK (precio > 0),
    CONSTRAINT ck_producto_costo    CHECK (costo >= 0),
    CONSTRAINT ck_producto_stock    CHECK (stock >= 0),
    CONSTRAINT fk_producto_categoria  FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_producto_proveedor  FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_productos_categoria ON productos(id_categoria);
CREATE INDEX idx_productos_proveedor ON productos(id_proveedor);
CREATE INDEX idx_productos_activo    ON productos(activo);

-- ---------------------------------------------------------------------
-- Clientes
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente          INT AUTO_INCREMENT PRIMARY KEY,
    nombre              VARCHAR(100) NOT NULL,
    apellido            VARCHAR(100) NOT NULL,
    email               VARCHAR(150) NOT NULL UNIQUE,
    contrasena_hash     VARCHAR(255) NOT NULL,
    direccion_envio     VARCHAR(255),
    ciudad              VARCHAR(100),
    fecha_nacimiento    DATE,
    fecha_registro      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_gastado       DECIMAL(12,2) NOT NULL DEFAULT 0,
    nivel_lealtad       VARCHAR(20) NOT NULL DEFAULT 'Bronce',
    fecha_ultima_compra DATE NULL,
    id_sucursal         INT,
    referido_por        INT NULL,
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    eliminado_en        TIMESTAMP NULL DEFAULT NULL,   -- soft delete / anonimización
    CONSTRAINT fk_cliente_sucursal FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_cliente_referido FOREIGN KEY (referido_por) REFERENCES clientes(id_cliente)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_clientes_sucursal ON clientes(id_sucursal);

-- ---------------------------------------------------------------------
-- Ventas (encabezado de la orden)
-- ---------------------------------------------------------------------
CREATE TABLE ventas (
    id_venta      INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente    INT NOT NULL,
    id_sucursal   INT,
    fecha_venta   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado        ENUM('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado')
                  NOT NULL DEFAULT 'Pendiente de Pago',
    total         DECIMAL(12,2) NOT NULL DEFAULT 0,
    eliminado_en  TIMESTAMP NULL DEFAULT NULL,
    CONSTRAINT fk_venta_cliente  FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_venta_sucursal FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_ventas_cliente ON ventas(id_cliente);
CREATE INDEX idx_ventas_fecha   ON ventas(fecha_venta);
CREATE INDEX idx_ventas_estado  ON ventas(estado);

-- ---------------------------------------------------------------------
-- Detalle de Ventas (líneas de la orden)
-- ---------------------------------------------------------------------
CREATE TABLE detalle_ventas (
    id_detalle                 INT AUTO_INCREMENT PRIMARY KEY,
    id_venta                   INT NOT NULL,
    id_producto                INT NOT NULL,
    cantidad                   INT NOT NULL,
    precio_unitario_congelado  DECIMAL(10,2) NOT NULL,
    CONSTRAINT ck_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT fk_detalle_venta    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_detalle_venta    ON detalle_ventas(id_venta);
CREATE INDEX idx_detalle_producto ON detalle_ventas(id_producto);

-- =====================================================================
-- TABLAS DE SOPORTE (requeridas por consultas, triggers, eventos y SPs)
-- =====================================================================

CREATE TABLE carritos (
    id_carrito           INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente           INT NOT NULL,
    fecha_creacion       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado               ENUM('Activo','Abandonado','Convertido') NOT NULL DEFAULT 'Activo',
    CONSTRAINT fk_carrito_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE carrito_items (
    id_item         INT AUTO_INCREMENT PRIMARY KEY,
    id_carrito      INT NOT NULL,
    id_producto     INT NOT NULL,
    cantidad        INT NOT NULL DEFAULT 1,
    fecha_agregado  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_item_carrito  FOREIGN KEY (id_carrito) REFERENCES carritos(id_carrito)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_item_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE vistas_producto (
    id_vista     INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    id_cliente   INT NULL,
    fecha_vista  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_vista_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_vista_cliente  FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE promociones (
    id_promocion          INT AUTO_INCREMENT PRIMARY KEY,
    id_producto           INT NOT NULL,
    porcentaje_descuento  DECIMAL(5,2) NOT NULL,
    fecha_inicio          DATE NOT NULL,
    fecha_fin             DATE NOT NULL,
    activa                BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_promocion_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE resenas_productos (
    id_resena     INT AUTO_INCREMENT PRIMARY KEY,
    id_producto   INT NOT NULL,
    id_cliente    INT NOT NULL,
    calificacion  TINYINT NOT NULL,
    comentario    TEXT,
    fecha_resena  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_resena_calificacion CHECK (calificacion BETWEEN 1 AND 5),
    CONSTRAINT fk_resena_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_resena_cliente  FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---- Auditoría / logs ----

CREATE TABLE log_cambios_precio (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    id_producto     INT NOT NULL,
    precio_anterior DECIMAL(10,2) NOT NULL,
    precio_nuevo    DECIMAL(10,2) NOT NULL,
    fecha_cambio    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_bd      VARCHAR(100) NOT NULL DEFAULT (CURRENT_USER())
) ENGINE=InnoDB;

CREATE TABLE log_clientes_nuevos (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente    INT NOT NULL,
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE historial_estados_pedido (
    id_historial     INT AUTO_INCREMENT PRIMARY KEY,
    id_venta         INT NOT NULL,
    estado_anterior  VARCHAR(30),
    estado_nuevo     VARCHAR(30) NOT NULL,
    fecha_cambio     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE alertas_stock (
    id_alerta     INT AUTO_INCREMENT PRIMARY KEY,
    id_producto   INT NOT NULL,
    stock_actual  INT NOT NULL,
    fecha_alerta  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atendida      BOOLEAN NOT NULL DEFAULT FALSE
) ENGINE=InnoDB;

CREATE TABLE ventas_archivadas (
    id_venta      INT NOT NULL PRIMARY KEY,
    id_cliente    INT NOT NULL,
    id_sucursal   INT,
    fecha_venta   TIMESTAMP NOT NULL,
    estado        VARCHAR(30) NOT NULL,
    total         DECIMAL(12,2) NOT NULL,
    fecha_archivo TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE detalle_ventas_archivado (
    id_detalle                 INT NOT NULL,
    id_venta                   INT NOT NULL,
    id_producto                INT NOT NULL,
    cantidad                   INT NOT NULL,
    precio_unitario_congelado  DECIMAL(10,2) NOT NULL,
    fecha_archivo               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_detalle)
) ENGINE=InnoDB;

CREATE TABLE log_permisos (
    id_log            INT AUTO_INCREMENT PRIMARY KEY,
    usuario_afectado  VARCHAR(100) NOT NULL,
    accion            VARCHAR(100) NOT NULL,
    detalle           TEXT,
    ejecutado_por     VARCHAR(100) NOT NULL DEFAULT (CURRENT_USER()),
    fecha_cambio      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE log_intentos_login (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    usuario       VARCHAR(100) NOT NULL,
    exitoso       BOOLEAN NOT NULL,
    ip_origen     VARCHAR(45),
    fecha_intento TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE log_actividad_sospechosa (
    id_log           INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente       INT NULL,
    descripcion      TEXT NOT NULL,
    fecha_deteccion  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE log_tamano_bd (
    id_log     INT AUTO_INCREMENT PRIMARY KEY,
    fecha      DATE NOT NULL,
    tamano_mb  DECIMAL(12,2) NOT NULL
) ENGINE=InnoDB;

-- ---- Tablas de reporte / agregación (usadas por eventos) ----

CREATE TABLE reporte_ventas_semanales (
    id_reporte       INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio    DATE NOT NULL,
    semana_fin       DATE NOT NULL,
    total_ventas     DECIMAL(14,2) NOT NULL,
    numero_ordenes   INT NOT NULL,
    fecha_generacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE resumen_ventas_diarias (
    id_resumen       INT AUTO_INCREMENT PRIMARY KEY,
    fecha            DATE NOT NULL UNIQUE,
    total_ventas     DECIMAL(14,2) NOT NULL,
    numero_ordenes   INT NOT NULL,
    ticket_promedio  DECIMAL(12,2) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE kpis_mensuales (
    id_kpi             INT AUTO_INCREMENT PRIMARY KEY,
    mes                TINYINT NOT NULL,
    anio               SMALLINT NOT NULL,
    ingresos_totales   DECIMAL(14,2) NOT NULL,
    nuevos_clientes    INT NOT NULL,
    ticket_promedio    DECIMAL(12,2) NOT NULL,
    productos_vendidos INT NOT NULL,
    fecha_calculo      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_kpi_periodo (mes, anio)
) ENGINE=InnoDB;

CREATE TABLE reporte_rendimiento_proveedores (
    id_reporte         INT AUTO_INCREMENT PRIMARY KEY,
    id_proveedor       INT NOT NULL,
    mes                TINYINT NOT NULL,
    anio               SMALLINT NOT NULL,
    unidades_vendidas  INT NOT NULL,
    ingresos_generados DECIMAL(14,2) NOT NULL,
    fecha_generacion   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

SET FOREIGN_KEY_CHECKS = 1;

-- =====================================================================
-- DATOS DE EJEMPLO
-- =====================================================================

INSERT INTO sucursales (nombre, ciudad) VALUES
('Sucursal Centro', 'Bogotá'),
('Sucursal Norte', 'Medellín'),
('Sucursal Sur', 'Cali');

INSERT INTO categorias (nombre, descripcion) VALUES
('Electrónica', 'Dispositivos y gadgets electrónicos'),
('Ropa', 'Prendas de vestir para todas las edades'),
('Hogar', 'Artículos para el hogar y decoración'),
('Deportes', 'Equipamiento y ropa deportiva'),
('Libros', 'Libros físicos de diversos géneros');

INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
('TechImport S.A.S', 'ventas@techimport.com', '3001234567'),
('Textiles del Valle', 'contacto@textilesvalle.com', '3007654321'),
('Hogar y Deco Ltda', 'info@hogarydeco.com', '3009876543'),
('Deportes Andinos', 'contacto@deportesandinos.com', '3005551234'),
('Editorial Horizonte', 'pedidos@editorialhorizonte.com', '3002223344');

INSERT INTO productos (nombre, descripcion, precio, costo, stock, stock_minimo, sku, peso_kg, id_categoria, id_proveedor) VALUES
('Audífonos Bluetooth X200', 'Audífonos inalámbricos con cancelación de ruido', 189000, 95000, 40, 10, 'ELE-001', 0.30, 1, 1),
('Smartwatch Fit3', 'Reloj inteligente con monitor de ritmo cardiaco', 349000, 180000, 25, 8, 'ELE-002', 0.15, 1, 1),
('Cargador Rápido USB-C 65W', 'Cargador de carga rápida', 79000, 32000, 100, 20, 'ELE-003', 0.20, 1, 1),
('Camiseta Algodón Premium', 'Camiseta 100% algodón, varios colores', 59000, 22000, 150, 30, 'ROP-001', 0.25, 2, 2),
('Jean Slim Fit', 'Jean corte slim para hombre', 129000, 55000, 80, 15, 'ROP-002', 0.60, 2, 2),
('Chaqueta Impermeable', 'Chaqueta resistente al agua', 219000, 98000, 35, 10, 'ROP-003', 0.80, 2, 2),
('Juego de Sábanas Queen', 'Sábanas de microfibra 4 piezas', 149000, 60000, 45, 10, 'HOG-001', 1.20, 3, 3),
('Lámpara de Escritorio LED', 'Lámpara regulable con puerto USB', 89000, 35000, 60, 15, 'HOG-002', 0.90, 3, 3),
('Set de Ollas Antiadherentes', 'Set de 5 piezas', 259000, 120000, 20, 5, 'HOG-003', 3.50, 3, 3),
('Balón de Fútbol Profesional', 'Balón tamaño oficial FIFA', 99000, 40000, 70, 15, 'DEP-001', 0.43, 4, 4),
('Mancuernas Ajustables 20kg', 'Par de mancuernas ajustables', 289000, 140000, 15, 5, 'DEP-002', 20.00, 4, 4),
('Colchoneta de Yoga', 'Colchoneta antideslizante 6mm', 65000, 25000, 90, 20, 'DEP-003', 1.00, 4, 4),
('Cien Años de Soledad', 'Novela de Gabriel García Márquez', 45000, 18000, 3, 10, 'LIB-001', 0.40, 5, 5),
('El Principito', 'Clásico de Antoine de Saint-Exupéry', 32000, 12000, 2, 10, 'LIB-002', 0.20, 5, 5),
('Atlas Mundial Ilustrado', 'Atlas geográfico actualizado', 89000, 38000, 25, 8, 'LIB-003', 1.10, 5, 5);

INSERT INTO clientes (nombre, apellido, email, contrasena_hash, direccion_envio, ciudad, fecha_nacimiento, fecha_registro, id_sucursal, referido_por) VALUES
('Laura', 'Gómez', 'laura.gomez@correo.com', SHA2('ClaveSegura1!',256), 'Calle 10 # 5-20', 'Bogotá', '1992-03-14', '2024-01-10 09:15:00', 1, NULL),
('Carlos', 'Martínez', 'carlos.martinez@correo.com', SHA2('ClaveSegura2!',256), 'Carrera 45 # 12-30', 'Medellín', '1988-07-22', '2024-01-15 14:20:00', 2, NULL),
('Ana', 'Rodríguez', 'ana.rodriguez@correo.com', SHA2('ClaveSegura3!',256), 'Avenida Siempre Viva 742', 'Cali', '1995-11-02', '2024-02-01 10:00:00', 3, 1),
('Diego', 'Fernández', 'diego.fernandez@correo.com', SHA2('ClaveSegura4!',256), 'Calle 80 # 20-15', 'Bogotá', '1990-05-30', '2024-02-20 16:45:00', 1, NULL),
('María', 'López', 'maria.lopez@correo.com', SHA2('ClaveSegura5!',256), 'Carrera 7 # 45-10', 'Bogotá', '1998-09-18', '2024-03-05 11:30:00', 1, 1),
('Andrés', 'Torres', 'andres.torres@correo.com', SHA2('ClaveSegura6!',256), 'Calle 33 # 8-40', 'Medellín', '1985-12-25', '2024-03-18 08:50:00', 2, NULL),
('Valentina', 'Ramírez', 'valentina.ramirez@correo.com', SHA2('ClaveSegura7!',256), 'Carrera 15 # 100-05', 'Cali', '2000-02-09', '2024-04-02 13:10:00', 3, NULL),
('Santiago', 'Cruz', 'santiago.cruz@correo.com', SHA2('ClaveSegura8!',256), 'Calle 50 # 30-22', 'Bogotá', '1993-06-11', '2024-04-25 17:05:00', 1, 4);

INSERT INTO ventas (id_cliente, id_sucursal, fecha_venta, estado, total) VALUES
(1, 1, '2024-05-02 10:15:00', 'Entregado', 268000),
(2, 2, '2024-05-04 15:30:00', 'Entregado', 349000),
(3, 3, '2024-05-10 09:00:00', 'Enviado', 178000),
(1, 1, '2024-06-01 11:45:00', 'Entregado', 89000),
(4, 1, '2024-06-15 14:20:00', 'Procesando', 348000),
(5, 1, '2024-07-03 16:00:00', 'Entregado', 129000),
(2, 2, '2024-07-20 10:30:00', 'Cancelado', 259000),
(6, 2, '2024-08-05 12:10:00', 'Entregado', 164000),
(1, 1, '2024-08-22 09:40:00', 'Entregado', 99000),
(7, 3, '2024-09-01 13:25:00', 'Pendiente de Pago', 65000);

INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
(1, 1, 1, 189000), (1, 3, 1, 79000),
(2, 2, 1, 349000),
(3, 4, 2, 59000), (3, 10, 1, 60000),
(4, 8, 1, 89000),
(5, 2, 1, 349000-1000),
(6, 5, 1, 129000),
(7, 9, 1, 259000),
(8, 6, 1, 164000),
(9, 10, 1, 99000),
(10, 12, 1, 65000);

INSERT INTO carritos (id_cliente, estado, fecha_creacion, fecha_actualizacion) VALUES
(4, 'Abandonado', '2024-09-10 10:00:00', '2024-09-10 10:20:00'),
(6, 'Abandonado', '2024-09-15 18:00:00', '2024-09-15 18:05:00'),
(8, 'Activo', '2024-09-25 09:00:00', '2024-09-25 09:00:00');

INSERT INTO carrito_items (id_carrito, id_producto, cantidad) VALUES
(1, 2, 1),
(2, 7, 2),
(3, 1, 1);

INSERT INTO vistas_producto (id_producto, id_cliente, fecha_vista) VALUES
(1, 1, '2024-05-01 09:00:00'), (1, 3, '2024-05-08 12:00:00'), (1, NULL, '2024-05-09 12:00:00'),
(2, 2, '2024-05-03 14:00:00'), (2, 5, '2024-06-10 10:00:00'),
(13, 4, '2024-07-01 09:30:00'), (14, 4, '2024-07-01 09:35:00');

INSERT INTO promociones (id_producto, porcentaje_descuento, fecha_inicio, fecha_fin, activa) VALUES
(9, 15.00, '2024-07-10', '2024-07-25', FALSE),
(6, 10.00, '2024-09-01', '2024-09-30', TRUE);

INSERT INTO resenas_productos (id_producto, id_cliente, calificacion, comentario) VALUES
(1, 1, 5, 'Excelente calidad de sonido.'),
(2, 2, 4, 'Muy buena batería, cumple lo prometido.'),
(4, 3, 5, 'Tela muy cómoda.');
