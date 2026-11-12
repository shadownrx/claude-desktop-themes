#!/bin/zsh
# Temas de color para Claude Desktop (macOS), SIN modificar Claude.app.
#   Instalar:        doble clic, o: zsh instalar-tema-claude.command
#   Cambiar tema:    zsh instalar-tema-claude.command --theme mi-tema.json
#   Desinstalar:     zsh instalar-tema-claude.command --uninstall
#   Sin preguntar:   agregar --yes
#
# Cómo funciona: un proxy local (solo 127.0.0.1, solo claude.ai) agrega el CSS del tema a las páginas
# de claude.ai. "Claude con tema" abre Claude indicándole ese proxy. Claude.app conserva la firma de
# Anthropic, el llavero, las passkeys, el registro del dispositivo, los permisos y las actualizaciones.
set -euo pipefail
SRC=${0:A:h}/proxy
H=${CDT_HOME:-$HOME}
APPDIR="$H/Library/Application Support/claude-desktop-themes"
THEMES=$H/.claude/desktop-themes
TLS=$THEMES/tls
LABEL=${CDT_LABEL:-local.claude-desktop-themes.proxy}
PLIST=$H/Library/LaunchAgents/$LABEL.plist
LAUNCHER="$H/Applications/Claude con tema.app"
PORT=${CDT_PORT:-8737}
CLAUDE=${CDT_CLAUDE:-/Applications/Claude.app}   # CDT_* solo para pruebas
CA_CN="Claude Desktop Themes local CA"
LEGACY=$H/claude-desktop-theme      # instalación vieja (parche de Claude.app)

say_() { print -P "%B$1%b"; }
die() { print -P "%F{red}%B$1%b%f" >&2; exit 1; }
health() { curl -s -m 2 "http://127.0.0.1:$PORT/health" | grep -q '"ok":true'; }
is_patched() { [[ "$(codesign -dv $CLAUDE 2>&1)" == *"Signature=adhoc"* ]]; }
ca_trusted() { [[ -f $TLS/claude.ai.crt ]] && security verify-cert -c $TLS/claude.ai.crt -p ssl -s claude.ai -q >/dev/null 2>&1; }
remove_ca() {   # borra del llavero de login todas las CA viejas de este proyecto
  local h
  for h in $(security find-certificate -a -c "$CA_CN" -Z $H/Library/Keychains/login.keychain-db 2>/dev/null | awk '/SHA-1 hash:/{print $3}'); do
    security delete-certificate -Z $h $H/Library/Keychains/login.keychain-db >/dev/null 2>&1 || true
  done
}

# Deshace el parche viejo (versiones 1.x) restaurando la copia original de Claude.app
unpatch_legacy() {
  is_patched || return 0
  local ver bk
  ver=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $CLAUDE/Contents/Info.plist)
  bk=$LEGACY/backup-$ver/Claude.app
  [[ -d $bk && "$(codesign -dv $bk 2>&1)" == *"TeamIdentifier=Q6L2SF6YDW"* ]] ||
    die "Claude.app está modificado por la versión vieja de este proyecto y no encuentro la copia original de la $ver.
Reinstalá Claude desde https://claude.ai/download y volvé a correr el instalador."
  touch "$CLAUDE/Contents/.cdt-write-test" 2>/dev/null || {
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles" 2>/dev/null || true
    die "Para volver Claude a la versión original, macOS tiene que dejar modificar apps.
Activá esta app (o Terminal) en Ajustes del Sistema → Privacidad y seguridad → Gestión de apps y volvé a intentar.
O reinstalá Claude desde https://claude.ai/download."; }
  rm -f "$CLAUDE/Contents/.cdt-write-test"
  pgrep -f "^$CLAUDE/Contents/MacOS/Claude( |$)" >/dev/null && die "Cerrá Claude (Cmd+Q) y volvé a intentar."
  say_ "Volviendo Claude.app a la versión original de Anthropic..."
  rm -rf "$CLAUDE.restoring" && ditto $bk "$CLAUDE.restoring"
  rm -rf $CLAUDE && mv "$CLAUDE.restoring" $CLAUDE
  codesign --verify --strict --deep $CLAUDE || die "La copia restaurada no verifica. Reinstalá Claude desde https://claude.ai/download."
  say_ "Claude.app restaurado con la firma de Anthropic."
}

use_theme() {   # valida el JSON, lo copia a $THEMES y lo deja activo
  local src=${1:A} name=${${1:t}%.json}
  [[ -f $src ]] || die "No existe $1"
  name=${name//[^A-Za-z0-9_-]/-}
  node "$SRC/theme-json.js" "$src" >/dev/null || die "El JSON tiene errores (ver arriba). No se cambió el tema."
  [[ $src == $THEMES/$name.json ]] || cp "$src" "$THEMES/$name.json"
  echo $name > $THEMES/active
  say_ "Tema activo: $name"
}

uninstall() {
  say_ "Desinstalando..."
  launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
  rm -f $PLIST
  rm -rf "$LAUNCHER" "$APPDIR"
  remove_ca
  rm -rf $TLS
  say_ "Listo. Claude no se modificó en ningún momento; abrilo normal y se ve como siempre."
  print "Tus temas siguen en $THEMES (borralos si querés)."
}

# --- argumentos
MODE=install; THEME_FILE=; YES=
while (( $# )); do
  case $1 in
    --uninstall) MODE=uninstall ;;
    --theme) [[ -n ${2:-} ]] || die "Uso: zsh $0 --theme mi-tema.json"; THEME_FILE=$2; shift ;;
    --yes) YES=1 ;;
    *) die "Opción desconocida: $1" ;;
  esac
  shift
done

[[ $(uname) == Darwin ]] || die "Solo funciona en macOS."
if [[ $MODE == uninstall ]]; then uninstall; exit 0; fi
[[ -d $CLAUDE ]] || die "No encuentro Claude en $CLAUDE. Instalalo desde https://claude.ai/download."
[[ -f $SRC/cdt-proxy.js ]] || die "Faltan los archivos del proxy junto al instalador ($SRC)."
NODE=$(command -v node || true)
[[ -n $NODE ]] || die "Falta Node.js. Instalalo (https://nodejs.org o brew install node) y volvé a correr."
NODE=${NODE:A}

# Cambio de tema con todo ya instalado: no hace falta más
mkdir -p $THEMES
if [[ -n $THEME_FILE ]] && health && ca_trusted; then
  use_theme "$THEME_FILE"
  print "En Claude apretá Cmd+R para verlo."
  exit 0
fi

if [[ -z $YES ]]; then
cat <<MSG

  Temas para Claude Desktop
  ─────────────────────────
  No se modifica Claude.app: conserva la firma de Anthropic, el llavero, las passkeys,
  el registro del dispositivo, los permisos y las actualizaciones.

  Lo que sí se instala, y conviene entender antes de seguir:

  • Un certificado propio que tu Mac va a CONFIAR para claude.ai. macOS te va a pedir
    tu contraseña. El certificado está restringido a claude.ai (name constraints) y su
    clave de firma se borra al crearlo: no sirve para ningún otro sitio.
  • Un proxy local (solo 127.0.0.1) que DESCIFRA el tráfico de claude.ai para agregarle
    el tema. Corre en tu Mac, no guarda ni envía nada, y el código está en
    $APPDIR
  • Mientras esté instalado, cualquier programa que se ejecute con tu usuario y lea
    $TLS/claude.ai.key podría hacerse pasar por claude.ai en tu Mac.
  • El tema solo se ve si abrís Claude con "Claude con tema" (en ~/Applications).
    Abierto desde el Dock, Claude funciona normal, sin tema.

  Para sacar todo: zsh "${0:A}" --uninstall

MSG
  read "ok?Escribí SI para continuar: "
  [[ $ok == SI || $ok == si || $ok == Si ]] || die "Cancelado. No se tocó nada."
fi

unpatch_legacy

say_ "Copiando archivos..."
mkdir -p "$APPDIR" $H/Library/LaunchAgents $H/Applications
cp "$SRC/cdt-proxy.js" "$SRC/theme-json.js" "$SRC/gen-cert.sh" "$SRC/abrir-claude.sh" "$APPDIR/"
chmod +x "$APPDIR/gen-cert.sh" "$APPDIR/abrir-claude.sh"
for f in ${0:A:h}/themes/*.json(N); do [[ -f $THEMES/${f:t} ]] || cp $f $THEMES/; done
if [[ -n $THEME_FILE ]]; then use_theme "$THEME_FILE"
elif [[ ! -f $THEMES/active ]]; then echo full-black > $THEMES/active; fi

# Certificado: se genera si falta o vence en menos de 30 días
if [[ ! -f $TLS/claude.ai.crt ]] || ! openssl x509 -checkend 2592000 -noout -in $TLS/claude.ai.crt >/dev/null 2>&1; then
  say_ "Generando certificado local para claude.ai..."
  remove_ca
  rm -rf $TLS
  zsh "$APPDIR/gen-cert.sh" $TLS
fi
if [[ -z ${CDT_SKIP_TRUST:-} ]] && ! ca_trusted; then
  say_ "macOS va a pedir tu contraseña para confiar el certificado (solo para claude.ai)..."
  security add-trusted-cert -r trustRoot -p ssl -k $H/Library/Keychains/login.keychain-db $TLS/ca.crt ||
    die "No se confió el certificado. Sin eso, Claude no puede cargar claude.ai por el proxy. Volvé a correr el instalador."
  ca_trusted || die "El certificado no quedó confiable. Volvé a correr el instalador."
fi

say_ "Iniciando el proxy..."
cat > $PLIST <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$NODE</string><string>$APPDIR/cdt-proxy.js</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>CDT_PORT</key><string>$PORT</string><key>CDT_DIR</key><string>$THEMES</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardErrorPath</key><string>$THEMES/proxy.err</string>
</dict>
</plist>
PL
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $PLIST
for i in {1..40}; do health && break; sleep 0.25; done
health || die "El proxy no arrancó. Mirá $THEMES/proxy.err"

say_ "Creando \"Claude con tema\" en ~/Applications..."
rm -rf "$LAUNCHER"
osacompile -o "$LAUNCHER" -e "do shell script quoted form of \"$APPDIR/abrir-claude.sh\"" >/dev/null 2>&1
ICON=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" $CLAUDE/Contents/Info.plist 2>/dev/null || echo electron)
[[ -f $CLAUDE/Contents/Resources/${ICON%.icns}.icns ]] && cp $CLAUDE/Contents/Resources/${ICON%.icns}.icns "$LAUNCHER/Contents/Resources/applet.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Claude con tema" "$LAUNCHER/Contents/Info.plist" 2>/dev/null || true
codesign --force --sign - "$LAUNCHER" >/dev/null 2>&1   # ícono y nombre cambiados: volver a sellar
touch "$LAUNCHER"

cat <<MSG

  Listo.
  • Abrí Claude con "Claude con tema" (~/Applications). Podés arrastrarlo al Dock.
  • En Claude, poné la apariencia en modo oscuro.
  • Cambiar de tema: zsh "${0:A}" --theme otro.json  (o la app Temas para Claude), y Cmd+R.
  • Comprobar: tail $THEMES/proxy.log  debería mostrar  tema "…" → /new
  • Desinstalar: zsh "${0:A}" --uninstall

MSG
