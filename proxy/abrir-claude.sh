#!/bin/zsh
# Abre Claude Desktop con el tema: le pasa a Claude el PAC del proxy local (solo afecta a claude.ai).
# Claude.app no se modifica. Si Claude ya está abierto sin tema, pregunta antes de reiniciarlo.
set -uo pipefail
PORT=${CDT_PORT:-8737}
LABEL=local.claude-desktop-themes.proxy
PAC="http://127.0.0.1:$PORT/proxy.pac"
CLAUDE=/Applications/Claude.app
EXE="$CLAUDE/Contents/MacOS/Claude"

health() { curl -s -m 2 "http://127.0.0.1:$PORT/health" | grep -q '"ok":true'; }

# 1. Proxy arriba (launchd lo mantiene; si no responde, lo reinicia)
if ! health; then
  launchctl kickstart -k gui/$(id -u)/$LABEL 2>/dev/null
  for i in {1..20}; do health && break; sleep 0.25; done
fi
health || osascript -e 'display alert "Temas para Claude" message "El proxy del tema no responde. Claude se abre sin tema. Probá reinstalar desde la app Temas para Claude." as warning' >/dev/null

# 2. Claude
pid=$(pgrep -f "^$EXE( |$)" | head -1 || true)
if [[ -n $pid ]]; then
  if ps -o args= -p $pid | grep -q -- "--proxy-pac-url=$PAC"; then
    open -a "$CLAUDE"; exit 0
  fi
  ans=$(osascript -e 'button returned of (display dialog "Claude está abierto sin tema. ¿Reiniciarlo con el tema?" buttons {"Dejar así", "Reiniciar"} default button "Reiniciar" with title "Temas para Claude")' 2>/dev/null || echo "Dejar así")
  if [[ $ans != Reiniciar ]]; then open -a "$CLAUDE"; exit 0; fi
  osascript -e 'tell application id "com.anthropic.claudefordesktop" to quit' >/dev/null 2>&1 || kill -TERM $pid
  for i in {1..60}; do kill -0 $pid 2>/dev/null || break; sleep 0.5; done
fi
open -a "$CLAUDE" --args "--proxy-pac-url=$PAC"
