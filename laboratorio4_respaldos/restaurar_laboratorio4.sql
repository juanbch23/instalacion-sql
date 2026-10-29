/* =====================================================================
   Laboratorio 4 (Inteligencia de Negocios) - RESTAURAR las bases de la parte 1
   Restaura:  AdventureWorks2016CTP3 (origen), STAGE_AW y DWH_AW.
   Que hace por ti: usa la carpeta de datos de TU instancia (no hay que cambiar rutas como en el PDF),
   no pisa ninguna base que ya tengas y avisa de lo que hizo.

   COMO USARLO
   1) Copia los archivos .bak a una carpeta, por ejemplo  C:\Respaldos\   (el servicio de SQL Server debe poder leerla;
      una carpeta nueva en C:\ sirve. Evita Descargas o el Escritorio).
   2) En SSMS conectate a TU instancia (la que usaras para el laboratorio) y abre este archivo.
   3) Cambia las dos variables de abajo (@Carpeta y, si quieres, @RutaDimFecha) y presiona F5.
   ===================================================================== */
SET NOCOUNT ON;
USE [master];

DECLARE @Carpeta      NVARCHAR(260) = N'C:\Respaldos\';   -- <<< carpeta con los .bak (termina en \)
DECLARE @RutaDimFecha NVARCHAR(400) = N'';                -- <<< opcional: ruta de TU carpeta Dim_Fecha, ej. N'C:\laboratorio4\Dim_Fecha\Dim_Fecha'

-- ---------------------------------------------------------------- carpetas de datos de tu instancia
IF RIGHT(@Carpeta, 1) <> N'\' SET @Carpeta += N'\';
DECLARE @Datos NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));
DECLARE @Logs  NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS NVARCHAR(260));
IF @Datos IS NULL OR @Logs IS NULL
BEGIN RAISERROR('Tu version de SQL Server no informa la carpeta de datos por defecto. Restaura desde SSMS (clic derecho en Bases de datos > Restaurar).', 16, 1); RETURN; END
PRINT 'Instancia: ' + @@SERVERNAME + '   |   Datos: ' + @Datos + '   |   Respaldos: ' + @Carpeta;

DECLARE @bak NVARCHAR(400), @existe INT, @mdf NVARCHAR(400), @ldf NVARCHAR(400), @mod NVARCHAR(400);

-- ================================================================ 1) AdventureWorks2016CTP3 (origen del ETL)
SET @bak = @Carpeta + N'AdventureWorks2016CTP3.bak';
EXEC master.dbo.xp_fileexist @bak, @existe OUTPUT;
IF DB_ID(N'AdventureWorks2016CTP3') IS NOT NULL PRINT 'YA EXISTE - AdventureWorks2016CTP3 ya existe: no se toca.';
ELSE IF @existe <> 1 PRINT 'AVISO - No esta ' + @bak + ' (el .bak que dio el profesor): se omite AdventureWorks2016CTP3.';
ELSE
BEGIN
    SET @mdf = @Datos + N'AdventureWorks2016CTP3_Data.mdf';
    SET @ldf = @Logs  + N'AdventureWorks2016CTP3_Log.ldf';
    SET @mod = @Datos + N'AdventureWorks2016CTP3_mod';
    RESTORE DATABASE [AdventureWorks2016CTP3] FROM DISK = @bak
        WITH MOVE N'AdventureWorks2016CTP3_Data' TO @mdf, MOVE N'AdventureWorks2016CTP3_Log' TO @ldf,
             MOVE N'AdventureWorks2016CTP3_mod' TO @mod, STATS = 25;
    PRINT 'LISTO - AdventureWorks2016CTP3 restaurada.';
END

-- ================================================================ 2) STAGE_AW
SET @bak = @Carpeta + N'STAGE_AW.bak';
EXEC master.dbo.xp_fileexist @bak, @existe OUTPUT;
IF DB_ID(N'STAGE_AW') IS NOT NULL PRINT 'YA EXISTE - STAGE_AW ya existe: no se toca.';
ELSE IF @existe <> 1 PRINT 'AVISO - No esta ' + @bak + ': se omite STAGE_AW.';
ELSE
BEGIN
    SET @mdf = @Datos + N'STAGE_AW.mdf';
    SET @ldf = @Logs  + N'STAGE_AW_log.ldf';
    RESTORE DATABASE [STAGE_AW] FROM DISK = @bak WITH MOVE N'STAGE_AW' TO @mdf, MOVE N'STAGE_AW_log' TO @ldf, STATS = 25;
    PRINT 'LISTO - STAGE_AW restaurada.';
END

-- ================================================================ 3) DWH_AW
SET @bak = @Carpeta + N'DWH_AW.bak';
EXEC master.dbo.xp_fileexist @bak, @existe OUTPUT;
IF DB_ID(N'DWH_AW') IS NOT NULL PRINT 'YA EXISTE - DWH_AW ya existe: no se toca.';
ELSE IF @existe <> 1 PRINT 'AVISO - No esta ' + @bak + ': se omite DWH_AW.';
ELSE
BEGIN
    SET @mdf = @Datos + N'DWH_AW.mdf';
    SET @ldf = @Logs  + N'DWH_AW_log.ldf';
    RESTORE DATABASE [DWH_AW] FROM DISK = @bak WITH MOVE N'DWH_AW' TO @mdf, MOVE N'DWH_AW_log' TO @ldf, STATS = 25;
    PRINT 'LISTO - DWH_AW restaurada.';
END

-- ================================================================ 4) ruta del archivo Dim_Fecha (es la unica cosa propia de cada PC)
IF DB_ID(N'DWH_AW') IS NOT NULL AND @RutaDimFecha <> N''
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'UPDATE [DWH_AW].[dbo].[PATH_FILE] SET [RUTA] = @r WHERE [TableName] = N''[GENERICO].[DimFecha]'';';
    EXEC sp_executesql @sql, N'@r NVARCHAR(400)', @r = @RutaDimFecha;
    PRINT 'LISTO - PATH_FILE actualizada: ' + @RutaDimFecha;
END
ELSE IF DB_ID(N'DWH_AW') IS NOT NULL
    PRINT 'AVISO - Recuerda: DWH_AW.dbo.PATH_FILE trae la ruta de otro PC. Escribe tu ruta en @RutaDimFecha y vuelve a ejecutar, o usa UPDATE a mano.';

-- ================================================================ 5) comprobacion rapida
SELECT d.name AS BaseDeDatos, d.state_desc AS Estado, d.create_date AS Creada
  FROM sys.databases d WHERE d.name IN (N'AdventureWorks2016CTP3', N'STAGE_AW', N'DWH_AW') ORDER BY d.name;
IF DB_ID(N'STAGE_AW') IS NOT NULL
    SELECT N'STAGE_AW' AS BaseDeDatos, COUNT(DISTINCT t.object_id) AS Tablas, SUM(p.rows) AS FilasEnTotal
      FROM [STAGE_AW].sys.tables t JOIN [STAGE_AW].sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1);
IF DB_ID(N'DWH_AW') IS NOT NULL
    SELECT N'DWH_AW' AS BaseDeDatos, COUNT(DISTINCT t.object_id) AS Tablas, SUM(p.rows) AS FilasEnTotal
      FROM [DWH_AW].sys.tables t JOIN [DWH_AW].sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1);
