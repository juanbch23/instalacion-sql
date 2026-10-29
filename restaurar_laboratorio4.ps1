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
    [switch]$Simular             # solo muestra lo que haria
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
    if ($Simular) { Info 'Se restaurarian AdventureWorks2016CTP3, STAGE_AW y DWH_AW (las que no existan).'; return }

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
    Info 'Siguiente paso: la parte 2 del PDF (ETL con Integration Services).'
    Info "En los paquetes SSIS usa el nombre de TU servidor: $servidor"
}
finally { $cn.Close() }
