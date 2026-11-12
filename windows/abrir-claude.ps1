# Abre Claude Desktop con el tema (Windows, BETA): le pasa a Claude el PAC del proxy local.
# Claude no se modifica. Si Claude ya está abierto sin tema, pregunta antes de reiniciarlo.
$ErrorActionPreference = 'Stop'
$Port = 8737
$Pac = "http://127.0.0.1:$Port/proxy.pac"
$AppDir = Join-Path $env:LOCALAPPDATA 'claude-desktop-themes'
Add-Type -AssemblyName System.Windows.Forms

function Test-Proxy {
  try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "http://127.0.0.1:$Port/health").Content -match '"ok":true' } catch { $false }
}

function Find-ClaudeExe {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'),          # instalación Squirrel
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\claude.exe'),    # alias del paquete MSIX
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\Claude.exe')
  )
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  return $null
}

# 1. Proxy arriba
if (-not (Test-Proxy)) {
  Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$AppDir\proxy-oculto.vbs`"" -WindowStyle Hidden
  for ($i = 0; $i -lt 20 -and -not (Test-Proxy); $i++) { Start-Sleep -Milliseconds 250 }
}
if (-not (Test-Proxy)) {
  [System.Windows.Forms.MessageBox]::Show('El proxy del tema no responde. Claude se abre sin tema.', 'Temas para Claude (beta)', 'OK', 'Warning') | Out-Null
}

$exe = Find-ClaudeExe
if (-not $exe) {
  [System.Windows.Forms.MessageBox]::Show('No encuentro Claude Desktop. Instalalo desde https://claude.ai/download.', 'Temas para Claude (beta)', 'OK', 'Error') | Out-Null
  exit 1
}

# 2. Claude ya abierto
$running = @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
  if (@($running | Where-Object { $_.CommandLine -like "*--proxy-pac-url=$Pac*" }).Count -gt 0) {
    Start-Process -FilePath $exe   # ya tiene tema: solo traerlo al frente
    exit 0
  }
  $ans = [System.Windows.Forms.MessageBox]::Show('Claude está abierto sin tema. ¿Reiniciarlo con el tema?', 'Temas para Claude (beta)', 'YesNo', 'Question')
  if ($ans -ne 'Yes') { Start-Process -FilePath $exe; exit 0 }
  Get-Process -Name claude -ErrorAction SilentlyContinue | ForEach-Object { [void]$_.CloseMainWindow() }
  Start-Sleep -Seconds 3
  Get-Process -Name claude -ErrorAction SilentlyContinue | Stop-Process -Force   # Claude se queda en la bandeja al cerrar la ventana
  Start-Sleep -Seconds 1
}

Start-Process -FilePath $exe -ArgumentList "--proxy-pac-url=$Pac"
