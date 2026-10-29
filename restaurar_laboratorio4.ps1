<#
.SYNOPSIS
  Restaura el laboratorio 4 (AdventureWorks2016CTP3, STAGE_AW y DWH_AW) en TU instancia de SQL Server, con TUS rutas.

.DESCRIPTION
  1) Detecta tus instancias de SQL Server 2025 que estan encendidas (si hay varias, te deja elegir).
  2) Comprueba que tu usuario de Windows es administrador de esa instancia.
  3) Le da permiso de lectura al servicio de SQL Server sobre la carpeta de este repositorio (para que lea los .bak).
  4) Restaura las tres bases usando la carpeta de datos de tu instancia (no hay que cambiar rutas) y deja la ruta de
     Dim_Fecha apuntando a la copia que viene en este repositorio.
  No pisa ninguna base que ya tengas con el mismo nombre.

.EXAMPLE
  .\restaurar_laboratorio4.ps1                       # detecta todo solo
  .\restaurar_laboratorio4.ps1 -Instancia SQLEXPRESS # usa esa instancia
  .\restaurar_laboratorio4.ps1 -Instancia DEV -Simular
#>
[CmdletBinding()]
param(
    [string]$Instancia = '',     # nombre de la instancia (DEV, SQLEXPRESS, MSSQLSERVER para la predeterminada...)
    [switch]$Simular,            # solo muestra lo que haria
    [switch]$Nuevo,              # borra las 3 bases, los paquetes y el Job y lo rehace TODO desde cero (pide confirmacion)
    [switch]$Forzar,             # con -Nuevo: no pide confirmacion
    [switch]$SinETL,             # solo restaura las bases (no despliega los paquetes SSIS ni crea el Job)
    [switch]$SinProbarJob,       # despliega y crea el Job pero no lo ejecuta una vez
    [string]$ClaveSSISDB = 'Lab4_SSISDB#2026',   # clave maestra del catalogo SSISDB (solo si hay que crearlo)
    [string]$CarpetaSSIS = 'AdventureWork',      # carpeta del catalogo SSISDB
    [string]$NombreJob   = 'Job_AdventureWorks'
)

$ErrorActionPreference = 'Stop'
$Equipo    = $env:COMPUTERNAME
$Respaldos = Join-Path $PSScriptRoot 'laboratorio4_respaldos'
$ScriptSql = Join-Path $Respaldos 'restaurar_laboratorio4.sql'
$RutaFecha = Join-Path $Respaldos 'Dim_Fecha'

function Titulo($t) { Write-Host ''; Write-Host ('=' * 74) -ForegroundColor DarkCyan; Write-Host "  $t" -ForegroundColor Cyan; Write-Host ('=' * 74) -ForegroundColor DarkCyan }
function Info($t)   { Write-Host "  $t" }
function Ok($t)     { Write-Host "  [OK] $t" -ForegroundColor Green }
function Aviso($t)  { Write-Host "  [!]  $t" -ForegroundColor Yellow }

function Get-Instancias {
    $lista = @()
    $k = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    if (-not (Test-Path $k)) { return $lista }
    foreach ($p in (Get-ItemProperty $k).PSObject.Properties) {
        if ($p.Name -like 'PS*') { continue }
        $s = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$($p.Value)\Setup" -ErrorAction SilentlyContinue
        $servicio = if ($p.Name -eq 'MSSQLSERVER') { 'MSSQLSERVER' } else { 'MSSQL$' + $p.Name }
        $svc = Get-Service -Name $servicio -ErrorAction SilentlyContinue
        $ver = if ($s -and $s.Version) { [string]$s.Version } else { '0' }
        $lista += [pscustomobject]@{
            Nombre  = $p.Name
            Mayor   = [int]($ver.Split('.')[0])
            Version = $ver
            Edicion = $(if ($s -and $s.Edition) { [string]$s.Edition } else { '' })
            Estado  = $(if ($svc) { [string]$svc.Status } else { 'sin servicio' })
        }
    }
    return $lista
}

function Abrir-Conexion($nombre) {
    $destinos = if ($nombre -eq 'MSSQLSERVER') { @("lpc:$Equipo", $Equipo, 'localhost') }
                else { @("lpc:$Equipo\$nombre", "$Equipo\$nombre", "localhost\$nombre") }
    $ultimo = $null
    foreach ($d in $destinos) {
        try {
            $cn = New-Object System.Data.SqlClient.SqlConnection "Server=$d;Database=master;Integrated Security=SSPI;Connect Timeout=15;TrustServerCertificate=True"
            $cn.Open()
            return $cn
        } catch { $ultimo = $_.Exception.Message }
    }
    throw "No se pudo conectar a la instancia '$nombre': $ultimo"
}

function Consulta($cn, $sql) {
    $cmd = $cn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 60
    $t = New-Object System.Data.DataTable; $t.Load($cmd.ExecuteReader()); return ,$t
}

# ------------------------------------------------------------------------------------------------ comprobaciones previas
Titulo 'Laboratorio 4: restaurar bases de datos (parte 1)'
foreach ($f in @('AdventureWorks2016CTP3.bak', 'STAGE_AW.bak', 'DWH_AW.bak', 'restaurar_laboratorio4.sql')) {
    if (-not (Test-Path (Join-Path $Respaldos $f))) { throw "Falta el archivo $f en $Respaldos. Descarga de nuevo el repositorio completo." }
}
Ok "Archivos del laboratorio encontrados en: $Respaldos"

# ------------------------------------------------------------------------------------------------ 1. instancia
Titulo '1. Tu instancia de SQL Server'
$todas = @(Get-Instancias)
if ($todas.Count -eq 0) { throw 'No se encontro ninguna instancia de SQL Server en este equipo. Instala SQL Server 2025 y vuelve a ejecutar.' }
foreach ($i in $todas) {
    $ann = switch ($i.Mayor) { 17 { '2025' } 16 { '2022' } 15 { '2019' } 14 { '2017' } 13 { '2016' } default { "v$($i.Mayor)" } }
    Info ("{0,-16} SQL Server {1}  {2}  [{3}]" -f $i.Nombre, $ann, $i.Edicion, $i.Estado)
}
if ($Instancia) {
    $elegida = $todas | Where-Object { $_.Nombre -ieq $Instancia } | Select-Object -First 1
    if (-not $elegida) { throw "No existe la instancia '$Instancia'. Las que hay son: $(($todas | ForEach-Object { $_.Nombre }) -join ', ')" }
    if ($elegida.Mayor -lt 17) { throw "La instancia '$($elegida.Nombre)' es SQL Server $($elegida.Version): un respaldo de SQL Server 2025 solo se puede restaurar en 2025 o mas nuevo." }
    if ($elegida.Estado -ne 'Running') { throw "La instancia '$($elegida.Nombre)' esta '$($elegida.Estado)'. Enciendela (services.msc) y vuelve a ejecutar." }
} else {
    $validas = @($todas | Where-Object { $_.Mayor -ge 17 -and $_.Estado -eq 'Running' })
    if ($validas.Count -eq 0) {
        throw 'No hay ninguna instancia de SQL Server 2025 encendida. Los respaldos son de SQL Server 2025 y no se pueden restaurar en versiones anteriores. Enciende o instala una instancia 2025.'
    } elseif ($validas.Count -eq 1) {
        $elegida = $validas[0]
        Ok "Se usara la unica instancia valida: $($elegida.Nombre)"
    } else {
        Write-Host ''; Info 'Hay varias instancias de SQL Server 2025 encendidas. Elige una:'
        for ($n = 0; $n -lt $validas.Count; $n++) { Info ("   {0}) {1}   ({2})" -f ($n + 1), $validas[$n].Nombre, $validas[$n].Edicion) }
        do { $r = Read-Host '  Numero' } until ($r -match '^\d+$' -and [int]$r -ge 1 -and [int]$r -le $validas.Count)
        $elegida = $validas[[int]$r - 1]
    }
}
$servidor = if ($elegida.Nombre -eq 'MSSQLSERVER') { $Equipo } else { "$Equipo\$($elegida.Nombre)" }
Info "Servidor: $servidor"
if ($Simular) { Aviso 'MODO SIMULACION: se muestra lo que se haria y no se cambia nada.' }

# ------------------------------------------------------------------------------------------------ 2. conexion y permisos
Titulo '2. Conexion y permisos'
$cn = Abrir-Conexion $elegida.Nombre
try {
    $esAdmin = [int](Consulta $cn "SELECT IS_SRVROLEMEMBER('sysadmin') AS v").Rows[0].v
    $usuario = [string](Consulta $cn 'SELECT SUSER_SNAME() AS v').Rows[0].v
    if ($esAdmin -ne 1) {
        throw "Tu usuario ($usuario) no es administrador (sysadmin) de $servidor. Ejecuta el script con el usuario de Windows que instalo SQL Server, o agregate como administrador."
    }
    Ok "Conectado a $servidor como $usuario (administrador)"

    $cuenta = [string](Consulta $cn "SELECT TOP 1 service_account AS v FROM sys.dm_server_services WHERE servicename LIKE 'SQL Server (%'").Rows[0].v
    Info "El servicio de SQL Server corre como: $cuenta"

    $carpetaBak = $Respaldos
    if ($Simular) { Info "Se daria permiso de lectura a '$cuenta' sobre $carpetaBak" }
    else {
        & icacls $carpetaBak /grant ($cuenta + ':(OI)(CI)RX') | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Aviso 'No se pudo dar permiso en la carpeta del repositorio; se copian los respaldos a C:\Respaldos_Lab4.'
            $carpetaBak = 'C:\Respaldos_Lab4'
            New-Item -ItemType Directory -Force $carpetaBak | Out-Null
            Copy-Item -Path (Join-Path $Respaldos '*') -Destination $carpetaBak -Recurse -Force
            & icacls $carpetaBak /grant ($cuenta + ':(OI)(CI)RX') | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'No se pudo dar permiso de lectura al servicio de SQL Server. Cierra y vuelve a abrir el script con "Ejecutar como administrador".' }
        }
        Ok "El servicio de SQL Server puede leer: $carpetaBak"
    }
    $rutaFechaFinal = Join-Path $carpetaBak 'Dim_Fecha'

    # ------------------------------------------------------------------------------------------ 2b. -Nuevo: empezar de cero
    if ($Nuevo) {
        Titulo 'Empezar de cero (-Nuevo)'
        Aviso "Se van a BORRAR en $servidor las bases AdventureWorks2016CTP3, STAGE_AW y DWH_AW (con todos sus datos), los paquetes de SSISDB\$CarpetaSSIS y el Job $NombreJob. Despues se rehace todo desde los respaldos."
        if ($Simular) { Info 'Simulacion: no se borra nada.' }
        else {
            if (-not $Forzar) { $r = Read-Host '  Escribe SI para continuar'; if ($r -ne 'SI') { throw 'Cancelado: no se borro nada.' } }
            foreach ($bd in 'DWH_AW', 'STAGE_AW', 'AdventureWorks2016CTP3') {
                [void](Consulta $cn "IF DB_ID(N'$bd') IS NOT NULL BEGIN ALTER DATABASE [$bd] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$bd]; END; SELECT 1 AS v")
                Ok "Base $bd borrada (si existia)."
            }
            $script:LimpiarCatalogo = $true
        }
    }

    # ------------------------------------------------------------------------------------------ 3. restauracion
    Titulo '3. Restauracion'
    $sql = Get-Content -Path $ScriptSql -Raw -Encoding UTF8
    $comillas = { param($t) $t.Replace("'", "''") }
    $sql = [regex]::Replace($sql, "(DECLARE @Carpeta\s+NVARCHAR\(260\) = N')[^']*(';)",
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + (& $comillas ($carpetaBak.TrimEnd('\') + '\')) + $m.Groups[2].Value })
    $sql = [regex]::Replace($sql, "(DECLARE @RutaDimFecha\s+NVARCHAR\(400\) = N')[^']*(';)",
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + (& $comillas $rutaFechaFinal) + $m.Groups[2].Value })
    Info "Carpeta de respaldos : $carpetaBak"
    Info "Carpeta Dim_Fecha    : $rutaFechaFinal"
    if ($Simular) {
        Info 'Se restaurarian AdventureWorks2016CTP3, STAGE_AW y DWH_AW (las que no existan).'
        if (-not $SinETL) { Info "Despues se desplegarian los paquetes SSIS en SSISDB (carpeta $CarpetaSSIS) y se crearia el Job $NombreJob." }
        return
    }

    Info 'Restaurando (AdventureWorks tarda un poco: tiene muchos pasos de actualizacion)...'
    $silenciar = 'percent processed|por ciento procesado|upgrade step|paso de actualiz|Converting database|Convirtiendo la base'
    $cn.FireInfoMessageEventOnUserErrors = $false
    $cn.add_InfoMessage([System.Data.SqlClient.SqlInfoMessageEventHandler]{
        param($s, $e)
        foreach ($m in $e.Errors) { if ($m.Message -notmatch $silenciar) { Write-Host ("    " + $m.Message) -ForegroundColor Gray } }
    })
    $cmd = $cn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 0
    $ds = New-Object System.Data.DataSet
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $cmd).Fill($ds)
    foreach ($t in $ds.Tables) {
        if ($t.Rows.Count) { Write-Host ''; $t.Rows | Select-Object -Property ($t.Columns | ForEach-Object { $_.ColumnName }) | Format-Table -AutoSize | Out-String | Write-Host }
    }

    # ------------------------------------------------------------------------------------------ 4. comprobacion
    Titulo '4. Listo'
    $bds = Consulta $cn "SELECT name, state_desc FROM sys.databases WHERE name IN (N'AdventureWorks2016CTP3', N'STAGE_AW', N'DWH_AW') ORDER BY name"
    $faltan = @('AdventureWorks2016CTP3', 'STAGE_AW', 'DWH_AW') | Where-Object { $_ -notin @($bds.Rows | ForEach-Object { $_.name }) }
    foreach ($r in $bds.Rows) { Ok "$($r.name): $($r.state_desc)" }
    if ($faltan) { Aviso "No quedaron restauradas: $($faltan -join ', ')" }
    Write-Host ''
    Info "Conectate en SSMS a:  $servidor   (Autenticacion de Windows; si pide certificado, marca 'Confiar en el certificado del servidor')"
    if ($faltan) { return }

    # ------------------------------------------------------------------------------------------ 5. ETL (parte 2)
    if ($SinETL) { Info 'ETL omitido (-SinETL).'; return }
    Titulo '5. ETL: paquetes SSIS en SSISDB + Job'
    $ErrorActionPreference = 'Continue'
    try {
        # 5.1 instancia con Integration Services, SQL Server Agent y edicion que no sea Express
        $hayIS = [bool](Get-Service -Name 'MsDtsServer*' -ErrorAction SilentlyContinue)
        $cands = @($elegida) + @($todas | Where-Object { $_.Nombre -ne $elegida.Nombre -and $_.Mayor -ge 17 -and $_.Estado -eq 'Running' })
        $etl = $null
        foreach ($c in $cands) {
            $svcA = if ($c.Nombre -eq 'MSSQLSERVER') { 'SQLSERVERAGENT' } else { 'SQLAgent$' + $c.Nombre }
            if ($c.Edicion -match 'Express' -or -not (Get-Service -Name $svcA -ErrorAction SilentlyContinue)) { continue }
            $etl = [pscustomobject]@{ Inst = $c; Agente = $svcA }; break
        }
        if (-not $hayIS) { Aviso 'No se encontro el servicio de Integration Services (MsDtsServer*): instala la caracteristica "Integration Services" y vuelve a ejecutar.'; return }
        if (-not $etl)   { Aviso 'Ninguna instancia encendida tiene SQL Server Agent y edicion Developer/Standard/Enterprise (Express no tiene catalogo SSISDB ni Agent). Las bases quedaron restauradas; el ETL no se pudo desplegar.'; return }
        $servEtl = if ($etl.Inst.Nombre -eq 'MSSQLSERVER') { $Equipo } else { "$Equipo\$($etl.Inst.Nombre)" }
        Ok "Instancia para el ETL: $servEtl  ($($etl.Inst.Edicion))"

        # 5.2 SQL Server Agent encendido
        $sa = Get-Service -Name $etl.Agente
        if ($sa.Status -ne 'Running') {
            try { Start-Service -Name $etl.Agente -ErrorAction Stop; Start-Sleep 5; Ok 'SQL Server Agent encendido.' }
            catch { Aviso "No se pudo encender SQL Server Agent ($($etl.Agente)). Enciendelo en services.msc o ejecuta este script como administrador."; return }
        }

        $cnE = if ($etl.Inst.Nombre -eq $elegida.Nombre) { $cn } else { Abrir-Conexion $etl.Inst.Nombre }
        try {
            if ([int](Consulta $cnE "SELECT IS_SRVROLEMEMBER('sysadmin') AS v").Rows[0].v -ne 1) { Aviso "No eres administrador de $servEtl."; return }
            $ctaAgente = [string](Get-CimInstance Win32_Service -Filter "Name='$($etl.Agente.Replace('$', '$'))'" -ErrorAction SilentlyContinue).StartName
            if (-not $ctaAgente) { Aviso 'No se pudo saber la cuenta de SQL Server Agent.'; return }
            Info "SQL Server Agent corre como: $ctaAgente"

            # 5.3 permisos del Agent: leer Dim_Fecha y, si las bases estan en otra instancia, usarlas
            & icacls $rutaFechaFinal /grant ($ctaAgente + ':(OI)(CI)RX') | Out-Null
            if ($LASTEXITCODE -ne 0) { Aviso "No se pudo dar permiso de lectura a $ctaAgente sobre $rutaFechaFinal." } else { Ok 'El Agent puede leer la carpeta Dim_Fecha.' }
            if ($etl.Inst.Nombre -ne $elegida.Nombre) {
                $q = $ctaAgente.Replace("'", "''")
                [void](Consulta $cn "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$q') CREATE LOGIN [$ctaAgente] FROM WINDOWS; SELECT 1 AS v")
                foreach ($bd in @(@('AdventureWorks2016CTP3', 'db_datareader'), @('STAGE_AW', 'db_owner'), @('DWH_AW', 'db_owner'))) {
                    [void](Consulta $cn "USE [$($bd[0])]; IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$q') CREATE USER [$ctaAgente] FOR LOGIN [$ctaAgente]; ALTER ROLE [$($bd[1])] ADD MEMBER [$ctaAgente]; SELECT 1 AS v")
                }
                Ok "El Agent de $servEtl tiene acceso a las bases de $servidor."
            }

            # 5.4 DLL de administracion de SSIS (vienen con SSMS)
            $raices = @('C:\Program Files\Microsoft SQL Server Management Studio*', 'C:\Program Files (x86)\Microsoft SQL Server Management Studio*',
                        'C:\Program Files\Microsoft Visual Studio\*\*\Common7\IDE', 'C:\Program Files (x86)\Microsoft Visual Studio\*\*\Common7\IDE',
                        'C:\Program Files\Microsoft SQL Server\*\SDK\Assemblies', 'C:\Program Files (x86)\Microsoft SQL Server\*\SDK\Assemblies')
            $dlls = @()
            foreach ($r in $raices) {
                foreach ($d in @(Get-ChildItem $r -Directory -ErrorAction SilentlyContinue)) {
                    $dlls += Get-ChildItem $d.FullName -Recurse -Filter 'Microsoft.SqlServer.Management.IntegrationServices.dll' -ErrorAction SilentlyContinue
                }
                $dlls += Get-ChildItem $r -Filter 'Microsoft.SqlServer.Management.IntegrationServices.dll' -ErrorAction SilentlyContinue
            }
            # preferir la version 170 (SQL Server 2025) y la mas reciente
            $dllIS = $dlls | Sort-Object @{ e = { $_.FullName -match '[\\/]170[\\/]' }; Descending = $true }, @{ e = { $_.LastWriteTime }; Descending = $true } | Select-Object -First 1
            if (-not $dllIS) {
                Aviso 'No se encontro la libreria de Integration Services en SSMS, Visual Studio ni SQL Server. Se instala SSMS automaticamente (winget)...'
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    & winget install --id Microsoft.SQLServerManagementStudio.22 -e --silent --accept-package-agreements --accept-source-agreements
                    foreach ($r in $raices) { $dlls += Get-ChildItem $r -Recurse -Filter 'Microsoft.SqlServer.Management.IntegrationServices.dll' -ErrorAction SilentlyContinue }
                    $dllIS = $dlls | Select-Object -First 1
                }
                if (-not $dllIS) { Aviso 'No se pudo instalar SSMS solo. Instala SSMS (https://aka.ms/ssms/22/release/vs_SSMS.exe) y vuelve a ejecutar el script.'; return }
            }
            Info "Libreria de SSIS: $($dllIS.FullName)"
            $carpetas = @($dllIS.DirectoryName)
            $padre = $dllIS.Directory
            for ($n = 0; $n -lt 6 -and $padre; $n++) { $carpetas += $padre.FullName; $padre = $padre.Parent }
            $script:probe = $carpetas | Select-Object -Unique
            [AppDomain]::CurrentDomain.add_AssemblyResolve({
                param($s, $e)
                $n = ($e.Name -split ',')[0] + '.dll'
                foreach ($d in $script:probe) { $p = Join-Path $d $n; if (Test-Path $p) { return [Reflection.Assembly]::LoadFrom($p) } }
                return $null
            })
            $asmIS = [Reflection.Assembly]::LoadFrom($dllIS.FullName)
            $usaMDS = [bool]($asmIS.GetReferencedAssemblies() | Where-Object { $_.Name -eq 'Microsoft.Data.SqlClient' })
            if ($usaMDS) {
                $mds = $script:probe | ForEach-Object { Join-Path $_ 'Microsoft.Data.SqlClient.dll' } | Where-Object { Test-Path $_ } | Select-Object -First 1
                if (-not $mds) {   # buscar en la carpeta IDE de SSMS / Visual Studio y en las demas ubicaciones
                    $ideDir = $dllIS.Directory; while ($ideDir -and $ideDir.Name -ne 'IDE') { $ideDir = $ideDir.Parent }
                    $buscar = @(); if ($ideDir) { $buscar += $ideDir.FullName }; $buscar += @(Get-ChildItem $raices -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
                    foreach ($b in $buscar) {
                        $mds = (Get-ChildItem $b -Recurse -Filter 'Microsoft.Data.SqlClient.dll' -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
                        if ($mds) { break }
                    }
                }
                if (-not $mds) { throw 'No se encontro Microsoft.Data.SqlClient.dll (viene con SSMS). Instala SSMS y vuelve a ejecutar.' }
                $script:probe = @($script:probe) + (Split-Path $mds)
                [void][Reflection.Assembly]::LoadFrom($mds)
            }
            $tipoCn = if ($usaMDS) { 'Microsoft.Data.SqlClient.SqlConnection' } else { 'System.Data.SqlClient.SqlConnection' }

            # 5.5 catalogo SSISDB y carpeta
            [void](Consulta $cnE "EXEC sp_configure 'clr enabled', 1; RECONFIGURE; SELECT 1 AS v")
            $cm = New-Object $tipoCn "Data Source=$servEtl;Initial Catalog=master;Integrated Security=SSPI;TrustServerCertificate=True"
            $cm.Open()
            try {
                $ssis = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $cm
                $cat = $ssis.Catalogs['SSISDB']
                if (-not $cat) {
                    $cat = New-Object Microsoft.SqlServer.Management.IntegrationServices.Catalog($ssis, 'SSISDB', $ClaveSSISDB)
                    $cat.Create(); Ok "Catalogo SSISDB creado (clave maestra: $ClaveSSISDB)"
                } else { Ok 'Catalogo SSISDB ya existia.' }
                if ($script:LimpiarCatalogo) {
                    $cf = $CarpetaSSIS.Replace("'", "''")
                    foreach ($pj in 'STAGE_AW', 'DWH_AW') {
                        [void](Consulta $cnE "IF EXISTS (SELECT 1 FROM SSISDB.catalog.projects p JOIN SSISDB.catalog.folders f ON f.folder_id = p.folder_id WHERE f.name = N'$cf' AND p.name = N'$pj') EXEC SSISDB.catalog.delete_project N'$cf', N'$pj'; SELECT 1 AS v")
                    }
                    [void](Consulta $cnE "IF EXISTS (SELECT 1 FROM SSISDB.catalog.folders WHERE name = N'$cf') EXEC SSISDB.catalog.delete_folder N'$cf'; SELECT 1 AS v")
                    $cat.Folders.Refresh()
                    if (Test-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AdventureWork')) { Remove-Item (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AdventureWork') -Recurse -Force -ErrorAction SilentlyContinue }
                    Ok 'Paquetes anteriores de SSISDB y solucion de Documentos borrados.'
                }
                $fol = $cat.Folders[$CarpetaSSIS]
                if (-not $fol) {
                    $fol = New-Object Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder($cat, $CarpetaSSIS, 'Solucion AdventureWork')
                    $fol.Create(); Ok "Carpeta $CarpetaSSIS creada."
                }

                # 5.6 paquetes: se les cambia el servidor por el de ESTA maquina y se implementan
                Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
                foreach ($p in 'STAGE_AW', 'DWH_AW') {
                    $tmp = Join-Path $env:TEMP "$p.lab4.ispac"
                    Copy-Item (Join-Path $PSScriptRoot "laboratorio4_etl\$p.ispac") $tmp -Force
                    $zip = [IO.Compression.ZipFile]::Open($tmp, 'Update')
                    try {
                        # el servidor esta en las conexiones del proyecto (.conmgr), en el manifiesto y dentro de algunos paquetes (.dtsx)
                        foreach ($en in @($zip.Entries | Where-Object { $_.Name -match '\.(conmgr|dtsx|manifest)$' })) {
                            $sr = New-Object IO.StreamReader($en.Open()); $txt = $sr.ReadToEnd(); $sr.Close()
                            $txtNuevo = $txt.Replace('LAPTOP-IO596P6A\SQLEXPRESS', $servidor)
                            if ($txtNuevo -eq $txt) { continue }
                            $nombre = $en.FullName; $en.Delete()
                            $ne = $zip.CreateEntry($nombre); $sw = New-Object IO.StreamWriter($ne.Open(), (New-Object Text.UTF8Encoding($false))); $sw.Write($txtNuevo); $sw.Close()
                        }
                    } finally { $zip.Dispose() }
                    [void]$fol.DeployProject($p, [IO.File]::ReadAllBytes($tmp))
                    Remove-Item $tmp -Force
                    Ok "Proyecto $p implementado en SSISDB\$CarpetaSSIS (apunta a $servidor)"
                }
            } finally { $cm.Close() }

            # 5.6b solucion de Visual Studio con los 2 proyectos (STAGE_AW y DWH_AW) apuntando a ESTE servidor
            try {
                $destSol = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AdventureWork'
                New-Item -ItemType Directory -Force $destSol | Out-Null
                Copy-Item -Path (Join-Path $PSScriptRoot 'laboratorio4_etl\AdventureWork\*') -Destination $destSol -Recurse -Force
                foreach ($f in Get-ChildItem $destSol -Recurse -File -Include *.dtsx, *.conmgr, *.dtproj, *.params) {
                    $by = [IO.File]::ReadAllBytes($f.FullName); $bom = ($by.Length -ge 3 -and $by[0] -eq 0xEF -and $by[1] -eq 0xBB -and $by[2] -eq 0xBF)
                    $tx = [Text.Encoding]::UTF8.GetString($by); if ($bom) { $tx = $tx.TrimStart([char]0xFEFF) }
                    $txtNuevo = $tx.Replace('LAPTOP-IO596P6A\SQLEXPRESS', $servidor)
                    if ($txtNuevo -ne $tx) { [IO.File]::WriteAllText($f.FullName, $txtNuevo, (New-Object Text.UTF8Encoding($bom))) }
                }
                Ok "Solucion de Visual Studio: $destSol\AdventureWork.sln  (conectada a $servidor)"
            } catch { Aviso "No se pudo crear la solucion de Visual Studio: $($_.Exception.Message)" }

            # 5.7 Job de SQL Server Agent (STAGE y luego DWH, diario 02:00)
            $jobSql = @"
USE [msdb];
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'$NombreJob') EXEC msdb.dbo.sp_delete_job @job_name = N'$NombreJob', @delete_unused_schedule = 1;
DECLARE @server sysname = N'$servEtl';
DECLARE @c1 nvarchar(max) = N'/ISSERVER "\"\SSISDB\$CarpetaSSIS\STAGE_AW\MasterExecuteStage.dtsx\"" /SERVER "\"' + @server + N'\"" /Par "\"`$ServerOption::LOGGING_LEVEL(Int16)\"";1 /Par "\"`$ServerOption::SYNCHRONIZED(Boolean)\"";True /CALLERINFO SQLAGENT /REPORTING E';
DECLARE @c2 nvarchar(max) = N'/ISSERVER "\"\SSISDB\$CarpetaSSIS\DWH_AW\MasterExecuteDWH.dtsx\"" /SERVER "\"' + @server + N'\"" /Par "\"`$ServerOption::LOGGING_LEVEL(Int16)\"";1 /Par "\"`$ServerOption::SYNCHRONIZED(Boolean)\"";True /CALLERINFO SQLAGENT /REPORTING E';
DECLARE @owner sysname = SUSER_SNAME();
EXEC msdb.dbo.sp_add_job @job_name = N'$NombreJob', @enabled = 1, @description = N'Carga STAGE_AW y luego DWH_AW (paquetes maestros del catalogo SSISDB)', @owner_login_name = @owner;
EXEC msdb.dbo.sp_add_jobstep @job_name = N'$NombreJob', @step_name = N'Step_1_Stage_AW', @step_id = 1, @subsystem = N'SSIS', @command = @c1, @on_success_action = 4, @on_success_step_id = 2, @on_fail_action = 2;
EXEC msdb.dbo.sp_add_jobstep @job_name = N'$NombreJob', @step_name = N'Step_2_DWH_AW', @step_id = 2, @subsystem = N'SSIS', @command = @c2, @on_success_action = 1, @on_fail_action = 2;
EXEC msdb.dbo.sp_add_jobschedule @job_name = N'$NombreJob', @name = N'Diario_0200', @enabled = 1, @freq_type = 4, @freq_interval = 1, @active_start_time = 020000;
EXEC msdb.dbo.sp_add_jobserver @job_name = N'$NombreJob', @server_name = N'(local)';
SELECT 1 AS v;
"@
            [void](Consulta $cnE $jobSql)
            Ok "Job $NombreJob creado en $servEtl (diario 02:00)."

            # 5.8 prueba: se ejecuta una vez
            if ($SinProbarJob) { Info "Para ejecutarlo: SSMS > SQL Server Agent > Jobs > $NombreJob > Iniciar trabajo en el paso."; return }
            Info 'Ejecutando el Job una vez para comprobar que todo funciona (1-3 minutos)...'
            $jn = $NombreJob.Replace("'", "''")
            $inicioJob = (Get-Date).AddSeconds(-5).ToString('yyyyMMdd HH:mm:ss')
            [void](Consulta $cnE "EXEC msdb.dbo.sp_start_job @job_name = N'$jn'; SELECT 1 AS v")
            $limite = (Get-Date).AddMinutes(15); $fin = $false
            do {
                Start-Sleep 5
                $act = Consulta $cnE "SELECT COUNT(*) AS n FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id WHERE j.name = N'$jn' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
                $fin = ([int]$act.Rows[0].n -eq 0)
            } until ($fin -or (Get-Date) -gt $limite)
            $h = Consulta $cnE "SELECT TOP 1 h.run_status AS st FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id WHERE j.name = N'$jn' AND h.step_id = 0 ORDER BY h.instance_id DESC"
            if ($h.Rows.Count -and [int]$h.Rows[0].st -eq 1) {
                $r = Consulta $cn "SELECT (SELECT COUNT(*) FROM DWH_AW.Sales.FactSales) AS fact, (SELECT COUNT(*) FROM DWH_AW.Sales.ErrorFactSales) AS err, (SELECT COUNT(*) FROM DWH_AW.GENERICO.DimFecha) AS fecha, (SELECT COUNT(*) FROM DWH_AW.dbo.DIM_AUDIT WHERE SuccessfulProcessingInd <> 'Y' AND ExecStartDT >= '$inicioJob') AS audit_mal"
                Ok "Job ejecutado con exito. FactSales=$($r.Rows[0].fact)  ErrorFactSales=$($r.Rows[0].err)  DimFecha=$($r.Rows[0].fecha)  auditorias con error en esta corrida=$($r.Rows[0].audit_mal)"
            } else {
                Aviso "El Job fallo (o sigue ejecutando). Causa:"
                try {
                    $em = Consulta $cnE "SELECT TOP 6 CAST(em.message AS nvarchar(1500)) AS msg FROM SSISDB.catalog.event_messages em WHERE em.message_type = 120 AND em.operation_id = (SELECT MAX(execution_id) FROM SSISDB.catalog.executions WHERE folder_name = N'$($CarpetaSSIS.Replace("'", "''"))') ORDER BY em.event_message_id"
                    foreach ($x in $em.Rows) { Write-Host ("    SSIS: " + $x.msg) -ForegroundColor Red }
                    if (-not $em.Rows.Count) {
                        $hm = Consulta $cnE "SELECT TOP 3 CAST(h.message AS nvarchar(1500)) AS msg FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id WHERE j.name = N'$jn' AND h.step_id > 0 ORDER BY h.instance_id DESC"
                        foreach ($x in $hm.Rows) { Write-Host ("    Job: " + $x.msg) -ForegroundColor Red }
                    }
                } catch { Info "No se pudo leer el detalle: $($_.Exception.Message)" }
                Info 'Manda esas lineas rojas para corregirlo. Tambien: SSMS > Integration Services Catalogs > SSISDB > Informes > Todas las ejecuciones.'
            }
        } finally { if ($cnE -ne $cn) { $cnE.Close() } }
    } catch { Aviso "El ETL no se pudo completar: $($_.Exception.Message)" }
    Write-Host ''
    Info "Listo. Conectate en SSMS a $servidor. Los paquetes y el Job estan en $servEtl."
}
finally { $cn.Close() }
