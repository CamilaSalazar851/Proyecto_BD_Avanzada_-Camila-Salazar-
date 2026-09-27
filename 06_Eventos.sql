-- =====================================================================
-- 06_Eventos.sql
-- Tabla de reportes semanales + 20 eventos programados de mantenimiento
-- =====================================================================
USE ecommerce_db;

CREATE TABLE IF NOT EXISTS reporte_ventas_semanales (
    id_reporte       INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio    DATE NOT NULL,
    semana_fin       DATE NOT NULL,
    total_ventas     DECIMAL(14,2) NOT NULL,
    numero_ordenes   INT NOT NULL,
    fecha_generacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabla auxiliar para el evento 8 (temporal, se vacía en cada corrida)
CREATE TABLE IF NOT EXISTS tablas_temporales_log (
    id_log    INT AUTO_INCREMENT PRIMARY KEY,
    contenido VARCHAR(255),
    creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabla auxiliar para el evento 10 (inconsistencias detectadas)
CREATE TABLE IF NOT EXISTS log_inconsistencias (
    id_log       INT AUTO_INCREMENT PRIMARY KEY,
    descripcion  VARCHAR(255) NOT NULL,
    fecha_deteccion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabla auxiliar para el evento 11 (cumpleaños)
CREATE TABLE IF NOT EXISTS lista_cumpleanos_hoy (
    id_cliente  INT PRIMARY KEY,
    nombre      VARCHAR(100),
    email       VARCHAR(150),
    generado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabla auxiliar para el evento 12 (ranking de popularidad)
CREATE TABLE IF NOT EXISTS ranking_productos_populares (
    id_producto     INT PRIMARY KEY,
    unidades_30dias INT NOT NULL,
    actualizado_en  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabla auxiliar para el evento 13 (registro de backups lógicos)
CREATE TABLE IF NOT EXISTS log_backups (
    id_backup   INT AUTO_INCREMENT PRIMARY KEY,
    tabla       VARCHAR(100),
    filas       INT,
    fecha_backup TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

SET GLOBAL event_scheduler = ON;

DROP EVENT IF EXISTS evt_generate_weekly_sales_report;
DROP EVENT IF EXISTS evt_cleanup_temp_tables_daily;
DROP EVENT IF EXISTS evt_archive_old_logs_monthly;
DROP EVENT IF EXISTS evt_deactivate_expired_promotions_hourly;
DROP EVENT IF EXISTS evt_recalculate_customer_loyalty_tiers_nightly;
DROP EVENT IF EXISTS evt_generate_reorder_list_daily;
DROP EVENT IF EXISTS evt_rebuild_indexes_weekly;
DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly;
DROP EVENT IF EXISTS evt_aggregate_daily_sales_data;
DROP EVENT IF EXISTS evt_check_data_consistency_nightly;
DROP EVENT IF EXISTS evt_send_birthday_greetings_daily;
DROP EVENT IF EXISTS evt_update_product_rankings_hourly;
DROP EVENT IF EXISTS evt_backup_critical_tables_daily;
DROP EVENT IF EXISTS evt_clear_abandoned_carts_daily;
DROP EVENT IF EXISTS evt_calculate_monthly_kpis;
DROP EVENT IF EXISTS evt_refresh_materialized_views_nightly;
DROP EVENT IF EXISTS evt_log_database_size_weekly;
DROP EVENT IF EXISTS evt_detect_fraudulent_activity_hourly;
DROP EVENT IF EXISTS evt_generate_supplier_performance_report_monthly;
DROP EVENT IF EXISTS evt_purge_soft_deleted_records_weekly;

DELIMITER $$

-- 1. Genera un reporte de ventas semanal
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL 1 WEEK)
DO
BEGIN
    INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, total_ventas, numero_ordenes)
    SELECT
        DATE_SUB(CURDATE(), INTERVAL 7 DAY),
        CURDATE(),
        COALESCE(SUM(total), 0),
        COUNT(*)
    FROM ventas
    WHERE fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
      AND estado <> 'Cancelado';
END$$

-- 2. Borra tablas temporales diariamente
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
    TRUNCATE TABLE tablas_temporales_log$$

-- 3. Archiva logs de más de 6 meses en tablas históricas
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH STARTS (CURRENT_DATE + INTERVAL 1 MONTH)
DO
BEGIN
    DELETE FROM log_intentos_login WHERE fecha_intento < DATE_SUB(NOW(), INTERVAL 6 MONTH);
    DELETE FROM log_clientes_nuevos WHERE fecha_registro < DATE_SUB(NOW(), INTERVAL 6 MONTH);
END$$

-- 4. Desactiva códigos de descuento (promociones) que han expirado
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
DO
    UPDATE promociones SET activa = FALSE WHERE fecha_fin < CURDATE() AND activa = TRUE$$

-- 5. Recalcula el nivel de lealtad de los clientes cada noche
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 2 HOUR)
DO
BEGIN
    UPDATE clientes SET nivel_lealtad = fn_DeterminarEstadoLealtad(id_cliente);
END$$

-- 6. Crea una lista de productos que necesitan ser reabastecidos
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 3 HOUR)
DO
BEGIN
    INSERT INTO alertas_stock (id_producto, stock_actual)
    SELECT id_producto, stock FROM productos
     WHERE activo = TRUE AND stock < stock_minimo
       AND id_producto NOT IN (
           SELECT id_producto FROM alertas_stock
            WHERE atendida = FALSE AND fecha_alerta >= CURDATE()
       );
END$$

-- 7. Reconstruye los índices de las tablas más usadas
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL 1 WEEK)
DO
BEGIN
    OPTIMIZE TABLE productos, ventas, detalle_ventas, clientes;
END$$

-- 8. Desactiva cuentas de clientes sin actividad en más de un año
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH STARTS (CURRENT_DATE + INTERVAL 3 MONTH)
DO
BEGIN
    UPDATE clientes c
       SET activo = FALSE
     WHERE c.activo = TRUE
       AND (fn_ObtenerUltimaFechaCompra(c.id_cliente) IS NULL
            OR fn_ObtenerUltimaFechaCompra(c.id_cliente) < DATE_SUB(CURDATE(), INTERVAL 1 YEAR))
       AND c.fecha_registro < DATE_SUB(CURDATE(), INTERVAL 1 YEAR);
END$$

-- 9. Agrega los datos de ventas del día en una tabla de resumen
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO resumen_ventas_diarias (fecha, total_ventas, numero_ordenes, ticket_promedio)
    SELECT
        DATE_SUB(CURDATE(), INTERVAL 1 DAY),
        COALESCE(SUM(total), 0),
        COUNT(*),
        COALESCE(AVG(total), 0)
    FROM ventas
    WHERE DATE(fecha_venta) = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
      AND estado <> 'Cancelado'
    ON DUPLICATE KEY UPDATE
        total_ventas = VALUES(total_ventas),
        numero_ordenes = VALUES(numero_ordenes),
        ticket_promedio = VALUES(ticket_promedio);
END$$

-- 10. Busca inconsistencias en los datos (ej. ventas sin detalle)
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 1 HOUR)
DO
BEGIN
    INSERT INTO log_inconsistencias (descripcion)
    SELECT CONCAT('Venta sin detalle: id_venta=', v.id_venta)
      FROM ventas v
      LEFT JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
     WHERE dv.id_detalle IS NULL AND v.estado <> 'Cancelado';
END$$

-- 11. Genera una lista de clientes que cumplen años, para enviarles un cupón
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 6 HOUR)
DO
BEGIN
    TRUNCATE TABLE lista_cumpleanos_hoy;
    INSERT INTO lista_cumpleanos_hoy (id_cliente, nombre, email)
    SELECT id_cliente, CONCAT(nombre,' ',apellido), email
      FROM clientes
     WHERE MONTH(fecha_nacimiento) = MONTH(CURDATE())
       AND DAY(fecha_nacimiento) = DAY(CURDATE());
END$$

-- 12. Actualiza una tabla con el ranking de los productos más populares
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    REPLACE INTO ranking_productos_populares (id_producto, unidades_30dias)
    SELECT dv.id_producto, SUM(dv.cantidad)
      FROM detalle_ventas dv
      JOIN ventas v ON v.id_venta = dv.id_venta
     WHERE v.fecha_venta >= DATE_SUB(NOW(), INTERVAL 30 DAY)
       AND v.estado <> 'Cancelado'
     GROUP BY dv.id_producto;
END$$

-- 13. Realiza un backup lógico (registro de conteo de filas) de tablas críticas
CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 4 HOUR)
DO
BEGIN
    INSERT INTO log_backups (tabla, filas)
    SELECT 'productos', COUNT(*) FROM productos
    UNION ALL SELECT 'clientes', COUNT(*) FROM clientes
    UNION ALL SELECT 'ventas', COUNT(*) FROM ventas
    UNION ALL SELECT 'detalle_ventas', COUNT(*) FROM detalle_ventas;
END$$

-- 14. Vacía los carritos de compra abandonados hace más de 72 horas
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 5 HOUR)
DO
BEGIN
    UPDATE carritos
       SET estado = 'Abandonado'
     WHERE estado = 'Activo'
       AND fecha_actualizacion < NOW() - INTERVAL 72 HOUR;
END$$

-- 15. Calcula los KPIs del mes y los guarda en una tabla
CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH STARTS (CURRENT_DATE + INTERVAL 1 MONTH)
DO
BEGIN
    INSERT INTO kpis_mensuales (mes, anio, ingresos_totales, nuevos_clientes, ticket_promedio, productos_vendidos)
    SELECT
        MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)),
        YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)),
        COALESCE((SELECT SUM(total) FROM ventas
                   WHERE estado <> 'Cancelado'
                     AND MONTH(fecha_venta) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
                     AND YEAR(fecha_venta) = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))), 0),
        (SELECT COUNT(*) FROM clientes
          WHERE MONTH(fecha_registro) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
            AND YEAR(fecha_registro) = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))),
        COALESCE((SELECT AVG(total) FROM ventas
                   WHERE estado <> 'Cancelado'
                     AND MONTH(fecha_venta) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
                     AND YEAR(fecha_venta) = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))), 0),
        COALESCE((SELECT SUM(dv.cantidad) FROM detalle_ventas dv JOIN ventas v ON v.id_venta = dv.id_venta
                   WHERE v.estado <> 'Cancelado'
                     AND MONTH(v.fecha_venta) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
                     AND YEAR(v.fecha_venta) = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))), 0)
    ON DUPLICATE KEY UPDATE
        ingresos_totales = VALUES(ingresos_totales),
        nuevos_clientes = VALUES(nuevos_clientes),
        ticket_promedio = VALUES(ticket_promedio),
        productos_vendidos = VALUES(productos_vendidos);
END$$

-- 16. Actualiza las vistas materializadas (si se usan) — aquí, las tablas resumen
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 2 HOUR + INTERVAL 30 MINUTE)
DO
BEGIN
    REPLACE INTO ranking_productos_populares (id_producto, unidades_30dias)
    SELECT dv.id_producto, SUM(dv.cantidad)
      FROM detalle_ventas dv JOIN ventas v ON v.id_venta = dv.id_venta
     WHERE v.fecha_venta >= DATE_SUB(NOW(), INTERVAL 30 DAY) AND v.estado <> 'Cancelado'
     GROUP BY dv.id_producto;
END$$

-- 17. Registra el tamaño de la base de datos para monitorear su crecimiento
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL 1 WEEK)
DO
BEGIN
    INSERT INTO log_tamano_bd (fecha, tamano_mb)
    SELECT CURDATE(), ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
      FROM information_schema.TABLES
     WHERE table_schema = 'ecommerce_db';
END$$

-- 18. Busca patrones de actividad sospechosa (múltiples pedidos fallidos)
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO log_actividad_sospechosa (id_cliente, descripcion)
    SELECT id_cliente, CONCAT('Múltiples pedidos cancelados en la última hora: ', COUNT(*))
      FROM ventas
     WHERE estado = 'Cancelado' AND fecha_venta >= NOW() - INTERVAL 1 HOUR
     GROUP BY id_cliente
    HAVING COUNT(*) >= 3;
END$$

-- 19. Crea un reporte mensual sobre el rendimiento de los proveedores
CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH STARTS (CURRENT_DATE + INTERVAL 1 MONTH)
DO
BEGIN
    INSERT INTO reporte_rendimiento_proveedores (id_proveedor, mes, anio, unidades_vendidas, ingresos_generados)
    SELECT
        prov.id_proveedor,
        MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)),
        YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)),
        COALESCE(SUM(dv.cantidad), 0),
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0)
    FROM proveedores prov
    JOIN productos p ON p.id_proveedor = prov.id_proveedor
    LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
    LEFT JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
        AND MONTH(v.fecha_venta) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
        AND YEAR(v.fecha_venta) = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
    GROUP BY prov.id_proveedor;
END$$

-- 20. Elimina permanentemente los registros marcados para borrado hace más de 30 días
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL 1 WEEK)
DO
BEGIN
    DELETE FROM productos WHERE eliminado_en IS NOT NULL AND eliminado_en < NOW() - INTERVAL 30 DAY;
    DELETE FROM clientes  WHERE eliminado_en IS NOT NULL AND eliminado_en < NOW() - INTERVAL 30 DAY;
END$$

DELIMITER ;
