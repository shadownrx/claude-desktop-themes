#!/bin/zsh
# Temas de color para Claude Desktop (macOS).
#   Instalar:        doble clic, o: zsh instalar-tema-claude.command
#   Cambiar tema:    zsh instalar-tema-claude.command --theme mi-tema.json
#   Desinstalar:     zsh instalar-tema-claude.command --uninstall
#   Sin preguntar:   agregar --yes
#
# Formato del JSON (solo "background" es obligatorio; colores en hex):
#   { "name": "Mi tema",
#     "colors": { "background": "#000000", "sidebar": "#0a0a0a", "card": "#141414",
#                 "popover": "#1a1a1a", "input": "#262626", "border": "#333333",
#                 "text": "#ffffff", "textSecondary": "#d4d4d4", "textMuted": "#a3a3a3" } }
set -euo pipefail
APP=${APP:-/Applications/Claude.app}
DIR=$HOME/claude-desktop-theme
THEMES=$HOME/.claude/desktop-themes
TEST=${APP:#/Applications/Claude.app}   # no vacío si se prueba sobre una copia
SELF=${0:A}

say_() { print -P "%B$1%b"; }
die() { print -P "%F{red}%B$1%b%f"; exit 1; }
quit_claude() {
  [[ -n $TEST ]] && return
  pgrep -f "$APP/Contents/MacOS/Claude" >/dev/null || return 0
  say_ "Cerrando Claude..."
  osascript -e 'quit app "Claude"' >/dev/null 2>&1 || true
  for i in {1..30}; do pgrep -f "$APP/Contents/MacOS/Claude" >/dev/null || return 0; sleep 1; done
  die "Claude no se cerró. Cerralo a mano (Cmd+Q) y volvé a correr el instalador."
}
check_write() {
  [[ -n $TEST ]] && return
  if ! touch "$APP/Contents/.cdt-write-test" 2>/dev/null; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles" 2>/dev/null || true
    die "macOS no deja modificar Claude.app desde Terminal.
Activá Terminal en Ajustes del Sistema → Privacidad y seguridad → Gestión de apps (ya te lo abrí), cerrá Terminal y volvé a correr el instalador."
  fi
  rm -f "$APP/Contents/.cdt-write-test"
}
write_files() {
  mkdir -p $DIR $THEMES
cat > "$DIR/inject.js" <<'__CDT_EOF__'
/*claude-desktop-theme*/;(()=>{try{const E=require("electron"),fs=require("fs"),path=require("path"),os=require("os");const dir=path.join(os.homedir(),".claude","desktop-themes");const log=m=>{try{fs.appendFileSync(path.join(dir,"debug.log"),new Date().toISOString()+" "+m+"\n")}catch{}};log("inject cargado pid="+process.pid);const css=()=>{try{const n=fs.readFileSync(path.join(dir,"active"),"utf8").trim();if(!n||n==="none"||!/^[\w-]+$/.test(n))return null;return fs.readFileSync(path.join(dir,n+".css"),"utf8")}catch(e){log("css error "+e.message);return null}};const ok=u=>{try{const h=new URL(u).hostname;return h==="claude.ai"||h.endsWith(".claude.ai")}catch{return!1}};const apply=(f,tag)=>{try{if(!f||!ok(f.url))return;const c=css();if(!c)return;f.executeJavaScript("(()=>{let s=document.getElementById('cdt-theme');if(!s){s=document.createElement('style');s.id='cdt-theme';(document.head||document.documentElement).appendChild(s)}s.textContent="+JSON.stringify(c)+";})()").then(()=>log("aplicado "+tag+" "+f.url.slice(0,80)),e=>log("fallo "+tag+" "+e.message))}catch(e){log("apply error "+e.message)}};E.app.on("web-contents-created",(_e,wc)=>{log("wc creado tipo="+wc.getType());wc.on("dom-ready",()=>{log("dom-ready "+wc.getURL().slice(0,80));try{if(ok(wc.getURL())){const c=css();if(c)wc.insertCSS(c,{cssOrigin:"user"}).then(()=>log("insertCSS ok "+wc.getURL().slice(0,80)),e=>log("insertCSS fallo "+e.message))}}catch(e){log("main error "+e.message)}});wc.on("did-frame-finish-load",(_e,isMain,pid,rid)=>{if(isMain)return;try{apply(E.webFrameMain.fromId(pid,rid),"frame")}catch(e){log("frame error "+e.message)}})})}catch(e){try{require("fs").appendFileSync(require("os").homedir()+"/.claude/desktop-themes/debug.log","inject error "+e.message+"\n")}catch{}}})();
__CDT_EOF__
cat > "$DIR/patch.sh" <<'__CDT_EOF__'
#!/bin/zsh
# Inyecta temas CSS (~/.claude/desktop-themes/<active>.css) en Claude Desktop.
# Volver a correr después de cada actualización de Claude.
# APP=/otra/ruta/Claude.app ./patch.sh parchea otra copia (para probar).
set -euo pipefail
APP=${APP:-/Applications/Claude.app}
DIR=${0:A:h}
RES=$APP/Contents/Resources
FW="$APP/Contents/Frameworks/Electron Framework.framework"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $APP/Contents/Info.plist)
BK=$DIR/backup-$VER
WORK=$(mktemp -d)
trap 'rm -rf $WORK' EXIT

[[ -d $DIR/node_modules/@electron/asar ]] || (cd $DIR && npm i --silent @electron/asar >/dev/null)

# 1. Backup completo de la app original (una vez por versión)
if [[ ! -d $BK/Claude.app ]]; then
  [[ "$(codesign -dv $APP 2>&1)" == *"TeamIdentifier=Q6L2SF6YDW"* ]] || { echo "La app no tiene la firma original y no hay backup de $VER. Reinstalá Claude y volvé a correr."; exit 1; }
  mkdir -p $BK && ditto $APP $BK/Claude.app
  echo "Backup en $BK/Claude.app"
fi
SRC=$BK/Claude.app

# 2. Extraer app.asar original, inyectar, reempaquetar con los mismos archivos sin empaquetar
node -e '
const fs=require("fs"),p=require("path");
(async()=>{
const [_,dir,src,inj,work]=process.argv;
const a=await import(dir+"/node_modules/@electron/asar/lib/asar.js");
a.extractAll(src,work+"/app");
const f=work+"/app/.vite/build/index.pre.js";let s=fs.readFileSync(f,"utf8");
if(!s.startsWith("\"use strict\";"))throw Error("index.pre.js inesperado");
s="\"use strict\";"+fs.readFileSync(inj,"utf8").trim()+s.slice(13);fs.writeFileSync(f,s);
const unp=h=>{const o=[];const w=(n,pre)=>{for(const[k,v]of Object.entries(n.files||{})){const q=pre?pre+"/"+k:k;if(v.files)w(v,q);else if(v.unpacked)o.push(q)}};w(h,"");return o.sort()};
const un=unp(a.getRawHeader(src).header);
await a.createPackageWithOptions(work+"/app",work+"/app.asar",{unpack:"{"+un.map(x=>p.basename(x)).join(",")+"}"});
const un2=unp(a.getRawHeader(work+"/app.asar").header);
if(JSON.stringify(un)!==JSON.stringify(un2))throw Error("archivos unpacked distintos: "+un2.join(","));
fs.writeFileSync(work+"/hash",require("crypto").createHash("sha256").update(a.getRawHeader(work+"/app.asar").headerString).digest("hex"));
})().catch(e=>{console.error(e.message);process.exit(1)})' $DIR $SRC/Contents/Resources/app.asar $DIR/inject.js $WORK
diff -rq $WORK/app.asar.unpacked $SRC/Contents/Resources/app.asar.unpacked >/dev/null || { echo "app.asar.unpacked difiere, abortando"; exit 1; }

# 3. Entitlements de la app sin los restringidos (ad hoc no los puede tener)
codesign -d --entitlements :- $SRC 2>/dev/null > $WORK/ent.plist
for k in com.apple.application-identifier com.apple.developer.team-identifier keychain-access-groups; do
  /usr/libexec/PlistBuddy -c "Delete :$k" $WORK/ent.plist 2>/dev/null || true
done

# 4. Instalar: asar nuevo, hash en Info.plist y huella del diccionario en Electron Framework
cp $SRC/Contents/Info.plist $WORK/Info.plist
/usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $(cat $WORK/hash)" $WORK/Info.plist
cp "$SRC/Contents/Frameworks/Electron Framework.framework/Versions/A/Electron Framework" $WORK/fw
python3 -I - $WORK/Info.plist $WORK/fw <<'PY'
import sys,plistlib,hashlib
d=plistlib.load(open(sys.argv[1],"rb"))["ElectronAsarIntegrity"]
b=bytearray(open(sys.argv[2],"rb").read())
sen=b"AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A"
assert b.count(sen)==1,"sentinel no encontrado una sola vez"
i=b.find(sen); assert b[i+32]==1 and b[i+33]==1,"formato de huella desconocido"
h=hashlib.sha256()
for k in sorted(d): h.update(k.encode()); h.update(d[k]["algorithm"].encode()); h.update(d[k]["hash"].encode())
b[i+34:i+66]=h.digest(); open(sys.argv[2],"wb").write(b)
PY
mv -f $WORK/app.asar $RES/app.asar
cp $WORK/Info.plist $APP/Contents/Info.plist
cp $WORK/fw "$FW/Versions/A/Electron Framework"

# 5. Firma ad hoc de adentro hacia afuera, sin hardened runtime
codesign --force --sign - "$FW"
for h in $APP/Contents/Frameworks/*.app; do
  codesign --force --sign - --preserve-metadata=entitlements "$h"
done
codesign --force --sign - --entitlements $WORK/ent.plist $APP
codesign --verify --strict --deep $APP && echo "Parche aplicado ($VER). Reiniciá Claude."
__CDT_EOF__
cat > "$DIR/restore.sh" <<'__CDT_EOF__'
#!/bin/zsh
# Deja Claude Desktop como venía de Anthropic, desde el backup completo de la misma versión.
set -euo pipefail
APP=${APP:-/Applications/Claude.app}
DIR=${0:A:h}
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $APP/Contents/Info.plist)
BK=$DIR/backup-$VER/Claude.app
[[ -d $BK ]] || { echo "No hay backup completo para $VER. Reinstalá Claude desde claude.ai/download."; exit 1; }
[[ "$(codesign -dv $BK 2>&1)" == *"TeamIdentifier=Q6L2SF6YDW"* ]] || { echo "El backup no tiene la firma original, abortando."; exit 1; }
pgrep -f "$APP/Contents/MacOS/Claude" >/dev/null && { echo "Cerrá Claude primero."; exit 1; }
rm -rf "$APP.restoring" && ditto $BK "$APP.restoring"
rm -rf $APP && mv "$APP.restoring" $APP
codesign --verify --strict --deep $APP && echo "Restaurado ($VER). Abrí Claude."
__CDT_EOF__
cat > "$DIR/theme-json.js" <<'__CDT_EOF__'
// Convierte un tema JSON en CSS para Claude Desktop (modo oscuro).
// Uso: node theme-json.js tema.json salida.css
// Claves de "colors" (todas opcionales salvo background), en hex (#rgb o #rrggbb):
//   background     fondo principal
//   sidebar        barra lateral
//   card           tarjetas y hover
//   popover        menús desplegables
//   input          caja de texto y botones
//   border         bordes
//   text, textSecondary, textMuted   texto
const fs = require("fs");
const [, , inp, out] = process.argv;
if (!inp || !out) { console.error("Uso: node theme-json.js tema.json salida.css"); process.exit(1); }
let t;
try { t = JSON.parse(fs.readFileSync(inp, "utf8")); } catch (e) { console.error("JSON inválido: " + e.message); process.exit(1); }
const c = t.colors || {};
const KEYS = ["background", "sidebar", "card", "popover", "input", "border", "text", "textSecondary", "textMuted"];
for (const k of Object.keys(c)) if (!KEYS.includes(k)) { console.error(`Clave desconocida "${k}". Válidas: ${KEYS.join(", ")}`); process.exit(1); }
const norm = (k) => {
  const v = String(c[k]).trim().toLowerCase();
  if (/^#[0-9a-f]{3}$/.test(v)) return "#" + [...v.slice(1)].map((x) => x + x).join("");
  if (/^#[0-9a-f]{6}$/.test(v)) return v;
  console.error(`"${k}": "${c[k]}" no es un color hex (#rgb o #rrggbb)`); process.exit(1);
};
if (!c.background) { console.error('Falta "colors.background"'); process.exit(1); }
const col = {};
for (const k of Object.keys(c)) col[k] = norm(k);
const bg = col.background, sidebar = col.sidebar || bg, card = col.card || sidebar;
const popover = col.popover || card, input = col.input || popover, border = col.border || input;
const hsl = (h) => {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn;
  let H = 0, S = 0;
  if (d) {
    S = d / (1 - Math.abs(2 * l - 1));
    H = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
    H = (H * 60 + 360) % 360;
  }
  const f = (x) => +x.toFixed(3);
  return `${Math.round(H)} ${f(S * 100)}% ${f(l * 100)}%`;
};
const mix = (a, b, w) => "#" + [1, 3, 5].map((i) => Math.round(parseInt(a.slice(i, i + 2), 16) * (1 - w) + parseInt(b.slice(i, i + 2), 16) * w).toString(16).padStart(2, "0")).join("");
const L = [];
const v = (name, val) => L.push(`  ${name}: ${val} !important;`);
const gray = (n, h) => { v(`--cds-gray-${n}`, h); v(`--cds-hsl-gray-${n}`, hsl(h)); };
// Escala de grises (vista clásica)
gray(650, border); gray(700, input); gray(750, popover); gray(800, card); gray(810, mix(sidebar, card, 0.3)); gray(820, sidebar);
for (const n of [830, 840, 850, 860, 870, 880, 890, 900]) gray(n, bg);
// Variante fizzy-lake (vista nueva)
v("--cds-surface-1", bg); v("--cds-surface-2", sidebar); v("--cds-surface-3", card);
v("--cds-surface-popover", popover); v("--cds-fizzy-lake-color-sidebar", sidebar);
v("--cds-fizzy-lake-color-card-hover", card); v("--cds-on-primary", bg);
if (col.text) { v("--cds-text-primary", col.text); v("--cds-fizzy-lake-color-solid-primary", col.text); }
if (col.textSecondary) for (const n of ["--cds-text-secondary", "--cds-text-stays-secondary", "--cds-fizzy-lake-color-secondary", "--cds-fizzy-lake-color-plain-secondary", "--cds-fizzy-lake-color-solid-secondary"]) v(n, col.textSecondary);
if (col.textMuted) for (const n of ["--cds-text-muted", "--cds-fizzy-lake-color-tertiary", "--cds-fizzy-lake-color-plain-muted", "--cds-fizzy-lake-color-solid-muted", "--cds-fizzy-lake-color-placeholder"]) v(n, col.textMuted);
const css = `/* Generado desde ${require("path").basename(inp)} (${t.name || "sin nombre"}) por theme-json.js. Editá el JSON, no este archivo. */
@media (prefers-color-scheme: dark) {
*, :root {
${L.join("\n")}
}
html, body { background-color: ${bg} !important; }
}
`;
fs.writeFileSync(out, css);
console.log(`Tema "${t.name || inp}" → ${out}`);
__CDT_EOF__
cat > "$DIR/full-black.json" <<'__CDT_EOF__'
{
  "name": "Full Black",
  "colors": {
    "background": "#000000",
    "sidebar": "#0a0a0a",
    "card": "#141414",
    "popover": "#1a1a1a",
    "input": "#262626",
    "border": "#333333"
  }
}
__CDT_EOF__
  chmod +x $DIR/patch.sh $DIR/restore.sh
  [[ -f $THEMES/full-black.json ]] || cp $DIR/full-black.json $THEMES/full-black.json
}
# Convierte el JSON a CSS en $THEMES y lo deja activo
use_theme() {
  local src=${1:A} name=${${1:t}%.json}
  [[ -f $src ]] || die "No existe $1"
  name=${name//[^A-Za-z0-9_-]/-}
  node $DIR/theme-json.js "$src" /dev/null >/dev/null || die "El JSON tiene errores (ver arriba). No se cambió el tema."
  [[ $src == $THEMES/$name.json ]] || cp "$src" "$THEMES/$name.json"
  node $DIR/theme-json.js "$THEMES/$name.json" "$THEMES/$name.css"
  echo $name > $THEMES/active
}
is_patched() { [[ "$(codesign -dv "$APP" 2>&1)" == *"Signature=adhoc"* ]] && [[ -f $DIR/inject.js ]]; }

[[ $(uname) == Darwin ]] || die "Solo funciona en macOS."
[[ -d $APP ]] || die "No encuentro $APP."
command -v node >/dev/null && command -v npm >/dev/null || die "Falta Node.js (node y npm). Instalalo (https://nodejs.org o brew install node) y volvé a correr."

MODE=install; THEME_FILE=; YES=
while (( $# )); do
  case $1 in
    --uninstall) MODE=uninstall ;;
    --theme) [[ -n ${2:-} ]] || die "Uso: zsh $SELF --theme mi-tema.json"; THEME_FILE=$2; shift ;;
    --yes) YES=1 ;;   # confirmación ya dada (la usa la app con interfaz)
    *) die "Opción desconocida: $1" ;;
  esac
  shift
done

if [[ $MODE == uninstall ]]; then
  [[ -x $DIR/restore.sh ]] || die "No hay instalación en $DIR."
  check_write; quit_claude
  APP=$APP $DIR/restore.sh
  [[ -n $TEST ]] || open -a "$APP"
  exit 0
fi

# Solo cambiar el tema si la app ya está parcheada
if [[ -n $THEME_FILE ]] && is_patched; then
  write_files
  use_theme "$THEME_FILE"
  say_ "Tema aplicado. En Claude: Cmd+R para verlo."
  exit 0
fi

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $APP/Contents/Info.plist)
cat <<MSG

  Temas para Claude Desktop $VER
  ──────────────────────────────
  Claude Desktop no tiene temas, así que esto modifica la app. Efectos:

  • La app queda firmada ad hoc (ya no por Anthropic).
  • Al abrirla, macOS pide permiso para "Claude Safe Storage" en el llavero:
    elegí "Permitir siempre". Si lo negás, la app pierde el login.
  • Dejan de andar las passkeys / llaves de seguridad dentro de la app y el
    conector de Microsoft 365.
  • Hay que volver a dar los permisos de Accesibilidad, Grabación de pantalla
    y Micrófono si los usás.
  • Cada actualización de Claude borra el tema: volvé a correr este instalador.
  • Se guarda una copia de la app original (~620 MB) en
    $DIR/backup-$VER
    Para volver atrás: zsh "$SELF" --uninstall

  Probado con Claude 5.1231.0. Claude se va a cerrar durante la instalación.

MSG
if [[ -z $YES ]]; then
  read "ok?Escribí SI para continuar: "
  [[ $ok == SI || $ok == si || $ok == Si ]] || die "Cancelado. No se tocó nada."
fi

if [[ -z $THEME_FILE && -t 0 ]]; then
  print "\nTema: arrastrá acá un JSON de colores y apretá Enter, o solo Enter para Full Black."
  read "THEME_FILE?JSON: "
  THEME_FILE=${${THEME_FILE## }%% }; THEME_FILE=${THEME_FILE//\\ / }; THEME_FILE=${THEME_FILE#\'}; THEME_FILE=${THEME_FILE%\'}
fi

check_write
say_ "Creando archivos en $DIR y $THEMES..."
write_files
use_theme "${THEME_FILE:-$THEMES/full-black.json}"

quit_claude
say_ "Parcheando (tarda 1-2 minutos)..."
APP=$APP $DIR/patch.sh || die "Falló el parche. La app original está en $DIR/backup-$VER/Claude.app; para restaurar: zsh \"$SELF\" --uninstall"

[[ -n $TEST ]] && exit 0
open -a "$APP"
cat <<MSG

  Listo. Ahora:
  1. Cuando macOS pida "Claude Safe Storage": tu contraseña y "Permitir siempre".
  2. En Claude, poné la apariencia en modo oscuro.

  Cambiar de tema: zsh "$SELF" --theme otro.json  (después Cmd+R en Claude)
  Temas guardados: $THEMES
  Si algo anda mal: zsh "$SELF" --uninstall

MSG
