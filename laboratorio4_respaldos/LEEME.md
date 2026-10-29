# Laboratorio 4 — bases de datos listas para restaurar (parte 1)

> **Forma automática:** en la carpeta principal del repositorio, doble clic en `restaurar_laboratorio4.bat`: hace todo lo de abajo solo.
> Esta guía es la **forma manual** (con SSMS), por si prefieres hacerlo paso a paso.

Con esto no tienes que hacer a mano la **parte 1 del PDF** (restaurar AdventureWorks, crear STAGE y DWH y todos sus
objetos): restauras tres respaldos con un solo script y listo.

## Qué trae
| Archivo | Qué es |
|---|---|
| `AdventureWorks2016CTP3.bak` | La base de origen del laboratorio (el `.bak` original del profesor) |
| `STAGE_AW.bak` | Base **STAGE_AW**: tablas, procedimientos y los datos del ETL ya cargados (9 tablas, ~185 mil filas) |
| `DWH_AW.bak` | Base **DWH_AW**: dimensiones, hechos, tablas de error y auditoría (9 tablas, ~166 mil filas) |
| `restaurar_laboratorio4.sql` | Script que restaura las tres bases en **tu** instancia, sin tocar rutas |

> Las bases vienen **tal como quedaron después de hacer el laboratorio** (con los datos del ETL cargados).
> **No** incluyen los paquetes SSIS (la parte 2 del PDF).

## Requisito importante
Tu SQL Server debe ser **2025 (17.x)** o más nuevo. Un respaldo de SQL Server 2025 **no se puede restaurar en 2022 ni anteriores**.
Se prueba así (en SSMS): `SELECT @@VERSION;` debe decir *SQL Server 2025*.

## Cómo restaurar (5 minutos)
1. Crea la carpeta **`C:\Respaldos`** y copia ahí los cuatro archivos `.bak` y el `.sql`.
   (Usa una carpeta en `C:\`, no Descargas ni el Escritorio: el servicio de SQL Server tiene que poder leerla.)
2. Abre **SSMS**, conéctate a **tu instancia** (por ejemplo `TU_PC\SQLEXPRESS` o `TU_PC\DEV`) con Autenticación de Windows.
   Si pide certificado, marca **Confiar en el certificado del servidor**.
3. **Archivo → Abrir → Archivo…** y elige `restaurar_laboratorio4.sql`.
4. Revisa las dos variables del inicio:
   ```sql
   DECLARE @Carpeta      NVARCHAR(260) = N'C:\Respaldos\';   -- donde copiaste los .bak
   DECLARE @RutaDimFecha NVARCHAR(400) = N'';                -- opcional, mira el paso 5
   ```
5. Presiona **F5**. Al terminar verás: `LISTO - … restaurada` por cada base y una tabla final con las tres bases en `ONLINE`.

**Resultado esperado:** `AdventureWorks2016CTP3`, `STAGE_AW` y `DWH_AW` en el Explorador de objetos
(clic derecho en *Bases de datos → Actualizar*).

## Lo único que depende de tu PC: la ruta de Dim_Fecha
`DWH_AW.dbo.PATH_FILE` guarda la carpeta del archivo `Dim_Fecha` que usa el ETL. En el respaldo trae la ruta de **mi** PC.
Ponla en `@RutaDimFecha` antes de ejecutar (por ejemplo `N'C:\laboratorio4\Dim_Fecha\Dim_Fecha'`), o corrígela después:
```sql
UPDATE DWH_AW.dbo.PATH_FILE SET RUTA = N'C:\laboratorio4\Dim_Fecha\Dim_Fecha' WHERE TableName = N'[GENERICO].[DimFecha]';
```

## Notas
- **No pisa nada:** si ya tienes una base con el mismo nombre, el script la deja como está y lo avisa (`YA EXISTE - …`).
  Para rehacerla, bórrala antes en SSMS (clic derecho → Eliminar) y vuelve a ejecutar.
- Al restaurar AdventureWorks salen **muchas líneas** de "paso de actualización de la versión…": es normal (la base es de 2016).
- Si sale *"Access is denied" / error del sistema operativo 5*: la carpeta de los `.bak` no es legible por el servicio de SQL Server;
  muévelos a `C:\Respaldos` o a la carpeta `Backup` de tu instancia.
- Si en tu SQL Server la carpeta de datos no se detecta, restaura con SSMS: clic derecho en *Bases de datos → Restaurar base de datos…* (como indica el PDF).
- Para conectarte desde los paquetes SSIS usa el nombre de **tu** servidor (en el PDF aparece el del autor).
