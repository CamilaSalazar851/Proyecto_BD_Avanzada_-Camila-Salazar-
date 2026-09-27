-- =====================================================================
-- 03_Funciones.sql
-- 20 funciones definidas por el usuario (UDFs)
-- =====================================================================
USE ecommerce_db;

DROP FUNCTION IF EXISTS fn_CalcularTotalVenta;
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock;
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto;
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente;
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto;
DROP FUNCTION IF EXISTS fn_EsClienteNuevo;
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio;
DROP FUNCTION IF EXISTS fn_AplicarDescuento;
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra;
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail;
DROP FUNCTION IF EXISTS fn_ObtenerNombreCategoria;
DROP FUNCTION IF EXISTS fn_ContarVentasCliente;
DROP FUNCTION IF EXISTS fn_CalcularDiasDesdeUltimaCompra;
DROP FUNCTION IF EXISTS fn_DeterminarEstadoLealtad;
DROP FUNCTION IF EXISTS fn_GenerarSKU;
DROP FUNCTION IF EXISTS fn_CalcularIVA;
DROP FUNCTION IF EXISTS fn_ObtenerStockTotalPorCategoria;
DROP FUNCTION IF EXISTS fn_EstimarFechaEntrega;
DROP FUNCTION IF EXISTS fn_ConvertirMoneda;
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContrasena;

DELIMITER $$

-- 1. Calcula el monto total de una venta específica a partir de su detalle
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);
    SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
      INTO v_total
      FROM detalle_ventas
     WHERE id_venta = p_id_venta;
    RETURN v_total;
END$$

-- 2. Valida si hay stock suficiente para un producto
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = p_id_producto;
    RETURN (v_stock IS NOT NULL AND v_stock >= p_cantidad);
END$$

-- 3. Devuelve el precio actual de un producto
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(10,2);
    SELECT precio INTO v_precio FROM productos WHERE id_producto = p_id_producto;
    RETURN v_precio;
END$$

-- 4. Calcula la edad de un cliente a partir de su fecha de nacimiento
CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha_nac DATE;
    SELECT fecha_nacimiento INTO v_fecha_nac FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_fecha_nac IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN TIMESTAMPDIFF(YEAR, v_fecha_nac, CURDATE());
END$$

-- 5. Devuelve el nombre y apellido de un cliente en formato estandarizado
CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(210)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nombre_completo VARCHAR(210);
    SELECT CONCAT(UPPER(LEFT(apellido,1)), LOWER(SUBSTRING(apellido,2)), ', ',
                  UPPER(LEFT(nombre,1)), LOWER(SUBSTRING(nombre,2)))
      INTO v_nombre_completo
      FROM clientes WHERE id_cliente = p_id_cliente;
    RETURN v_nombre_completo;
END$$

-- 6. Devuelve VERDADERO si el cliente realizó su primera compra en los últimos 30 días
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATE;
    SELECT MIN(fecha_venta) INTO v_primera_compra
      FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    IF v_primera_compra IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN DATEDIFF(CURDATE(), v_primera_compra) <= 30;
END$$

-- 7. Calcula el costo de envío según el peso total de los productos de una venta
CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_peso_total DECIMAL(10,2);
    DECLARE v_costo_base DECIMAL(10,2) DEFAULT 8000;
    DECLARE v_costo_por_kg DECIMAL(10,2) DEFAULT 2500;

    SELECT COALESCE(SUM(p.peso_kg * dv.cantidad), 0)
      INTO v_peso_total
      FROM detalle_ventas dv
      JOIN productos p ON p.id_producto = dv.id_producto
     WHERE dv.id_venta = p_id_venta;

    RETURN ROUND(v_costo_base + (v_peso_total * v_costo_por_kg), 2);
END$$

-- 8. Aplica un porcentaje de descuento a un monto dado
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(12,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_porcentaje < 0 OR p_porcentaje > 100 THEN
        RETURN p_monto;
    END IF;
    RETURN ROUND(p_monto * (1 - (p_porcentaje / 100)), 2);
END$$

-- 9. Devuelve la fecha de la última compra de un cliente
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATE
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha DATE;
    SELECT MAX(fecha_venta) INTO v_fecha
      FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_fecha;
END$$

-- 10. Comprueba si una cadena de texto tiene un formato de correo electrónico válido
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    RETURN p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';
END$$

-- 11. Devuelve el nombre de la categoría a partir del ID de un producto
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(100)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nombre_categoria VARCHAR(100);
    SELECT cat.nombre INTO v_nombre_categoria
      FROM productos p
      JOIN categorias cat ON cat.id_categoria = p.id_categoria
     WHERE p.id_producto = p_id_producto;
    RETURN v_nombre_categoria;
END$$

-- 12. Cuenta el número total de compras realizadas por un cliente
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    SELECT COUNT(*) INTO v_total
      FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_total;
END$$

-- 13. Devuelve el número de días transcurridos desde la última compra de un cliente
CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ultima_fecha DATE;
    SET v_ultima_fecha = fn_ObtenerUltimaFechaCompra(p_id_cliente);
    IF v_ultima_fecha IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN DATEDIFF(CURDATE(), v_ultima_fecha);
END$$

-- 14. Asigna un estado de lealtad (Bronce, Plata, Oro) según el gasto total
CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT)
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_gasto_total DECIMAL(12,2);
    SELECT COALESCE(SUM(total), 0) INTO v_gasto_total
      FROM ventas WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';

    IF v_gasto_total >= 1000000 THEN
        RETURN 'Oro';
    ELSEIF v_gasto_total >= 300000 THEN
        RETURN 'Plata';
    ELSE
        RETURN 'Bronce';
    END IF;
END$$

-- 15. Genera un código de producto (SKU) único basado en nombre y categoría
CREATE FUNCTION fn_GenerarSKU(p_nombre VARCHAR(200), p_id_categoria INT)
RETURNS VARCHAR(50)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_prefijo_categoria VARCHAR(10);
    DECLARE v_prefijo_nombre VARCHAR(10);
    DECLARE v_sufijo INT;

    SELECT UPPER(LEFT(nombre, 3)) INTO v_prefijo_categoria
      FROM categorias WHERE id_categoria = p_id_categoria;

    SET v_prefijo_nombre = UPPER(LEFT(REPLACE(p_nombre, ' ', ''), 3));
    SET v_sufijo = FLOOR(100 + RAND() * 899);

    RETURN CONCAT(COALESCE(v_prefijo_categoria, 'GEN'), '-', v_prefijo_nombre, '-', v_sufijo);
END$$

-- 16. Calcula el impuesto (IVA) sobre el total de una venta
CREATE FUNCTION fn_CalcularIVA(p_monto DECIMAL(12,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_tasa_iva DECIMAL(5,4) DEFAULT 0.1900;  -- 19%
    RETURN ROUND(p_monto * v_tasa_iva, 2);
END$$

-- 17. Suma el stock de todos los productos de una categoría
CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock_total INT;
    SELECT COALESCE(SUM(stock), 0) INTO v_stock_total
      FROM productos WHERE id_categoria = p_id_categoria AND activo = TRUE;
    RETURN v_stock_total;
END$$

-- 18. Calcula la fecha estimada de entrega según la ciudad del cliente
CREATE FUNCTION fn_EstimarFechaEntrega(p_id_venta INT)
RETURNS DATE
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ciudad VARCHAR(100);
    DECLARE v_dias_entrega INT;
    DECLARE v_fecha_venta TIMESTAMP;

    SELECT c.ciudad, v.fecha_venta INTO v_ciudad, v_fecha_venta
      FROM ventas v JOIN clientes c ON c.id_cliente = v.id_cliente
     WHERE v.id_venta = p_id_venta;

    SET v_dias_entrega = CASE
        WHEN v_ciudad = 'Bogotá' THEN 2
        WHEN v_ciudad IN ('Medellín','Cali') THEN 3
        ELSE 5
    END;

    RETURN DATE_ADD(DATE(v_fecha_venta), INTERVAL v_dias_entrega DAY);
END$$

-- 19. Convierte un monto a otra moneda usando una tasa de cambio fija
CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(14,2), p_tasa_cambio DECIMAL(12,6))
RETURNS DECIMAL(14,2)
DETERMINISTIC
NO SQL
BEGIN
    RETURN ROUND(p_monto * p_tasa_cambio, 2);
END$$

-- 20. Verifica si una contraseña cumple con los criterios de seguridad
--     (mínimo 8 caracteres, al menos una mayúscula, un número y un carácter especial)
CREATE FUNCTION fn_ValidarComplejidadContrasena(p_contrasena VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    IF CHAR_LENGTH(p_contrasena) < 8 THEN
        RETURN FALSE;
    ELSEIF p_contrasena NOT REGEXP '[A-Z]' THEN
        RETURN FALSE;
    ELSEIF p_contrasena NOT REGEXP '[0-9]' THEN
        RETURN FALSE;
    ELSEIF p_contrasena NOT REGEXP '[^A-Za-z0-9]' THEN
        RETURN FALSE;
    END IF;
    RETURN TRUE;
END$$

DELIMITER ;
