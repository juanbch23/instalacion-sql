# Laboratorio 4 · Entorno listo (partes 1 y 2)

Deja listo **en un solo paso** el laboratorio: las bases de la **parte 1 del PDF** (AdventureWorks, STAGE y DWH con todos sus
objetos) y el **ETL de la parte 2** (paquetes SSIS en el catalogo SSISDB + Job de SQL Server Agent), usando **tu** instancia de
SQL Server y **tus** rutas. No tienes que cambiar nada a mano.

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
   6. **ETL (parte 2):** busca una instancia con SQL Server Agent y Integration Services (Developer/Standard; Express no sirve),
      crea el catalogo **SSISDB** si no existe, implementa los proyectos `STAGE_AW` y `DWH_AW` (cambiandoles el servidor por el
      tuyo), crea el Job **`Job_AdventureWorks`** (Stage y luego DWH, todos los dias 02:00), le da al Agent permiso sobre las
      bases y la carpeta `Dim_Fecha`, y **ejecuta el Job una vez** para comprobar que todo carga.
   7. **Solucion de Visual Studio:** deja en `Documentos\AdventureWork\AdventureWork.sln` los 2 proyectos (`STAGE_AW` y `DWH_AW`)
      con todos sus paquetes y las conexiones ya apuntando a **tu** servidor, para abrirlos, verlos y ejecutarlos en Visual Studio.
4. Al terminar muestra las tres bases en `ONLINE`, el resultado del Job y el servidor al que debes conectarte en SSMS.

**Para el ETL necesitas:** SSMS (trae la libreria para crear SSISDB), la caracteristica *Integration Services* de SQL Server y
SQL Server Agent. Si falta algo, el script lo dice y deja las bases restauradas. Opciones: `-SinETL` (solo bases),
`-SinProbarJob` (crea el Job pero no lo ejecuta). Clave maestra del catalogo (si lo crea): `Lab4_SSISDB#2026`.

> **Si Windows no deja ejecutar el `.bat`:** abre PowerShell en la carpeta y escribe
> `powershell -ExecutionPolicy Bypass -File .\restaurar_laboratorio4.ps1`
>
> **Elegir la instancia tú misma:** `.\restaurar_laboratorio4.ps1 -Instancia SQLEXPRESS`
> (o `DEV`, o `MSSQLSERVER` si es la instancia predeterminada). Con `-Simular` solo muestra lo que haría.

## Empezar de cero (`-Nuevo`)
Si los datos quedaron contaminados (por ejemplo, ejecutaste los paquetes maestros desde Visual Studio varias veces o cambiaste algo):

`powershell -ExecutionPolicy Bypass -File .estaurar_laboratorio4.ps1 -Nuevo`

Pide que escribas **SI** y entonces **borra** las 3 bases (`AdventureWorks2016CTP3`, `STAGE_AW`, `DWH_AW`), los paquetes de SSISDB y la solucion de
Documentos, y lo rehace **todo** desde los respaldos (bases, paquetes, Job y solucion de Visual Studio). Con `-Forzar` no pregunta.
Sin `-Nuevo` el script nunca borra nada.

## Notas
- **No pisa nada:** si ya tienes una base con el mismo nombre, la deja como está y lo avisa. Para rehacerla, elimínala en SSMS
  (clic derecho → Eliminar) y ejecuta de nuevo.
- Se puede ejecutar todas las veces que quieras.
- Al restaurar AdventureWorks tarda unos segundos más: es normal.
- Si sale *"Access is denied"*: cierra la ventana y ejecuta el `.bat` con **clic derecho → Ejecutar como administrador**.
- Si prefieres hacerlo a mano en SSMS: `laboratorio4_respaldos/LEEME.md` explica el script `restaurar_laboratorio4.sql`.
- Los paquetes SSIS originales estan en `laboratorio4_etl/` (`.ispac`); el script los adapta a tu servidor al implementarlos.
