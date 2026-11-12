# Temas para Claude Desktop en Windows (BETA, sin probar en Windows real). No modifica Claude.
#   Instalar:      doble clic en instalar-windows.cmd   (o: powershell -ExecutionPolicy Bypass -File windows\instalar.ps1)
#   Cambiar tema:  instalar-windows.cmd -Theme mi-tema.json
#   Desinstalar:   instalar-windows.cmd -Uninstall
#
# Igual que en macOS: un proxy local (solo 127.0.0.1, solo claude.ai) agrega el CSS del tema a claude.ai,
# con un certificado local restringido a claude.ai. "Claude con tema" abre Claude indicándole ese proxy.
param(
  [switch]$Uninstall,
  [string]$Theme,
  [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $PSScriptRoot          # carpeta del zip: proxy\, themes\, windows\
$AppDir  = Join-Path $env:LOCALAPPDATA 'claude-desktop-themes'
$Themes  = Join-Path $HOME '.claude\desktop-themes'
$Tls     = Join-Path $Themes 'tls'
$Port    = 8737
$CaName  = 'Claude Desktop Themes local CA'
$Startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'claude-desktop-themes-proxy.vbs'
$Shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Claude con tema.lnk'

function Say($m) { Write-Host $m -ForegroundColor Cyan }
function Die($m) { Write-Host $m -ForegroundColor Red; exit 1 }
function Test-Proxy {
  try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "http://127.0.0.1:$Port/health").Content -match '"ok":true' } catch { $false }
}
function Stop-Proxy {
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*cdt-proxy.js*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
function Remove-Ca {
  Get-ChildItem Cert:\CurrentUser\Root | Where-Object { $_.Subject -like "*$CaName*" } |
    ForEach-Object { Remove-Item -Path $_.PSPath -ErrorAction SilentlyContinue }   # Windows pide confirmar
}
function Test-CaTrusted {
  (Test-Path (Join-Path $Tls 'ca.cer')) -and
  (@(Get-ChildItem Cert:\CurrentUser\Root | Where-Object { $_.Subject -like "*$CaName*" }).Count -gt 0)
}

if ($Uninstall) {
  Say 'Desinstalando...'
  Stop-Proxy
  Remove-Item -Force -ErrorAction SilentlyContinue $Startup, $Shortcut
  Remove-Ca
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Tls, $AppDir
  Say 'Listo. Claude no se modificó; abrilo normal y se ve como siempre.'
  Write-Host "Tus temas siguen en $Themes."
  exit 0
}

$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { Die 'Falta Node.js. Instalalo (winget install OpenJS.NodeJS.LTS o https://nodejs.org) y volvé a correr.' }
if (-not (Test-Path (Join-Path $Root 'proxy\cdt-proxy.js'))) { Die "Faltan los archivos del proxy en $Root\proxy." }
New-Item -ItemType Directory -Force -Path $Themes, $AppDir | Out-Null

function Use-Theme($file) {
  $src = (Resolve-Path $file).Path
  & $node (Join-Path $Root 'proxy\theme-json.js') $src
  if ($LASTEXITCODE -ne 0) { Die 'El JSON tiene errores (ver arriba). No se cambió el tema.' }
  $name = ([IO.Path]::GetFileNameWithoutExtension($src)) -replace '[^A-Za-z0-9_-]', '-'
  $dest = Join-Path $Themes "$name.json"
  if ($src -ne $dest) { Copy-Item $src $dest -Force }
  Set-Content -Path (Join-Path $Themes 'active') -Value $name -NoNewline
  Say "Tema activo: $name"
}

# Solo cambiar el tema si ya está todo instalado
if ($Theme -and (Test-Proxy) -and (Test-CaTrusted)) {
  Use-Theme $Theme
  Write-Host 'En Claude apretá Ctrl+R para verlo.'
  exit 0
}

if (-not $Yes) {
  Write-Host @"

  Temas para Claude Desktop - Windows (BETA)
  -----------------------------------------
  BETA: todavía no se probó en Windows. Si algo falla, desinstalá con  instalar-windows.cmd -Uninstall

  No se modifica Claude: conserva la firma de Anthropic, las credenciales y las actualizaciones.
  Lo que sí se instala, y conviene entender antes de seguir:

  * Un certificado que Windows va a CONFIAR para claude.ai (Windows te pide confirmarlo).
    Está restringido a claude.ai (name constraints) y la clave que lo emitió se borra:
    no sirve para ningún otro sitio.
  * Un proxy local (solo 127.0.0.1) que DESCIFRA el tráfico de claude.ai para agregar el tema.
    Corre en tu PC, no guarda ni envía nada. Código en: $AppDir
  * Mientras esté instalado, un programa que corra con tu usuario y lea la clave del
    certificado ($Tls) podría hacerse pasar por claude.ai en tu PC.
  * El tema solo se ve si abrís Claude con "Claude con tema" (menú Inicio).

"@
  $ok = Read-Host 'Escribí SI para continuar'
  if ($ok -notin @('SI', 'si', 'Si')) { Die 'Cancelado. No se tocó nada.' }
}

Say 'Copiando archivos...'
Copy-Item (Join-Path $Root 'proxy\cdt-proxy.js'), (Join-Path $Root 'proxy\theme-json.js'), (Join-Path $Root 'windows\abrir-claude.ps1') $AppDir -Force
Get-ChildItem (Join-Path $Root 'themes\*.json') | ForEach-Object {
  if (-not (Test-Path (Join-Path $Themes $_.Name))) { Copy-Item $_.FullName $Themes }
}
if ($Theme) { Use-Theme $Theme }
elseif (-not (Test-Path (Join-Path $Themes 'active'))) { Set-Content -Path (Join-Path $Themes 'active') -Value 'full-black' -NoNewline }

# Certificado: CA restringida a claude.ai -> firma claude.ai -> se borra la clave de la CA
$pfx = Join-Path $Tls 'claude.ai.pfx'
$expiring = $true
if (Test-Path $pfx) {
  try {
    $pass = Get-Content (Join-Path $Tls 'pfx.pass') -Raw
    $c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfx, $pass.Trim())
    $expiring = $c.NotAfter -lt (Get-Date).AddDays(30)
  } catch { $expiring = $true }
}
if ($expiring) {
  Say 'Generando certificado local para claude.ai...'
  Remove-Ca
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Tls
  New-Item -ItemType Directory -Force -Path $Tls | Out-Null
  $who = "$env:USERNAME@$env:COMPUTERNAME"
  $ca = New-SelfSignedCertificate -Subject "CN=$CaName ($who), O=claude-desktop-themes (local)" `
    -KeyAlgorithm ECDSA_nistP256 -HashAlgorithm SHA256 -CertStoreLocation Cert:\CurrentUser\My `
    -KeyUsage CertSign, CRLSign -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddDays(820) `
    -TextExtension @('2.5.29.19={critical}{text}ca=1&pathlength=0', '2.5.29.30={critical}{text}SubTree=Include&DNS=claude.ai')
  try {
    $nc = $ca.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.30' }
    if (-not $nc -or -not $nc.Critical -or ($nc.Format($false) -notmatch 'claude\.ai')) {
      Die 'La CA no quedó restringida a claude.ai. Por seguridad no se instala nada.'
    }
    $leaf = New-SelfSignedCertificate -Subject 'CN=claude.ai' -DnsName 'claude.ai' -Signer $ca `
      -KeyAlgorithm ECDSA_nistP256 -HashAlgorithm SHA256 -CertStoreLocation Cert:\CurrentUser\My `
      -KeyUsage DigitalSignature -KeyExportPolicy Exportable -NotAfter (Get-Date).AddDays(820) `
      -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.1')
    $passPlain = [Convert]::ToBase64String((1..24 | ForEach-Object { [byte](Get-Random -Maximum 256) }))
    $sec = ConvertTo-SecureString $passPlain -AsPlainText -Force
    # AES256: Node (OpenSSL 3) no abre los PFX con RC2 que Windows exporta por defecto
    try { Export-PfxCertificate -Cert $leaf -FilePath $pfx -Password $sec -CryptoAlgorithmOption AES256_SHA256 | Out-Null }
    catch { Export-PfxCertificate -Cert $leaf -FilePath $pfx -Password $sec | Out-Null }
    Set-Content -Path (Join-Path $Tls 'pfx.pass') -Value $passPlain -NoNewline
    Export-Certificate -Cert $ca -FilePath (Join-Path $Tls 'ca.cer') | Out-Null
  } finally {
    # La clave de la CA (y la copia del certificado de claude.ai) salen del almacén: no se puede emitir nada más
    if ($leaf) { Remove-Item -Path $leaf.PSPath -DeleteKey -ErrorAction SilentlyContinue }
    Remove-Item -Path $ca.PSPath -DeleteKey -ErrorAction SilentlyContinue
  }
}
if (-not (Test-CaTrusted)) {
  Say 'Windows va a pedir que confirmes el certificado (solo para claude.ai)...'
  try { Import-Certificate -FilePath (Join-Path $Tls 'ca.cer') -CertStoreLocation Cert:\CurrentUser\Root | Out-Null } catch { }
  if (-not (Test-CaTrusted)) { Die 'No se confió el certificado. Sin eso, Claude no puede cargar claude.ai por el proxy.' }
}

Say 'Iniciando el proxy...'
$vbs = @"
Set sh = CreateObject("WScript.Shell")
sh.Environment("PROCESS")("CDT_PORT") = "$Port"
sh.Run """$node"" ""$AppDir\cdt-proxy.js""", 0, False
"@
Set-Content -Path (Join-Path $AppDir 'proxy-oculto.vbs') -Value $vbs -Encoding ASCII
Copy-Item (Join-Path $AppDir 'proxy-oculto.vbs') $Startup -Force     # arranca con la sesión
Stop-Proxy
Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$AppDir\proxy-oculto.vbs`"" -WindowStyle Hidden
for ($i = 0; $i -lt 40 -and -not (Test-Proxy); $i++) { Start-Sleep -Milliseconds 250 }
if (-not (Test-Proxy)) { Die "El proxy no arrancó. Mirá $Themes\proxy.log" }

Say 'Creando "Claude con tema" en el menú Inicio...'
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($Shortcut)
$lnk.TargetPath = (Get-Command powershell.exe).Source
$lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$AppDir\abrir-claude.ps1`""
$icon = @((Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\claude.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($icon) { $lnk.IconLocation = "$icon,0" }
$lnk.Save()

Write-Host @"

  Listo (BETA).
  * Abrí Claude con "Claude con tema" (menú Inicio).
  * En Claude, poné la apariencia en modo oscuro.
  * Cambiar de tema: instalar-windows.cmd -Theme otro.json, y Ctrl+R en Claude.
  * Comprobar: en $Themes\proxy.log debería aparecer  tema "..." -> /new
  * Desinstalar: instalar-windows.cmd -Uninstall

"@
