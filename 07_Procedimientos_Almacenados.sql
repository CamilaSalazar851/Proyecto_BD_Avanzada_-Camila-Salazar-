-- =====================================================================
-- 07_Procedimientos_Almacenados.sql
-- 20 procedimientos almacenados para operaciones complejas y transaccionales
-- =====================================================================
USE ecommerce_db;

DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta;
DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto;
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente;
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion;
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente;
DROP PROCEDURE IF EXISTS sp_AjustarNivelStock;
DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura;
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria;
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas;
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido;
DROP PROCEDURE IF EXISTS sp_RegistrarNuevoCliente;
DROP PROCEDURE IF EXISTS sp_ObtenerDetallesProductoCompleto;
DROP PROCEDURE IF EXISTS sp_FusionarCuentasCliente;
DROP PROCEDURE IF EXISTS sp_AsignarProductoAProveedor;
DROP PROCEDURE IF EXISTS sp_BuscarProductos;
DROP PROCEDURE IF EXISTS sp_ObtenerDashboardAdmin;
DROP PROCEDURE IF EXISTS sp_ProcesarPago;
DROP PROCEDURE IF EXISTS sp_AnadirResenaProducto;
DROP PROCEDURE IF EXISTS sp_ObtenerProductosRelacionados;
DROP PROCEDURE IF EXISTS sp_MoverProductosEntreCategorias;

DELIMITER $$

-- 1. Procesa una nueva venta de forma transaccional
--    p_items_json: '[{"id_producto":1,"cantidad":2},{"id_producto":3,"cantidad":1}]'
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_id_sucursal INT,
    IN p_items_json JSON,
    OUT p_id_venta_generado INT
)
BEGIN
    DECLARE v_num_items INT;
    DECLARE v_i INT DEFAULT 0;
    DECLARE v_id_producto INT;
    DECLARE v_cantidad INT;
    DECLARE v_precio_actual DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO ventas (id_cliente, id_sucursal, estado, total)
    VALUES (p_id_cliente, p_id_sucursal, 'Pendiente de Pago', 0);
    SET p_id_venta_generado = LAST_INSERT_ID();

    SET v_num_items = JSON_LENGTH(p_items_json);
    WHILE v_i < v_num_items DO
        SET v_id_producto = JSON_UNQUOTE(JSON_EXTRACT(p_items_json, CONCAT('$[', v_i, '].id_producto')));
        SET v_cantidad    = JSON_UNQUOTE(JSON_EXTRACT(p_items_json, CONCAT('$[', v_i, '].cantidad')));
        SET v_precio_actual = fn_ObtenerPrecioProducto(v_id_producto);

        INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
        VALUES (p_id_venta_generado, v_id_producto, v_cantidad, v_precio_actual);

        SET v_i = v_i + 1;
    END WHILE;

    UPDATE ventas
       SET total = fn_CalcularTotalVenta(p_id_venta_generado)
     WHERE id_venta = p_id_venta_generado;

    COMMIT;
END$$

-- 2. Inserta un nuevo producto y sus atributos iniciales
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_nombre VARCHAR(200),
    IN p_descripcion TEXT,
    IN p_precio DECIMAL(10,2),
    IN p_costo DECIMAL(10,2),
    IN p_stock_inicial INT,
    IN p_id_categoria INT,
    IN p_id_proveedor INT,
    OUT p_id_producto_generado INT
)
BEGIN
    DECLARE v_sku VARCHAR(50);
    SET v_sku = fn_GenerarSKU(p_nombre, p_id_categoria);

    INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor)
    VALUES (p_nombre, p_descripcion, p_precio, p_costo, p_stock_inicial, v_sku, p_id_categoria, p_id_proveedor);

    SET p_id_producto_generado = LAST_INSERT_ID();
END$$

-- 3. Actualiza la dirección de un cliente en todas las tablas relevantes
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT,
    IN p_nueva_direccion VARCHAR(255),
    IN p_nueva_ciudad VARCHAR(100)
)
BEGIN
    UPDATE clientes
       SET direccion_envio = p_nueva_direccion,
           ciudad = p_nueva_ciudad
     WHERE id_cliente = p_id_cliente;
END$$

-- 4. Gestiona la devolución de un producto, ajustando stock y generando un crédito
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_detalle INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_id_producto INT;
    DECLARE v_cantidad INT;
    DECLARE v_id_venta INT;
    DECLARE v_monto_credito DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT id_producto, cantidad, id_venta, cantidad * precio_unitario_congelado
      INTO v_id_producto, v_cantidad, v_id_venta, v_monto_credito
      FROM detalle_ventas WHERE id_detalle = p_id_detalle;

    UPDATE productos SET stock = stock + v_cantidad WHERE id_producto = v_id_producto;

    UPDATE ventas SET estado = 'Cancelado' WHERE id_venta = v_id_venta;

    INSERT INTO historial_estados_pedido (id_venta, estado_anterior, estado_nuevo)
    VALUES (v_id_venta, 'Devolución', CONCAT('Procesada: ', p_motivo, ' - Crédito: ', v_monto_credito));

    COMMIT;
END$$

-- 5. Devuelve el historial completo de compras de un cliente
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(IN p_id_cliente INT)
BEGIN
    SELECT
        v.id_venta, v.fecha_venta, v.estado, v.total,
        p.nombre AS producto, dv.cantidad, dv.precio_unitario_congelado
    FROM ventas v
    JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    JOIN productos p ON p.id_producto = dv.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC;
END$$

-- 6. Permite ajustar manualmente el stock de un producto, registrando el motivo
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_nuevo_stock INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_stock_anterior INT;
    SELECT stock INTO v_stock_anterior FROM productos WHERE id_producto = p_id_producto;

    UPDATE productos SET stock = p_nuevo_stock WHERE id_producto = p_id_producto;

    INSERT INTO log_permisos (usuario_afectado, accion, detalle)
    VALUES (CURRENT_USER(), 'AJUSTE_STOCK',
            CONCAT('Producto ', p_id_producto, ': ', v_stock_anterior, ' -> ', p_nuevo_stock, ' Motivo: ', p_motivo));
END$$

-- 7. Anonimiza los datos de un cliente en lugar de borrarlo (integridad referencial)
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(IN p_id_cliente INT)
BEGIN
    UPDATE clientes
       SET nombre = 'Cliente',
           apellido = 'Eliminado',
           email = CONCAT('eliminado_', p_id_cliente, '@anonimo.local'),
           contrasena_hash = SHA2(CONCAT('eliminado', p_id_cliente, NOW()), 256),
           direccion_envio = NULL,
           ciudad = NULL,
           fecha_nacimiento = NULL,
           activo = FALSE,
           eliminado_en = CURRENT_TIMESTAMP
     WHERE id_cliente = p_id_cliente;
END$$

-- 8. Aplica un descuento a todos los productos de una categoría específica
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_porcentaje DECIMAL(5,2)
)
BEGIN
    UPDATE productos
       SET precio = fn_AplicarDescuento(precio, p_porcentaje)
     WHERE id_categoria = p_id_categoria AND activo = TRUE;
END$$

-- 9. Genera un reporte completo de ventas para un mes y año dados
CREATE PROCEDURE sp_GenerarReporteMensualVentas(IN p_mes INT, IN p_anio INT)
BEGIN
    SELECT
        COUNT(DISTINCT v.id_venta)             AS numero_ordenes,
        COALESCE(SUM(v.total), 0)              AS ingresos_totales,
        COALESCE(AVG(v.total), 0)              AS ticket_promedio,
        COALESCE(SUM(dv.cantidad), 0)          AS unidades_vendidas
    FROM ventas v
    LEFT JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    WHERE MONTH(v.fecha_venta) = p_mes
      AND YEAR(v.fecha_venta) = p_anio
      AND v.estado <> 'Cancelado';
END$$

-- 10. Cambia el estado de un pedido y deja registro para notificación a otros sistemas
CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta INT,
    IN p_nuevo_estado VARCHAR(30)
)
BEGIN
    UPDATE ventas SET estado = p_nuevo_estado WHERE id_venta = p_id_venta;
    -- El cambio queda auditado automáticamente por trg_log_order_status_change.
    -- Aquí se dejaría la integración con colas de mensajes (SQS, RabbitMQ, etc.)
    -- para notificar a sistemas externos (logística, facturación, CRM).
END$$

-- 11. Registra un nuevo cliente validando que el email no exista
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(100),
    IN p_apellido VARCHAR(100),
    IN p_email VARCHAR(150),
    IN p_contrasena_plana VARCHAR(255),
    IN p_direccion VARCHAR(255),
    IN p_ciudad VARCHAR(100),
    OUT p_id_cliente_generado INT
)
BEGIN
    IF EXISTS (SELECT 1 FROM clientes WHERE email = p_email) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un cliente registrado con este email.';
    END IF;

    IF NOT fn_ValidarComplejidadContrasena(p_contrasena_plana) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La contraseña no cumple los requisitos de seguridad.';
    END IF;

    INSERT INTO clientes (nombre, apellido, email, contrasena_hash, direccion_envio, ciudad)
    VALUES (p_nombre, p_apellido, p_email, SHA2(p_contrasena_plana, 256), p_direccion, p_ciudad);

    SET p_id_cliente_generado = LAST_INSERT_ID();
END$$

-- 12. Devuelve toda la información de un producto, incluyendo proveedor y categoría
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(IN p_id_producto INT)
BEGIN
    SELECT
        p.*,
        cat.nombre AS categoria_nombre,
        prov.nombre AS proveedor_nombre,
        prov.email_contacto AS proveedor_email
    FROM productos p
    LEFT JOIN categorias cat ON cat.id_categoria = p.id_categoria
    LEFT JOIN proveedores prov ON prov.id_proveedor = p.id_proveedor
    WHERE p.id_producto = p_id_producto;
END$$

-- 13. Fusiona dos cuentas de cliente duplicadas en una sola
CREATE PROCEDURE sp_FusionarCuentasCliente(
    IN p_id_cliente_principal INT,
    IN p_id_cliente_duplicado INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE ventas SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;
    UPDATE carritos SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;
    UPDATE resenas_productos SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;

    UPDATE clientes
       SET total_gastado = (SELECT COALESCE(SUM(total),0) FROM ventas
                              WHERE id_cliente = p_id_cliente_principal AND estado <> 'Cancelado')
     WHERE id_cliente = p_id_cliente_principal;

    CALL sp_EliminarClienteDeFormaSegura(p_id_cliente_duplicado);

    COMMIT;
END$$

-- 14. Asigna o cambia el proveedor de un producto
CREATE PROCEDURE sp_AsignarProductoAProveedor(
    IN p_id_producto INT,
    IN p_id_proveedor INT
)
BEGIN
    UPDATE productos SET id_proveedor = p_id_proveedor WHERE id_producto = p_id_producto;
END$$

-- 15. Realiza una búsqueda avanzada de productos con filtros
CREATE PROCEDURE sp_BuscarProductos(
    IN p_nombre VARCHAR(200),
    IN p_id_categoria INT,
    IN p_precio_min DECIMAL(10,2),
    IN p_precio_max DECIMAL(10,2)
)
BEGIN
    SELECT p.*, cat.nombre AS categoria
      FROM productos p
      LEFT JOIN categorias cat ON cat.id_categoria = p.id_categoria
     WHERE p.activo = TRUE
       AND (p_nombre IS NULL OR p.nombre LIKE CONCAT('%', p_nombre, '%'))
       AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
       AND (p_precio_min IS NULL OR p.precio >= p_precio_min)
       AND (p_precio_max IS NULL OR p.precio <= p_precio_max)
     ORDER BY p.nombre;
END$$

-- 16. Devuelve un conjunto de KPIs para un panel de administración
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT
        (SELECT COALESCE(SUM(total),0) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado') AS ventas_hoy,
        (SELECT COUNT(*) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado')              AS ordenes_hoy,
        (SELECT COUNT(*) FROM clientes WHERE DATE(fecha_registro) = CURDATE())                                   AS nuevos_clientes_hoy,
        (SELECT COUNT(*) FROM productos WHERE stock < stock_minimo AND activo = TRUE)                            AS productos_bajo_stock,
        (SELECT COUNT(*) FROM ventas WHERE estado = 'Pendiente de Pago')                                         AS pedidos_pendientes;
END$$

-- 17. Simula el procesamiento de un pago para una venta
CREATE PROCEDURE sp_ProcesarPago(
    IN p_id_venta INT,
    IN p_monto_pagado DECIMAL(12,2)
)
BEGIN
    DECLARE v_total_venta DECIMAL(12,2);
    SELECT total INTO v_total_venta FROM ventas WHERE id_venta = p_id_venta;

    IF p_monto_pagado < v_total_venta THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El monto pagado es insuficiente para cubrir el total de la venta.';
    END IF;

    UPDATE ventas SET estado = 'Procesando' WHERE id_venta = p_id_venta;
END$$

-- 18. Permite a un cliente añadir una reseña a un producto que ha comprado
CREATE PROCEDURE sp_AnadirResenaProducto(
    IN p_id_producto INT,
    IN p_id_cliente INT,
    IN p_calificacion TINYINT,
    IN p_comentario TEXT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM detalle_ventas dv
        JOIN ventas v ON v.id_venta = dv.id_venta
        WHERE dv.id_producto = p_id_producto
          AND v.id_cliente = p_id_cliente
          AND v.estado IN ('Entregado','Enviado','Procesando')
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El cliente no ha comprado este producto; no puede reseñarlo.';
    END IF;

    INSERT INTO resenas_productos (id_producto, id_cliente, calificacion, comentario)
    VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario);
END$$

-- 19. Devuelve productos relacionados a uno dado, basándose en compras conjuntas
CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT)
BEGIN
    SELECT
        p2.id_producto, p2.nombre, COUNT(*) AS veces_comprados_juntos
    FROM detalle_ventas d1
    JOIN detalle_ventas d2 ON d1.id_venta = d2.id_venta AND d1.id_producto <> d2.id_producto
    JOIN productos p2 ON p2.id_producto = d2.id_producto
    WHERE d1.id_producto = p_id_producto
    GROUP BY p2.id_producto, p2.nombre
    ORDER BY veces_comprados_juntos DESC
    LIMIT 5;
END$$

-- 20. Mueve uno o más productos de una categoría a otra de forma segura
CREATE PROCEDURE sp_MoverProductosEntreCategorias(
    IN p_id_categoria_origen INT,
    IN p_id_categoria_destino INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM categorias WHERE id_categoria = p_id_categoria_destino) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La categoría destino no existe.';
    END IF;

    UPDATE productos
       SET id_categoria = p_id_categoria_destino
     WHERE id_categoria = p_id_categoria_origen;
END$$

DELIMITER ;
