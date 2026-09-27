-- =====================================================================
-- 05_Triggers.sql
-- Tabla de auditoría de precios + 20 triggers de integridad y automatización
-- =====================================================================
USE ecommerce_db;

-- Tabla de auditoría de cambios de precio (ya definida en 01, se incluye
-- aquí también, de forma idempotente, para que este script sea autónomo)
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    id_producto     INT NOT NULL,
    precio_anterior DECIMAL(10,2) NOT NULL,
    precio_nuevo    DECIMAL(10,2) NOT NULL,
    fecha_cambio    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_bd      VARCHAR(100) NOT NULL DEFAULT (CURRENT_USER())
) ENGINE=InnoDB;

DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update;
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta;
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta;
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products;
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert;
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente;
DROP TRIGGER IF EXISTS trg_set_fecha_modificacion_producto;
DROP TRIGGER IF EXISTS trg_prevent_negative_stock;
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente;
DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_change;
DROP TRIGGER IF EXISTS trg_log_order_status_change;
DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less;
DROP TRIGGER IF EXISTS trg_send_stock_alert_on_low_stock;
DROP TRIGGER IF EXISTS trg_archive_deleted_venta;
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer;
DROP TRIGGER IF EXISTS trg_update_last_order_date_customer;
DROP TRIGGER IF EXISTS trg_prevent_self_referral;
DROP TRIGGER IF EXISTS trg_log_permission_changes;
DROP TRIGGER IF EXISTS trg_assign_default_category_on_null;
DROP TRIGGER IF EXISTS trg_update_producto_count_in_categoria;
DROP TRIGGER IF EXISTS trg_update_producto_count_in_categoria_del;

DELIMITER $$

-- 1. Guarda un log de cambios de precios
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.precio <> NEW.precio THEN
        INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo)
        VALUES (NEW.id_producto, OLD.precio, NEW.precio);
    END IF;
END$$

-- 2. Verifica el stock antes de registrar el detalle de una venta
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock_disponible INT;
    SELECT stock INTO v_stock_disponible FROM productos WHERE id_producto = NEW.id_producto;
    IF v_stock_disponible IS NULL OR v_stock_disponible < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Stock insuficiente para completar la venta de este producto.';
    END IF;
END$$

-- 3. Decrementa el stock después de registrar una línea de venta
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
       SET stock = stock - NEW.cantidad
     WHERE id_producto = NEW.id_producto;
END$$

-- 4. Impide eliminar una categoría si tiene productos asociados
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_num_productos INT;
    SELECT COUNT(*) INTO v_num_productos FROM productos WHERE id_categoria = OLD.id_categoria;
    IF v_num_productos > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar una categoría que tiene productos asociados.';
    END IF;
END$$

-- 5. Registra en auditoría cada vez que se crea un nuevo cliente
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO log_clientes_nuevos (id_cliente) VALUES (NEW.id_cliente);
END$$

-- 6. Actualiza total_gastado en clientes después de cada compra confirmada
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado <> OLD.estado AND NEW.estado IN ('Entregado','Enviado','Procesando') THEN
        UPDATE clientes
           SET total_gastado = (
                SELECT COALESCE(SUM(total), 0) FROM ventas
                 WHERE id_cliente = NEW.id_cliente AND estado <> 'Cancelado'
           )
         WHERE id_cliente = NEW.id_cliente;
    END IF;
END$$

-- 7. Actualiza automáticamente la fecha de última modificación de un producto
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = CURRENT_TIMESTAMP;
END$$

-- 8. Impide que el stock de un producto se actualice a un valor negativo
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El stock de un producto no puede ser negativo.';
    END IF;
END$$

-- 9. Convierte a mayúscula la primera letra de nombre y apellido al insertar un cliente
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre = CONCAT(UPPER(LEFT(NEW.nombre,1)), LOWER(SUBSTRING(NEW.nombre,2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido,1)), LOWER(SUBSTRING(NEW.apellido,2)));
END$$

-- 10. Recalcula el total de la venta si se modifica un detalle_venta
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_change
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
       SET total = (SELECT COALESCE(SUM(cantidad * precio_unitario_congelado),0)
                       FROM detalle_ventas WHERE id_venta = NEW.id_venta)
     WHERE id_venta = NEW.id_venta;
END$$

-- 11. Audita cada cambio de estado en un pedido
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado <> NEW.estado THEN
        INSERT INTO historial_estados_pedido (id_venta, estado_anterior, estado_nuevo)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado);
    END IF;
END$$

-- 12. Impide que el precio de un producto se establezca en cero o negativo
CREATE TRIGGER trg_prevent_price_zero_or_less
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El precio de un producto debe ser mayor que cero.';
    END IF;
END$$

-- 13. Inserta una alerta si el stock baja del umbral mínimo
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < NEW.stock_minimo AND (OLD.stock >= OLD.stock_minimo OR OLD.stock IS NULL) THEN
        INSERT INTO alertas_stock (id_producto, stock_actual)
        VALUES (NEW.id_producto, NEW.stock);
    END IF;
END$$

-- 14. Mueve una venta eliminada a una tabla de archivo en lugar de borrarla
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta, id_cliente, id_sucursal, fecha_venta, estado, total)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.id_sucursal, OLD.fecha_venta, OLD.estado, OLD.total);

    INSERT INTO detalle_ventas_archivado (id_detalle, id_venta, id_producto, cantidad, precio_unitario_congelado)
    SELECT id_detalle, id_venta, id_producto, cantidad, precio_unitario_congelado
      FROM detalle_ventas WHERE id_venta = OLD.id_venta;
END$$

-- 15. Valida el formato del email antes de insertar o actualizar un cliente
CREATE TRIGGER trg_validate_email_format_on_customer
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NOT fn_ValidarFormatoEmail(NEW.email) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El formato del correo electrónico no es válido.';
    END IF;
END$$

-- 16. Actualiza la fecha del último pedido en la tabla clientes
CREATE TRIGGER trg_update_last_order_date_customer
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
       SET fecha_ultima_compra = DATE(NEW.fecha_venta)
     WHERE id_cliente = NEW.id_cliente;
END$$

-- 17. Impide que un cliente se referencie a sí mismo en el programa de referidos
CREATE TRIGGER trg_prevent_self_referral
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NEW.referido_por IS NOT NULL AND NEW.referido_por = NEW.id_cliente THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Un cliente no puede referirse a sí mismo.';
    END IF;
END$$

-- 18. Audita los cambios en los permisos de los usuarios (roles de MySQL)
--     Nota: para capturar GRANT/REVOKE a nivel de servidor se requiere
--     habilitar el log de auditoría del servidor; este trigger cubre
--     los cambios administrados por la propia aplicación en log_permisos.
CREATE TRIGGER trg_log_permission_changes
BEFORE INSERT ON log_permisos
FOR EACH ROW
BEGIN
    SET NEW.fecha_cambio = CURRENT_TIMESTAMP;
END$$

-- 19. Asigna una categoría "General" si se inserta un producto sin categoría
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    DECLARE v_id_general INT;
    IF NEW.id_categoria IS NULL THEN
        SELECT id_categoria INTO v_id_general FROM categorias WHERE nombre = 'General' LIMIT 1;
        IF v_id_general IS NULL THEN
            INSERT INTO categorias (nombre, descripcion) VALUES ('General', 'Categoría por defecto');
            SET v_id_general = LAST_INSERT_ID();
        END IF;
        SET NEW.id_categoria = v_id_general;
    END IF;
END$$

-- 20. Mantiene un contador de productos por categoría (inserción y borrado)
CREATE TRIGGER trg_update_producto_count_in_categoria
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias SET total_productos = total_productos + 1 WHERE id_categoria = NEW.id_categoria;
END$$

CREATE TRIGGER trg_update_producto_count_in_categoria_del
AFTER DELETE ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias SET total_productos = total_productos - 1 WHERE id_categoria = OLD.id_categoria;
END$$

DELIMITER ;
