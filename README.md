# Temas para Claude Desktop

Colores propios para la app de escritorio de Claude en macOS: Full Black, Dracula, Nord, Solarized Dark, Tokyo Night, o tu propio JSON.

> **No es oficial.** Este proyecto no está hecho ni respaldado por Anthropic. Funciona modificando tu copia de Claude Desktop; leé [qué cambia](#qué-cambia-en-tu-mac) antes de instalar.

<p align="center">
  <img src="docs/instalar.png" width="49%" alt="Primera instalación: elegís un tema y aceptás las advertencias">
  <img src="docs/aplicar.png" width="49%" alt="Con un tema instalado: elegís otro y lo aplicás">
</p>

## Instalar

1. Descargá **[Temas-para-Claude.zip](https://github.com/shadownrx/claude-desktop-themes/releases/latest/download/Temas-para-Claude.zip)** y descomprimilo.
2. Abrí **Temas para Claude**. La primera vez macOS la bloquea porque no está firmada por un desarrollador de Apple: andá a **Ajustes del Sistema → Privacidad y seguridad** y tocá **Abrir igualmente**.
3. Elegí un tema, marcá **Entiendo y quiero instalar** y tocá **Instalar**. La app cierra Claude, lo modifica y lo vuelve a abrir (1-2 minutos).
4. Cuando macOS pida permiso para **"Claude Safe Storage"**, poné tu contraseña y elegí **Permitir siempre**. Si lo negás, Claude pierde el login.
5. En Claude, poné la apariencia en **modo oscuro**. Los temas solo se aplican ahí.

Si macOS dice que la app no puede modificar otras apps, activá **Temas para Claude** en **Ajustes del Sistema → Privacidad y seguridad → Gestión de apps** y volvé a tocar **Instalar**.

**Requisitos:** macOS 14 o posterior, Claude Desktop en `/Applications` y [Node.js](https://nodejs.org) (`brew install node`). Probado con Claude 5.1231.0.

## Cambiar de tema

Abrí la app, elegí otro tema y tocá **Aplicar**. Después apretá `Cmd+R` en Claude. No hace falta volver a instalar.

## Tu propio tema

Tocá **Cargar JSON…** y elegí un archivo así (solo `background` es obligatorio; los colores van en hex):

```json
{
  "name": "Mi tema",
  "colors": {
    "background": "#000000",
    "sidebar": "#0a0a0a",
    "card": "#141414",
    "popover": "#1a1a1a",
    "input": "#262626",
    "border": "#333333",
    "text": "#ffffff",
    "textSecondary": "#d4d4d4",
    "textMuted": "#a3a3a3"
  }
}
```

| Clave | Qué pinta | Si falta, usa |
|---|---|---|
| `background` | Fondo principal | (obligatoria) |
| `sidebar` | Barra lateral | `background` |
| `card` | Tarjetas y hover | `sidebar` |
| `popover` | Menús desplegables | `card` |
| `input` | Caja de texto y botones | `popover` |
| `border` | Bordes | `input` |
| `text`, `textSecondary`, `textMuted` | Texto | colores de Claude |

En [`themes/`](themes) están los temas incluidos como ejemplo.

## Qué cambia en tu Mac

Claude Desktop no tiene temas, así que esto modifica la app:

- **Firma:** Claude queda firmado ad hoc, ya no por Anthropic.
- **Llavero:** al abrirlo, macOS pide permiso para "Claude Safe Storage".
- **Funciones que dejan de andar:** las passkeys y llaves de seguridad (WebAuthn) dentro de la app, y el conector de Microsoft 365. Para firmar ad hoc hay que sacar tres entitlements atados al equipo de Anthropic: `application-identifier`, `team-identifier` y `keychain-access-groups`.
- **Permisos:** hay que volver a dar Accesibilidad, Grabación de pantalla y Micrófono, si los usás.
- **Actualizaciones:** cada actualización de Claude borra el tema. Abrí la app y tocá **Instalar** de nuevo.
- **Copia de seguridad:** antes de tocar nada se guarda una copia completa de Claude original (unos 620 MB) en `~/claude-desktop-theme/backup-<versión>/`.

## Desinstalar

Abrí la app y tocá **Desinstalar**. Claude vuelve a la versión original de Anthropic, con su firma. También podés reinstalar Claude desde [claude.ai/download](https://claude.ai/download).

## Sin interfaz (Terminal)

[`instalar-tema-claude.command`](instalar-tema-claude.command) hace lo mismo desde Terminal; la app lo usa por dentro:

```sh
zsh instalar-tema-claude.command                     # instalar (pregunta el tema)
zsh instalar-tema-claude.command --theme mi.json     # cambiar de tema
zsh instalar-tema-claude.command --uninstall         # desinstalar
```

## Cómo funciona

- Se agrega un script al inicio de `.vite/build/index.pre.js`, dentro de `app.asar`. Ese script inserta el CSS del tema en las páginas de claude.ai.
- El tema activo está en `~/.claude/desktop-themes/active`. Cada JSON se convierte en CSS que pisa las variables de color de claude.ai: `--cds-gray-*`, `--cds-hsl-gray-*`, `--cds-surface-*` y `--cds-fizzy-lake-color-*`.
- Electron 45 valida la integridad de `app.asar` de dos formas: con un hash en `Info.plist` (`ElectronAsarIntegrity`) y con una huella SHA256 de ese diccionario guardada en `Electron Framework`. El instalador actualiza las dos y vuelve a firmar ad hoc el framework, los helpers y la app.
- `~/.claude/desktop-themes/debug.log` registra cada inyección. Sirve para diagnosticar si el tema no aparece.

Si claude.ai cambia sus variables de color, el tema puede dejar de verse aunque el log diga `insertCSS ok`.

## Compilar la app

```sh
zsh gui/build.sh   # genera gui/build/Temas para Claude.app y Temas-para-Claude.zip
```

Necesita las Command Line Tools de Xcode (`xcode-select --install`).
