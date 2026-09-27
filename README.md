# Proyecto de Base de Datos para un E-commerce

## Descripción

Este proyecto implementa el núcleo completo de una base de datos relacional (MySQL 8.0+) para una tienda en línea. Cubre el modelado de productos, categorías, proveedores, clientes, ventas y su detalle, junto con una capa avanzada de lógica de negocio: consultas analíticas, funciones reutilizables, seguridad basada en roles, triggers de integridad, eventos de mantenimiento programado y procedimientos almacenados transaccionales.

## Integrantes

- Camila Valentina Salazar Castañeda

## Requisitos previos

- MySQL Server 8.0 o superior (se usan roles, `JSON_EXTRACT`, `NTILE`, `PERCENT_RANK`, `CHECK constraints` y `CREATE EVENT`).
- Un cliente para ejecutar scripts `.sql` (MySQL Workbench, `mysql` CLI, DBeaver, etc.).
- Privilegios de administrador (`root` o equivalente) para crear la base de datos, roles y usuarios.
- El componente `validate_password` instalado si se desea aplicar la política de contraseñas del script `04_Seguridad.sql` (opcional; esas líneas pueden comentarse si el componente no está disponible).

## Instrucciones de Ejecución

Los scripts deben ejecutarse **en orden estricto**, ya que cada uno depende de estructuras creadas en los anteriores (tablas, funciones usadas por triggers, etc.).

1. **`01_Esquema_y_Datos.sql`** — Crea la base de datos `ecommerce_db`, todas las tablas (entidades principales y de soporte/auditoría) y carga los datos de ejemplo iniciales.
2. **`02_Consultas_Avanzadas.sql`** — Contiene las 20 consultas de análisis y reporteo de negocio. Cada una puede ejecutarse de forma independiente sobre los datos cargados en el paso 1.
3. **`03_Funciones.sql`** — Crea las 20 funciones definidas por el usuario (UDFs). Debe ejecutarse antes de `05_Triggers.sql` y `07_Procedimientos_Almacenados.sql`, ya que varios triggers y procedimientos reutilizan estas funciones.
4. **`04_Seguridad.sql`** — Crea las vistas de seguridad, los roles, los usuarios y asigna los permisos (`GRANT`/`REVOKE`) correspondientes.
5. **`05_Triggers.sql`** — Crea la tabla de auditoría de precios (si no existe) y los 20 triggers de integridad y automatización.
6. **`06_Eventos.sql`** — Crea las tablas auxiliares de reporte/log necesarias y los 20 eventos programados (recuerda que requieren `event_scheduler = ON`, que el script activa).
7. **`07_Procedimientos_Almacenados.sql`** — Crea los 20 procedimientos almacenados que orquestan las operaciones transaccionales del sistema.

### Ejemplo de ejecución vía CLI

```bash
mysql -u root -p < 01_Esquema_y_Datos.sql
mysql -u root -p < 02_Consultas_Avanzadas.sql
mysql -u root -p < 03_Funciones.sql
mysql -u root -p < 04_Seguridad.sql
mysql -u root -p < 05_Triggers.sql
mysql -u root -p < 06_Eventos.sql
mysql -u root -p < 07_Procedimientos_Almacenados.sql
```

### Notas importantes

- Todos los scripts son **idempotentes**: usan `DROP ... IF EXISTS` antes de crear cada objeto, por lo que el repositorio completo puede re-ejecutarse desde cero sin errores.
- Las contraseñas de los usuarios creados en `04_Seguridad.sql` son valores de ejemplo (`Cambiar_Esta_Clave_2024!`) y **deben cambiarse** antes de cualquier uso real.
- La línea de `GRANT EXECUTE` sobre `sp_GenerarReporteMensualVentas` en `04_Seguridad.sql` está comentada porque el procedimiento se crea después, en `07_Procedimientos_Almacenados.sql`; debe descomentarse y ejecutarse una vez corrido ese archivo.
- `evt_generate_weekly_sales_report` y otros eventos programados solo se ejecutarán si `event_scheduler` permanece en `ON` en el servidor.

## Estructura del repositorio

```
├── README.md
├── 01_Esquema_y_Datos.sql
├── 02_Consultas_Avanzadas.sql
├── 03_Funciones.sql
├── 04_Seguridad.sql
├── 05_Triggers.sql
├── 06_Eventos.sql
└── 07_Procedimientos_Almacenados.sql
```

## Resumen de contenido

| Archivo | Contenido |
|---|---|
| `01_Esquema_y_Datos.sql` | 7 entidades principales + 20 tablas de soporte/auditoría, con restricciones (`PK`, `FK`, `UNIQUE`, `CHECK`) y datos de ejemplo |
| `02_Consultas_Avanzadas.sql` | 20 consultas SQL de análisis de negocio (ventas, clientes, inventario, RFM, cohortes, etc.) |
| `03_Funciones.sql` | 20 funciones (`fn_...`) para cálculos y validaciones reutilizables |
| `04_Seguridad.sql` | 7 roles, 7 usuarios, vistas de seguridad y permisos `GRANT`/`REVOKE` |
| `05_Triggers.sql` | 20 triggers (21 disparadores, ya que uno de los requisitos se resuelve con 2 triggers INSERT/DELETE) |
| `06_Eventos.sql` | 20 eventos programados de mantenimiento, reporteo y limpieza |
| `07_Procedimientos_Almacenados.sql` | 20 procedimientos almacenados transaccionales |
