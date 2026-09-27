-- =====================================================================
-- 02_Consultas_Avanzadas.sql
-- 20 consultas de análisis y reporteo sobre ecommerce_db
-- =====================================================================
USE ecommerce_db;

-- 1. Top 10 Productos Más Vendidos (ranking por ingresos generados)
SELECT
    p.id_producto,
    p.nombre,
    SUM(dv.cantidad)                              AS unidades_vendidas,
    SUM(dv.cantidad * dv.precio_unitario_congelado) AS ingresos_totales
FROM detalle_ventas dv
JOIN productos p ON p.id_producto = dv.id_producto
JOIN ventas v ON v.id_venta = dv.id_venta
WHERE v.estado <> 'Cancelado'
GROUP BY p.id_producto, p.nombre
ORDER BY ingresos_totales DESC
LIMIT 10;

-- 2. Productos con Bajas Ventas (10% inferior por unidades vendidas)
WITH ventas_producto AS (
    SELECT p.id_producto, p.nombre,
           COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas
    FROM productos p
    LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
    LEFT JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
    GROUP BY p.id_producto, p.nombre
),
ranked AS (
    SELECT *, PERCENT_RANK() OVER (ORDER BY unidades_vendidas) AS pr
    FROM ventas_producto
)
SELECT id_producto, nombre, unidades_vendidas
FROM ranked
WHERE pr <= 0.10
ORDER BY unidades_vendidas ASC;

-- 3. Clientes VIP: Top 5 por valor de vida (LTV = gasto total histórico)
SELECT
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    SUM(v.total) AS ltv_total
FROM clientes c
JOIN ventas v ON v.id_cliente = c.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.id_cliente, cliente
ORDER BY ltv_total DESC
LIMIT 5;

-- 4. Análisis de Ventas Mensuales (totales agrupados por mes y año)
SELECT
    YEAR(fecha_venta)  AS anio,
    MONTH(fecha_venta) AS mes,
    COUNT(*)           AS numero_ordenes,
    SUM(total)         AS ventas_totales
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY YEAR(fecha_venta), MONTH(fecha_venta)
ORDER BY anio, mes;

-- 5. Crecimiento de Clientes (nuevos clientes por trimestre)
SELECT
    YEAR(fecha_registro)    AS anio,
    QUARTER(fecha_registro) AS trimestre,
    COUNT(*)                AS nuevos_clientes
FROM clientes
GROUP BY YEAR(fecha_registro), QUARTER(fecha_registro)
ORDER BY anio, trimestre;

-- 6. Tasa de Compra Repetida (% de clientes con más de una compra)
WITH compras_por_cliente AS (
    SELECT id_cliente, COUNT(*) AS num_compras
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente
)
SELECT
    ROUND(
      100.0 * SUM(CASE WHEN num_compras > 1 THEN 1 ELSE 0 END) / COUNT(*),
      2
    ) AS porcentaje_compra_repetida
FROM compras_por_cliente;

-- 7. Productos Comprados Juntos Frecuentemente (pares por transacción)
SELECT
    p1.nombre AS producto_a,
    p2.nombre AS producto_b,
    COUNT(*)  AS veces_comprados_juntos
FROM detalle_ventas d1
JOIN detalle_ventas d2
    ON d1.id_venta = d2.id_venta AND d1.id_producto < d2.id_producto
JOIN productos p1 ON p1.id_producto = d1.id_producto
JOIN productos p2 ON p2.id_producto = d2.id_producto
GROUP BY p1.nombre, p2.nombre
ORDER BY veces_comprados_juntos DESC
LIMIT 20;

-- 8. Rotación de Inventario por Categoría
--    Rotación = unidades vendidas en el período / stock promedio actual de la categoría
SELECT
    cat.id_categoria,
    cat.nombre,
    COALESCE(SUM(dv.cantidad), 0)                              AS unidades_vendidas,
    NULLIF(SUM(p.stock), 0)                                    AS stock_actual_total,
    ROUND(COALESCE(SUM(dv.cantidad), 0) / NULLIF(SUM(p.stock), 0), 2) AS tasa_rotacion
FROM categorias cat
JOIN productos p ON p.id_categoria = cat.id_categoria
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
LEFT JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
GROUP BY cat.id_categoria, cat.nombre;

-- 9. Productos que Necesitan Reabastecimiento (stock por debajo del mínimo)
SELECT id_producto, nombre, stock, stock_minimo
FROM productos
WHERE activo = TRUE AND stock < stock_minimo
ORDER BY (stock_minimo - stock) DESC;

-- 10. Análisis de Carrito Abandonado (carritos sin venta asociada en X días)
SELECT
    c.id_carrito,
    cli.id_cliente,
    CONCAT(cli.nombre, ' ', cli.apellido) AS cliente,
    c.fecha_creacion,
    TIMESTAMPDIFF(HOUR, c.fecha_actualizacion, NOW()) AS horas_sin_actividad
FROM carritos c
JOIN clientes cli ON cli.id_cliente = c.id_cliente
WHERE c.estado = 'Abandonado'
   OR (c.estado = 'Activo' AND c.fecha_actualizacion < NOW() - INTERVAL 72 HOUR)
ORDER BY c.fecha_actualizacion ASC;

-- 11. Rendimiento de Proveedores (clasificados por volumen de ventas)
SELECT
    prov.id_proveedor,
    prov.nombre,
    COALESCE(SUM(dv.cantidad), 0)                               AS unidades_vendidas,
    COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) AS ingresos_generados
FROM proveedores prov
JOIN productos p ON p.id_proveedor = prov.id_proveedor
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
LEFT JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
GROUP BY prov.id_proveedor, prov.nombre
ORDER BY ingresos_generados DESC;

-- 12. Análisis Geográfico de Ventas (agrupado por ciudad del cliente)
SELECT
    c.ciudad,
    COUNT(DISTINCT v.id_venta) AS numero_ordenes,
    SUM(v.total)               AS ventas_totales
FROM ventas v
JOIN clientes c ON c.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.ciudad
ORDER BY ventas_totales DESC;

-- 13. Ventas por Hora del Día (horas pico de compra)
SELECT
    HOUR(fecha_venta) AS hora_del_dia,
    COUNT(*)           AS numero_ordenes,
    SUM(total)         AS ventas_totales
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY HOUR(fecha_venta)
ORDER BY numero_ordenes DESC;

-- 14. Impacto de Promociones (ventas antes / durante / después de la campaña)
SELECT
    pr.id_promocion,
    p.nombre AS producto,
    SUM(CASE WHEN v.fecha_venta < pr.fecha_inicio THEN dv.cantidad ELSE 0 END) AS unidades_antes,
    SUM(CASE WHEN v.fecha_venta BETWEEN pr.fecha_inicio AND pr.fecha_fin THEN dv.cantidad ELSE 0 END) AS unidades_durante,
    SUM(CASE WHEN v.fecha_venta > pr.fecha_fin THEN dv.cantidad ELSE 0 END) AS unidades_despues
FROM promociones pr
JOIN productos p ON p.id_producto = pr.id_producto
LEFT JOIN detalle_ventas dv ON dv.id_producto = pr.id_producto
LEFT JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
GROUP BY pr.id_promocion, p.nombre;

-- 15. Análisis de Cohort (retención de clientes mes a mes desde su 1ra compra)
WITH primera_compra AS (
    SELECT id_cliente, MIN(DATE_FORMAT(fecha_venta, '%Y-%m-01')) AS mes_cohort
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente
),
compras_mes AS (
    SELECT v.id_cliente, DATE_FORMAT(v.fecha_venta, '%Y-%m-01') AS mes_compra
    FROM ventas v
    WHERE v.estado <> 'Cancelado'
    GROUP BY v.id_cliente, DATE_FORMAT(v.fecha_venta, '%Y-%m-01')
)
SELECT
    pc.mes_cohort,
    PERIOD_DIFF(DATE_FORMAT(cm.mes_compra, '%Y%m'), DATE_FORMAT(pc.mes_cohort, '%Y%m')) AS mes_relativo,
    COUNT(DISTINCT cm.id_cliente) AS clientes_activos
FROM primera_compra pc
JOIN compras_mes cm ON cm.id_cliente = pc.id_cliente
GROUP BY pc.mes_cohort, mes_relativo
ORDER BY pc.mes_cohort, mes_relativo;

-- 16. Margen de Beneficio por Producto
SELECT
    id_producto,
    nombre,
    precio,
    costo,
    ROUND(precio - costo, 2)                         AS margen_absoluto,
    ROUND(100.0 * (precio - costo) / precio, 2)       AS margen_porcentual
FROM productos
ORDER BY margen_porcentual DESC;

-- 17. Tiempo Promedio Entre Compras (por cliente, en días)
WITH ventas_ordenadas AS (
    SELECT
        id_cliente,
        fecha_venta,
        LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta) AS venta_anterior
    FROM ventas
    WHERE estado <> 'Cancelado'
)
SELECT
    id_cliente,
    ROUND(AVG(DATEDIFF(fecha_venta, venta_anterior)), 1) AS dias_promedio_entre_compras
FROM ventas_ordenadas
WHERE venta_anterior IS NOT NULL
GROUP BY id_cliente;

-- 18. Productos Más Vistos vs. Comprados
SELECT
    p.id_producto,
    p.nombre,
    COALESCE(vp.total_vistas, 0)    AS total_vistas,
    COALESCE(dv.total_comprados, 0) AS total_comprados,
    ROUND(COALESCE(dv.total_comprados, 0) / NULLIF(vp.total_vistas, 0) * 100, 2) AS tasa_conversion_pct
FROM productos p
LEFT JOIN (SELECT id_producto, COUNT(*) AS total_vistas FROM vistas_producto GROUP BY id_producto) vp
       ON vp.id_producto = p.id_producto
LEFT JOIN (SELECT dv.id_producto, SUM(dv.cantidad) AS total_comprados
           FROM detalle_ventas dv JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
           GROUP BY dv.id_producto) dv ON dv.id_producto = p.id_producto
ORDER BY total_vistas DESC;

-- 19. Segmentación de Clientes (RFM: Recencia, Frecuencia, Monetario)
WITH rfm_base AS (
    SELECT
        c.id_cliente,
        DATEDIFF(CURDATE(), MAX(v.fecha_venta)) AS recencia_dias,
        COUNT(v.id_venta)                       AS frecuencia,
        SUM(v.total)                            AS monetario
    FROM clientes c
    JOIN ventas v ON v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
    GROUP BY c.id_cliente
),
rfm_scores AS (
    SELECT
        id_cliente, recencia_dias, frecuencia, monetario,
        NTILE(5) OVER (ORDER BY recencia_dias DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frecuencia ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetario ASC)      AS m_score
    FROM rfm_base
)
SELECT
    id_cliente, recencia_dias, frecuencia, monetario,
    r_score, f_score, m_score,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Campeón'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Cliente Leal'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'En Riesgo'
        ELSE 'Regular'
    END AS segmento_rfm
FROM rfm_scores
ORDER BY monetario DESC;

-- 20. Predicción de Demanda Simple (promedio móvil de los últimos 3 meses por categoría)
WITH ventas_mensuales_categoria AS (
    SELECT
        cat.id_categoria,
        cat.nombre,
        DATE_FORMAT(v.fecha_venta, '%Y-%m') AS mes,
        SUM(dv.cantidad) AS unidades_vendidas
    FROM detalle_ventas dv
    JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
    JOIN productos p ON p.id_producto = dv.id_producto
    JOIN categorias cat ON cat.id_categoria = p.id_categoria
    GROUP BY cat.id_categoria, cat.nombre, mes
)
SELECT
    id_categoria,
    nombre,
    ROUND(AVG(unidades_vendidas), 1) AS demanda_promedio_mensual,
    ROUND(AVG(unidades_vendidas), 1) AS prediccion_proximo_mes  -- promedio móvil simple como estimador
FROM ventas_mensuales_categoria
GROUP BY id_categoria, nombre
ORDER BY prediccion_proximo_mes DESC;
