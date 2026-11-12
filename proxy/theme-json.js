// Convierte un tema JSON en el CSS que se inyecta en claude.ai (solo modo oscuro).
// Módulo: const { themeToCss } = require("./theme-json"); themeToCss(objeto) → string (lanza Error si es inválido)
// CLI:    node theme-json.js tema.json [salida.css]   (valida; con salida, escribe el CSS)
//
// Claves de "colors" (todas opcionales salvo background), en hex (#rgb o #rrggbb):
//   background     fondo principal
//   sidebar        barra lateral
//   card           tarjetas y hover
//   popover        menús desplegables
//   input          caja de texto y botones
//   border         bordes
//   text, textSecondary, textMuted   texto
"use strict";
const KEYS = ["background", "sidebar", "card", "popover", "input", "border", "text", "textSecondary", "textMuted"];

function normHex(key, value) {
  const v = String(value).trim().toLowerCase();
  if (/^#[0-9a-f]{3}$/.test(v)) return "#" + [...v.slice(1)].map((x) => x + x).join("");
  if (/^#[0-9a-f]{6}$/.test(v)) return v;
  throw new Error(`"${key}": "${value}" no es un color hex (#rgb o #rrggbb)`);
}

function hsl(h) {
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
}

const mix = (a, b, w) => "#" + [1, 3, 5].map((i) =>
  Math.round(parseInt(a.slice(i, i + 2), 16) * (1 - w) + parseInt(b.slice(i, i + 2), 16) * w).toString(16).padStart(2, "0")).join("");

function themeToCss(theme) {
  if (!theme || typeof theme !== "object") throw new Error("El tema tiene que ser un objeto JSON");
  const c = theme.colors;
  if (!c || typeof c !== "object") throw new Error('Falta el objeto "colors"');
  for (const k of Object.keys(c)) if (!KEYS.includes(k)) throw new Error(`Clave desconocida "${k}". Válidas: ${KEYS.join(", ")}`);
  if (!c.background) throw new Error('Falta "colors.background"');
  const col = {};
  for (const k of Object.keys(c)) col[k] = normHex(k, c[k]);

  const bg = col.background, sidebar = col.sidebar || bg, card = col.card || sidebar;
  const popover = col.popover || card, input = col.input || popover, border = col.border || input;
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
  if (col.textSecondary) for (const n of ["--cds-text-secondary", "--cds-text-stays-secondary", "--cds-fizzy-lake-color-secondary",
    "--cds-fizzy-lake-color-plain-secondary", "--cds-fizzy-lake-color-solid-secondary"]) v(n, col.textSecondary);
  if (col.textMuted) for (const n of ["--cds-text-muted", "--cds-fizzy-lake-color-tertiary", "--cds-fizzy-lake-color-plain-muted",
    "--cds-fizzy-lake-color-solid-muted", "--cds-fizzy-lake-color-placeholder"]) v(n, col.textMuted);

  const name = String(theme.name || "sin nombre").replace(/\*\//g, "");
  return `/* claude-desktop-themes: ${name} */
@media (prefers-color-scheme: dark) {
*, :root {
${L.join("\n")}
}
html, body { background-color: ${bg} !important; }
}
`;
}

module.exports = { themeToCss, KEYS };

if (require.main === module) {
  const fs = require("fs");
  const [, , inp, out] = process.argv;
  if (!inp) { console.error("Uso: node theme-json.js tema.json [salida.css]"); process.exit(1); }
  try {
    const t = JSON.parse(fs.readFileSync(inp, "utf8"));
    const css = themeToCss(t);
    if (out) fs.writeFileSync(out, css);
    console.log(`Tema "${t.name || inp}" OK${out ? " → " + out : ""}`);
  } catch (e) {
    console.error(e instanceof SyntaxError ? "JSON inválido: " + e.message : e.message);
    process.exit(1);
  }
}
