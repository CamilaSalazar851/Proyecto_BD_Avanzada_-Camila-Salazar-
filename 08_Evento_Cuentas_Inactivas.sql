-- =====================================================================
-- 08_Evento_Cuentas_Inactivas.sql
-- Evento programado: Mantenimiento de Cuentas Inactivas
--
-- Politica de retencion: se desactivan automaticamente las cuentas de
-- clientes que no han comprado nada en los ultimos dos anios.
-- Se ejecuta despues de 07_Procedimientos_Almacenados.sql.
-- =====================================================================
USE ecommerce_db;

-- ---------------------------------------------------------------------
-- 0. Activar el planificador de eventos
-- Sin esto los eventos existen pero MySQL nunca los ejecuta.
-- SET GLOBAL dura hasta que se reinicie el servidor; para dejarlo fijo
-- agrega  event_scheduler=ON  en [mysqld] de my.ini / my.cnf.
-- ---------------------------------------------------------------------
SET GLOBAL event_scheduler = ON;
SHOW VARIABLES LIKE 'event_scheduler';   -- debe mostrar ON

-- ---------------------------------------------------------------------
-- 1. Nuevos campos en la tabla clientes
-- Tu 01_Esquema_y_Datos.sql ya crea estas dos columnas, y MySQL no
-- tiene "ADD COLUMN IF NOT EXISTS". Por eso cada ALTER TABLE se ejecuta
-- solo si la columna todavia no existe: asi el script funciona tanto
-- sobre tu base actual como sobre una tabla que no las tenga.
-- ---------------------------------------------------------------------

-- Fecha de la ultima compra del cliente. NULL = nunca ha comprado.
SET @existe = (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'clientes'
                  AND COLUMN_NAME = 'fecha_ultima_compra');
SET @sql = IF(@existe = 0,
              'ALTER TABLE clientes ADD COLUMN fecha_ultima_compra DATE NULL',
              'SELECT ''fecha_ultima_compra ya existe'' AS aviso');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Cuenta activa: TRUE (1) = activa, FALSE (0) = desactivada.
SET @existe = (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'clientes'
                  AND COLUMN_NAME = 'activo');
SET @sql = IF(@existe = 0,
              'ALTER TABLE clientes ADD COLUMN activo BOOLEAN NOT NULL DEFAULT TRUE',
              'SELECT ''activo ya existe'' AS aviso');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ---------------------------------------------------------------------
-- 2. Carga inicial de fecha_ultima_compra
-- Los clientes que ya tienen ventas necesitan su fecha calculada una
-- sola vez; de ahi en adelante la mantiene el trigger. Las ventas
-- canceladas no cuentan como compra.
-- ---------------------------------------------------------------------
UPDATE clientes c
SET c.fecha_ultima_compra = (
    SELECT MAX(DATE(v.fecha_venta))
    FROM ventas v
    WHERE v.id_cliente = c.id_cliente
      AND v.estado <> 'Cancelado'
);

-- ---------------------------------------------------------------------
-- 3. Trigger: mantener actualizada fecha_ultima_compra
-- Cada vez que se registra una venta (que no este cancelada), guarda su
-- fecha en la ficha del cliente. GREATEST evita que una venta con fecha
-- antigua haga retroceder una fecha ya guardada.
-- Si el cliente estaba desactivado, vuelve a quedar activo: quien
-- compra de nuevo deja de ser inactivo.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_actualizar_ultima_compra;

DELIMITER $$

CREATE TRIGGER trg_actualizar_ultima_compra
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado <> 'Cancelado' THEN
        UPDATE clientes
           SET fecha_ultima_compra = GREATEST(
                   COALESCE(fecha_ultima_compra, DATE(NEW.fecha_venta)),
                   DATE(NEW.fecha_venta)
               ),
               activo = TRUE
         WHERE id_cliente = NEW.id_cliente;
    END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- 4. Evento: evt_desactivar_cuentas_inactivas
-- Corre una vez al mes y pone activo = FALSE a los clientes activos que:
--   a) compraron por ultima vez hace mas de dos anios, o
--   b) nunca han comprado y se registraron hace mas de dos anios
--      (la fecha de registro evita desactivar a clientes recien creados).
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_desactivar_cuentas_inactivas;

DELIMITER $$

CREATE EVENT evt_desactivar_cuentas_inactivas
ON SCHEDULE EVERY 1 MONTH
STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 MONTH + INTERVAL 1 HOUR)
COMMENT 'Desactiva clientes sin compras en los ultimos 2 anios'
DO
BEGIN
    UPDATE clientes
       SET activo = FALSE
     WHERE activo = TRUE
       AND (
             fecha_ultima_compra < DATE_SUB(CURDATE(), INTERVAL 2 YEAR)
          OR (fecha_ultima_compra IS NULL
              AND fecha_registro < DATE_SUB(CURDATE(), INTERVAL 2 YEAR))
       );
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- 5. Comprobaciones opcionales
-- ---------------------------------------------------------------------
-- SHOW EVENTS WHERE Name = 'evt_desactivar_cuentas_inactivas';
-- SELECT id_cliente, nombre, fecha_ultima_compra, activo FROM clientes;
-- Para probar sin esperar un mes, ejecuta a mano el UPDATE del evento.
