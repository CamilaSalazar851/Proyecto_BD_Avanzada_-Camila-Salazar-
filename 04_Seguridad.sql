-- =====================================================================
-- 04_Seguridad.sql
-- Roles, usuarios, permisos y vistas de seguridad (MySQL 8.0+)
-- =====================================================================
USE ecommerce_db;

-- ---------------------------------------------------------------------
-- 13. Vista que oculta información sensible de clientes
--     (se crea antes de los GRANT que la referencian)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_info_clientes_basica;
CREATE VIEW v_info_clientes_basica AS
SELECT
    id_cliente,
    nombre,
    apellido,
    ciudad,
    fecha_registro,
    nivel_lealtad
FROM clientes;

DROP VIEW IF EXISTS v_productos_publicos;
CREATE VIEW v_productos_publicos AS
SELECT id_producto, nombre, descripcion, precio, sku, activo
FROM productos
WHERE activo = TRUE;

-- =====================================================================
-- 1-6. CREACIÓN DE ROLES
-- =====================================================================
DROP ROLE IF EXISTS 'Administrador_Sistema';
DROP ROLE IF EXISTS 'Gerente_Marketing';
DROP ROLE IF EXISTS 'Analista_Datos';
DROP ROLE IF EXISTS 'Empleado_Inventario';
DROP ROLE IF EXISTS 'Atencion_Cliente';
DROP ROLE IF EXISTS 'Auditor_Financiero';
DROP ROLE IF EXISTS 'Visitante';

-- 1. Administrador_Sistema: todos los privilegios
CREATE ROLE 'Administrador_Sistema';
GRANT ALL PRIVILEGES ON ecommerce_db.* TO 'Administrador_Sistema';

-- 2. Gerente_Marketing: solo lectura sobre ventas y clientes
CREATE ROLE 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.clientes TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.promociones TO 'Gerente_Marketing';

-- 3. Analista_Datos: solo lectura sobre todas las tablas, excepto auditoría
CREATE ROLE 'Analista_Datos';
GRANT SELECT ON ecommerce_db.productos TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.categorias TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.proveedores TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.clientes TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.ventas TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.carritos TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.carrito_items TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.vistas_producto TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.promociones TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.resenas_productos TO 'Analista_Datos';
-- (Las tablas log_*, historial_*, alertas_stock y *_archivad* son de auditoría y quedan excluidas)

-- 4. Empleado_Inventario: solo puede modificar productos (stock)
CREATE ROLE 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.productos TO 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.categorias TO 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.proveedores TO 'Empleado_Inventario';
GRANT UPDATE (stock, stock_minimo, activo) ON ecommerce_db.productos TO 'Empleado_Inventario';

-- 5. Atencion_Cliente: ve clientes y ventas, no modifica precios
CREATE ROLE 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO 'Atencion_Cliente';
GRANT SELECT, UPDATE (direccion_envio, ciudad) ON ecommerce_db.clientes TO 'Atencion_Cliente';
GRANT SELECT, UPDATE (estado) ON ecommerce_db.ventas TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.v_productos_publicos TO 'Atencion_Cliente';

-- 6. Auditor_Financiero: solo lectura sobre ventas, productos y logs de precios
CREATE ROLE 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.productos TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.log_cambios_precio TO 'Auditor_Financiero';

-- Rol adicional 17: Visitante — solo puede ver la tabla productos
CREATE ROLE 'Visitante';
GRANT SELECT ON ecommerce_db.v_productos_publicos TO 'Visitante';

-- =====================================================================
-- 7-10. CREACIÓN DE USUARIOS Y ASIGNACIÓN DE ROLES
-- =====================================================================
DROP USER IF EXISTS 'admin_user'@'localhost';
DROP USER IF EXISTS 'marketing_user'@'localhost';
DROP USER IF EXISTS 'inventory_user'@'localhost';
DROP USER IF EXISTS 'support_user'@'localhost';
DROP USER IF EXISTS 'analyst_user'@'localhost';
DROP USER IF EXISTS 'auditor_user'@'localhost';
DROP USER IF EXISTS 'visitor_user'@'localhost';

-- 7. admin_user -> Administrador_Sistema
CREATE USER 'admin_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2024!';
GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
SET DEFAULT ROLE 'Administrador_Sistema' TO 'admin_user'@'localhost';

-- 8. marketing_user -> Gerente_Marketing
CREATE USER 'marketing_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2024!';
GRANT 'Gerente_Marketing' TO 'marketing_user'@'localhost';
SET DEFAULT ROLE 'Gerente_Marketing' TO 'marketing_user'@'localhost';

-- 9. inventory_user -> Empleado_Inventario
CREATE USER 'inventory_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2024!';
GRANT 'Empleado_Inventario' TO 'inventory_user'@'localhost';
SET DEFAULT ROLE 'Empleado_Inventario' TO 'inventory_user'@'localhost';

-- 10. support_user -> Atencion_Cliente
CREATE USER 'support_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2024!';
GRANT 'Atencion_Cliente' TO 'support_user'@'localhost';
SET DEFAULT ROLE 'Atencion_Cliente' TO 'support_user'@'localhost';

-- Usuarios adicionales para los roles restantes
CREATE USER 'analyst_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2024!';
GRANT 'Analista_Datos' TO 'analyst_user'@'localhost';
SET DEFAULT ROLE 'Analista_Datos' TO 'analyst_user'@'localhost';

CREATE USER 'auditor_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2024!';
GRANT 'Auditor_Financiero' TO 'auditor_user'@'localhost';
SET DEFAULT ROLE 'Auditor_Financiero' TO 'auditor_user'@'localhost';

CREATE USER 'visitor_user'@'localhost' IDENTIFIED BY 'Cambiar_Esta_Clave_2024!';
GRANT 'Visitante' TO 'visitor_user'@'localhost';
SET DEFAULT ROLE 'Visitante' TO 'visitor_user'@'localhost';

-- =====================================================================
-- 11. Impedir que Analista_Datos ejecute DELETE o TRUNCATE
--     (por diseño no se le otorgó ni DELETE ni DROP; se refuerza explícitamente)
-- =====================================================================
REVOKE DELETE, DROP ON ecommerce_db.* FROM 'Analista_Datos';

-- =====================================================================
-- 12. Otorgar a Gerente_Marketing permiso para ejecutar SPs de reportes
--     de marketing (se otorga tras crear los procedimientos en 07)
-- =====================================================================
-- NOTA: ejecutar esta línea después de correr 07_Procedimientos_Almacenados.sql
-- GRANT EXECUTE ON PROCEDURE ecommerce_db.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';

-- =====================================================================
-- 14. Revocar UPDATE sobre la columna precio para Empleado_Inventario
--     (ya no se otorgó explícitamente; se revoca de forma defensiva
--      por si en el futuro se concede UPDATE global sobre productos)
-- =====================================================================
REVOKE UPDATE ON ecommerce_db.productos FROM 'Empleado_Inventario';
GRANT UPDATE (stock, stock_minimo, activo) ON ecommerce_db.productos TO 'Empleado_Inventario';

-- =====================================================================
-- 15. Política de contraseñas seguras para todos los usuarios
-- =====================================================================
-- Requiere el componente validate_password instalado en el servidor:
-- INSTALL COMPONENT 'file://component_validate_password';
SET GLOBAL validate_password.policy = 'STRONG';
SET GLOBAL validate_password.length = 12;
SET GLOBAL validate_password.mixed_case_count = 1;
SET GLOBAL validate_password.number_count = 1;
SET GLOBAL validate_password.special_char_count = 1;

ALTER USER 'admin_user'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'marketing_user'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'inventory_user'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;
ALTER USER 'support_user'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;

-- =====================================================================
-- 16. Asegurar que 'root' no pueda ser usado desde conexiones remotas
-- =====================================================================
DROP USER IF EXISTS 'root'@'%';
-- Se conserva únicamente 'root'@'localhost' (acceso local del servidor)

-- =====================================================================
-- 18. Limitar el número de consultas por hora para Analista_Datos
-- =====================================================================
ALTER USER 'analyst_user'@'localhost' WITH MAX_QUERIES_PER_HOUR 500;

-- =====================================================================
-- 19. Restringir que los usuarios solo vean ventas de su propia sucursal
--     Se implementa mediante una vista parametrizada por sesión, usando
--     una variable de sesión que la aplicación establece al autenticar.
-- =====================================================================
DROP VIEW IF EXISTS v_ventas_por_sucursal_actual;
CREATE VIEW v_ventas_por_sucursal_actual AS
SELECT v.*
FROM ventas v
WHERE v.id_sucursal = CAST(@sucursal_actual AS UNSIGNED);
-- La aplicación debe ejecutar: SET @sucursal_actual = <id_sucursal_del_usuario>;
-- antes de consultar esta vista.

-- =====================================================================
-- 20. Auditar todos los intentos de inicio de sesión fallidos
--     (la tabla log_intentos_login se creó en 01; aquí se define el
--      procedimiento auxiliar que la aplicación invoca en cada intento)
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_RegistrarIntentoLogin;
DELIMITER $$
CREATE PROCEDURE sp_RegistrarIntentoLogin(
    IN p_usuario VARCHAR(100),
    IN p_exitoso BOOLEAN,
    IN p_ip VARCHAR(45)
)
BEGIN
    INSERT INTO log_intentos_login (usuario, exitoso, ip_origen)
    VALUES (p_usuario, p_exitoso, p_ip);
END$$
DELIMITER ;

FLUSH PRIVILEGES;
