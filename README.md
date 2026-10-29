# Laboratorio 4 · Bases de datos listas (parte 1)

Restaura **en un solo paso** las bases de la **parte 1 del PDF** (restaurar AdventureWorks, crear STAGE y DWH con todos sus
objetos), usando **tu** instancia de SQL Server y **tus** rutas. No tienes que cambiar nada a mano.

| Se restaura | Qué es |
|---|---|
| `AdventureWorks2016CTP3` | Base de origen del laboratorio (el `.bak` original del profesor) |
| `STAGE_AW` | Tablas y procedimientos del Stage (con los datos del ETL ya cargados) |
| `DWH_AW` | Dimensiones, hechos, tablas de error y auditoría |

## Antes de empezar
- **SQL Server 2025** instalado y **encendido** (Developer o Express). Un respaldo de 2025 **no** se restaura en 2022 ni anteriores.
  Se comprueba en SSMS con `SELECT @@VERSION;`
- Entrar a Windows con el **mismo usuario que instaló SQL Server** (el que es administrador de la instancia).
- Unos **400 MB** libres en el disco.

## Cómo usarlo
1. Descarga este repositorio:
   - con Git: `git clone https://github.com/juanbch23/instalacion-sql.git`
   - o sin Git: en GitHub, botón verde **Code → Download ZIP**, y descomprímelo.
2. Entra a la carpeta y haz **doble clic en `restaurar_laboratorio4.bat`**.
3. El script:
   1. detecta tus instancias de SQL Server 2025 encendidas (si hay varias, te deja elegir una),
   2. comprueba que eres administrador,
   3. le da permiso de lectura al servicio de SQL Server sobre la carpeta del repositorio,
   4. restaura las tres bases en la carpeta de datos de **tu** instancia,
   5. deja la ruta de `Dim_Fecha` apuntando a la copia que viene en este repositorio.
4. Al terminar muestra las tres bases en `ONLINE` y el nombre del servidor al que debes conectarte en SSMS.

> **Si Windows no deja ejecutar el `.bat`:** abre PowerShell en la carpeta y escribe
> `powershell -ExecutionPolicy Bypass -File .\restaurar_laboratorio4.ps1`
>
> **Elegir la instancia tú misma:** `.\restaurar_laboratorio4.ps1 -Instancia SQLEXPRESS`
> (o `DEV`, o `MSSQLSERVER` si es la instancia predeterminada). Con `-Simular` solo muestra lo que haría.

## Notas
- **No pisa nada:** si ya tienes una base con el mismo nombre, la deja como está y lo avisa. Para rehacerla, elimínala en SSMS
  (clic derecho → Eliminar) y ejecuta de nuevo.
- Se puede ejecutar todas las veces que quieras.
- Al restaurar AdventureWorks tarda unos segundos más: es normal.
- Si sale *"Access is denied"*: cierra la ventana y ejecuta el `.bat` con **clic derecho → Ejecutar como administrador**.
- Si prefieres hacerlo a mano en SSMS: `laboratorio4_respaldos/LEEME.md` explica el script `restaurar_laboratorio4.sql`.
- Lo que **no** incluye: los paquetes SSIS (la parte 2 del PDF). En ellos usa el nombre de **tu** servidor, el que muestra el script al final.
