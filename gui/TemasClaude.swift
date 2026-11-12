// Temas para Claude: interfaz para instalar temas de color en Claude Desktop.
// Por dentro corre Resources/instalar-tema-claude.command (el mismo instalador de Terminal).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tema

struct Theme: Identifiable, Hashable {
    var id: String { slug }
    let slug: String
    let name: String
    let colors: [String: String]
    var isCustom = false

    static let keys = ["background", "sidebar", "card", "popover", "input", "border", "text", "textSecondary", "textMuted"]

    // Misma cadena de valores por defecto que theme-json.js
    func hex(_ k: String) -> String {
        switch k {
        case "background": return colors["background"] ?? "#000000"
        case "sidebar": return colors["sidebar"] ?? hex("background")
        case "card": return colors["card"] ?? hex("sidebar")
        case "popover": return colors["popover"] ?? hex("card")
        case "input": return colors["input"] ?? hex("popover")
        case "border": return colors["border"] ?? hex("input")
        case "text": return colors["text"] ?? "#ececec"
        case "textSecondary": return colors["textSecondary"] ?? "#b4b4b4"
        case "textMuted": return colors["textMuted"] ?? "#8a8a8a"
        default: return "#ff00ff"
        }
    }
    func c(_ k: String) -> Color { Color(hex: hex(k)) }

    var json: Data {
        let obj: [String: Any] = ["name": name, "colors": colors]
        return try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }

    static func slugify(_ s: String) -> String {
        let f = s.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        let r = f.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(r).split(separator: "-").joined(separator: "-")
    }

    static func parse(_ data: Data, fallbackName: String) throws -> Theme {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let colors = obj["colors"] as? [String: Any] else {
            throw Msg("El JSON tiene que tener un objeto \"colors\".")
        }
        var out: [String: String] = [:]
        for (k, v) in colors {
            guard keys.contains(k) else { throw Msg("Clave desconocida \"\(k)\". Válidas: \(keys.joined(separator: ", "))") }
            guard let s = v as? String, Color.isHex(s) else { throw Msg("\"\(k)\" no es un color hex (#rgb o #rrggbb).") }
            out[k] = s.lowercased()
        }
        guard out["background"] != nil else { throw Msg("Falta \"colors.background\".") }
        let name = (obj["name"] as? String) ?? fallbackName
        return Theme(slug: slugify(name).isEmpty ? "tema" : slugify(name), name: name, colors: out, isCustom: true)
    }

    static let presets: [Theme] = [
        Theme(slug: "full-black", name: "Full Black", colors: [
            "background": "#000000", "sidebar": "#0a0a0a", "card": "#141414",
            "popover": "#1a1a1a", "input": "#262626", "border": "#333333"]),
        Theme(slug: "dracula", name: "Dracula", colors: [
            "background": "#282a36", "sidebar": "#21222c", "card": "#343746", "popover": "#44475a",
            "input": "#44475a", "border": "#6272a4", "text": "#f8f8f2", "textSecondary": "#d6d6e6", "textMuted": "#8b93b8"]),
        Theme(slug: "nord", name: "Nord", colors: [
            "background": "#2e3440", "sidebar": "#272c36", "card": "#3b4252", "popover": "#434c5e",
            "input": "#434c5e", "border": "#4c566a", "text": "#eceff4", "textSecondary": "#d8dee9", "textMuted": "#9aa5b8"]),
        Theme(slug: "solarized-dark", name: "Solarized Dark", colors: [
            "background": "#002b36", "sidebar": "#00252f", "card": "#073642", "popover": "#0a4251",
            "input": "#0a4251", "border": "#2a5561", "text": "#eee8d5", "textSecondary": "#93a1a1", "textMuted": "#6c8389"]),
        Theme(slug: "tokyo-night", name: "Tokyo Night", colors: [
            "background": "#1a1b26", "sidebar": "#16161e", "card": "#24283b", "popover": "#292e42",
            "input": "#292e42", "border": "#3b4261", "text": "#c0caf5", "textSecondary": "#a9b1d6", "textMuted": "#737aa2"]),
    ]
}

struct Msg: LocalizedError { let text: String; init(_ t: String) { text = t }; var errorDescription: String? { text } }

extension Color {
    static func isHex(_ s: String) -> Bool { s.range(of: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", options: .regularExpression) != nil }
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let v = UInt64(h, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

// MARK: - Estado y acciones

enum Phase: Equatable { case idle, running(String), done(String), failed(String) }

@MainActor
final class Model: ObservableObject {
    @Published var themes: [Theme] = Theme.presets
    @Published var selected: Theme = Theme.presets[0]
    @Published var version = "?"
    @Published var installed = false
    @Published var activeName: String?
    @Published var accepted = false
    @Published var phase: Phase = .idle
    @Published var log = ""
    @Published var showLog = false

    let appPath = ProcessInfo.processInfo.environment["APP"] ?? "/Applications/Claude.app"
    var isTest: Bool { appPath != "/Applications/Claude.app" }
    let themesDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()).appendingPathComponent(".claude/desktop-themes")
    var installer: String { Bundle.main.path(forResource: "instalar-tema-claude", ofType: "command") ?? "" }
    var claudeExists: Bool { FileManager.default.fileExists(atPath: appPath) }
    var busy: Bool { if case .running = phase { return true }; return false }

    init() { loadUserThemes(); refresh() }

    func refresh() {
        let plist = NSDictionary(contentsOfFile: appPath + "/Contents/Info.plist")
        version = plist?["CFBundleShortVersionString"] as? String ?? "?"
        let sig = Self.run("/usr/bin/codesign", ["-dv", appPath])
        installed = sig.contains("Signature=adhoc")
        activeName = nil
        if installed, let slug = try? String(contentsOf: themesDir.appendingPathComponent("active"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), slug != "none" {
            activeName = themes.first { $0.slug == slug }?.name ?? slug
            if let t = themes.first(where: { $0.slug == slug }), case .idle = phase { selected = t }
        }
    }

    func loadUserThemes() {
        let files = (try? FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            let slug = f.deletingPathExtension().lastPathComponent
            guard !themes.contains(where: { $0.slug == slug }), let d = try? Data(contentsOf: f),
                  let t = try? Theme.parse(d, fallbackName: slug) else { continue }
            themes.append(Theme(slug: slug, name: t.name, colors: t.colors, isCustom: true))
        }
    }

    func importJSON() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        p.message = "Elegí un JSON de colores"
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let t = try Theme.parse(Data(contentsOf: url), fallbackName: url.deletingPathExtension().lastPathComponent)
            themes.removeAll { $0.slug == t.slug && $0.isCustom }
            themes.append(t)
            selected = t
            phase = .idle
        } catch {
            phase = .failed("No pude cargar \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func apply() {
        let t = selected
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(t.slug).json")
        do { try t.json.write(to: tmp) } catch { phase = .failed(error.localizedDescription); return }
        let quick = installed
        Task {
            if !quick { await quitClaude() }
            await runInstaller(["--theme", tmp.path, "--yes"],
                               running: quick ? "Aplicando \(t.name)…" : "Instalando \(t.name)… (1-2 minutos)",
                               done: quick ? "\(t.name) aplicado. En Claude apretá Cmd+R para verlo."
                                           : "Listo. Claude se está abriendo: cuando macOS pida \"Claude Safe Storage\", poné tu contraseña y elegí \"Permitir siempre\". Después poné la apariencia en modo oscuro.")
        }
    }

    func uninstall() {
        Task {
            await quitClaude()
            await runInstaller(["--uninstall", "--yes"], running: "Restaurando Claude original…",
                               done: "Claude volvió a la versión original de Anthropic.")
        }
    }

    private func quitClaude() async {
        guard !isTest else { return }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop")
        guard !apps.isEmpty else { return }
        phase = .running("Cerrando Claude…")
        apps.forEach { $0.terminate() }
        for _ in 0..<60 where apps.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func runInstaller(_ args: [String], running: String, done: String) async {
        phase = .running(running)
        log = ""
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.shellPath
        let code: Int32 = await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [installer] + args
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.standardInput = FileHandle.nullDevice
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
                let clean = s.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression)
                Task { @MainActor in self.log += clean }
            }
            p.terminationHandler = { pr in
                pipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: pr.terminationStatus)
            }
            do { try p.run() } catch { cont.resume(returning: -1) }
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if code == 0 {
            phase = .done(done)
        } else {
            let last = log.split(separator: "\n").suffix(3).joined(separator: "\n")
            phase = .failed(last.isEmpty ? "El instalador terminó con error \(code)." : last)
            showLog = true
        }
        refresh()
    }

    // PATH del shell de login del usuario (node suele estar en Homebrew, nvm, volta...)
    static let shellPath: String = {
        let home = NSHomeDirectory()
        var parts = run("/bin/zsh", ["-lic", "print -r -- \"$PATH\""]).split(separator: "\n").last.map(String.init)?
            .split(separator: ":").map(String.init) ?? []
        parts += ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.volta/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        if let nvm = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            parts += nvm.sorted().reversed().map { "\(home)/.nvm/versions/node/\($0)/bin" }
        }
        var seen = Set<String>()
        return parts.filter { seen.insert($0).inserted }.joined(separator: ":")
    }()

    static func run(_ exe: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }
}

// MARK: - Vistas

struct MockClaude: View {
    let t: Theme
    var compact = false
    var body: some View {
        let r: CGFloat = compact ? 3 : 6
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: compact ? 4 : 9) {
                RoundedRectangle(cornerRadius: r).fill(t.c("input")).frame(height: compact ? 7 : 16)
                ForEach(0..<(compact ? 4 : 7), id: \.self) { i in
                    Capsule().fill(i < 2 ? t.c("textSecondary") : t.c("textMuted"))
                        .frame(width: CGFloat([46, 38, 52, 30, 44, 36, 48][i]) * (compact ? 0.55 : 1), height: compact ? 2.5 : 5)
                }
                Spacer()
            }
            .padding(compact ? 6 : 12)
            .frame(width: compact ? 42 : 120)
            .frame(maxHeight: .infinity)
            .background(t.c("sidebar"))
            Rectangle().fill(t.c("border")).frame(width: 0.5)
            VStack(spacing: compact ? 5 : 10) {
                Spacer()
                Capsule().fill(t.c("text")).frame(width: compact ? 40 : 150, height: compact ? 3.5 : 8)
                VStack(alignment: .leading, spacing: compact ? 3 : 7) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: compact ? 3 : 6) {
                            RoundedRectangle(cornerRadius: 1.5).stroke(t.c("textMuted"), lineWidth: 1).frame(width: compact ? 4 : 9, height: compact ? 3 : 7)
                            Capsule().fill(t.c("textSecondary")).frame(width: CGFloat([90, 60, 110][i]) * (compact ? 0.4 : 1), height: compact ? 2.5 : 5)
                        }
                    }
                }
                .padding(compact ? 5 : 10)
                .frame(maxWidth: compact ? 70 : 220, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: r).fill(t.c("card")))
                .overlay(RoundedRectangle(cornerRadius: r).stroke(t.c("border"), lineWidth: 0.5))
                Spacer()
                HStack {
                    Capsule().fill(t.c("textMuted")).frame(width: compact ? 30 : 120, height: compact ? 2.5 : 5)
                    Spacer()
                }
                .padding(.horizontal, compact ? 6 : 12)
                .frame(height: compact ? 12 : 30)
                .background(RoundedRectangle(cornerRadius: compact ? 4 : 10).fill(t.c("input")))
                .overlay(RoundedRectangle(cornerRadius: compact ? 4 : 10).stroke(t.c("border"), lineWidth: 0.5))
                .padding(.horizontal, compact ? 8 : 24)
                .padding(.bottom, compact ? 6 : 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(t.c("background"))
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 10))
        .overlay(RoundedRectangle(cornerRadius: compact ? 6 : 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

struct ThemeCard: View {
    let t: Theme
    let selected: Bool
    let active: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MockClaude(t: t, compact: true).frame(height: 70)
            HStack(spacing: 4) {
                Text(t.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if active { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green) }
                Spacer(minLength: 0)
            }
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(selected ? 0.08 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }
}

struct ContentView: View {
    @EnvironmentObject var m: Model
    let cols = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !m.claudeExists {
                banner("No encuentro Claude en \(m.appPath). Instalalo desde claude.ai/download.", "exclamationmark.triangle.fill", .orange)
            }
            HStack {
                Text("Elegí un tema").font(.headline)
                Spacer()
                Button(action: m.importJSON) { Label("Cargar JSON…", systemImage: "doc.badge.plus") }
                    .disabled(m.busy)
                    .help("Un JSON con \"colors\": background, sidebar, card, popover, input, border, text, textSecondary, textMuted")
            }
            LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
                ForEach(m.themes) { t in
                    ThemeCard(t: t, selected: t == m.selected, active: m.activeName == t.name)
                        .onTapGesture { if !m.busy { m.selected = t } }
                }
            }
            MockClaude(t: m.selected).frame(height: 180)
            if !m.installed { risks }
            status
            actions
        }
        .padding(22)
        .frame(width: 700)
    }

    var header: some View {
        HStack(spacing: 12) {
            AppIconView().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Temas para Claude").font(.system(size: 20, weight: .semibold))
                Text("Colores propios para Claude Desktop").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(m.installed ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(m.installed ? "Claude \(m.version) · \(m.activeName ?? "tema instalado")" : "Claude \(m.version) · original")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }

    var risks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Antes de instalar", systemImage: "exclamationmark.shield").font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                bullet("Claude Desktop no tiene temas: esto modifica la app y queda firmada ad hoc, no por Anthropic.")
                bullet("Al abrirla, macOS pide permiso para \"Claude Safe Storage\": elegí \"Permitir siempre\" o se pierde el login.")
                bullet("Dejan de andar las passkeys dentro de la app y el conector de Microsoft 365.")
                bullet("Hay que volver a dar Accesibilidad, Grabación de pantalla y Micrófono si los usás.")
                bullet("Cada actualización de Claude borra el tema: volvé a abrir esta app e instalalo de nuevo.")
                bullet("Se guarda una copia de la app original (~620 MB). \"Desinstalar\" la vuelve a poner.")
            }
            Toggle("Entiendo y quiero instalar", isOn: $m.accepted).toggleStyle(.checkbox).padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder var status: some View {
        switch m.phase {
        case .idle: EmptyView()
        case .running(let s):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(s).font(.callout) }
        case .done(let s): banner(s, "checkmark.circle.fill", .green)
        case .failed(let s): banner(s, "xmark.octagon.fill", .red)
        }
        if !m.log.isEmpty {
            DisclosureGroup("Detalles", isExpanded: $m.showLog) {
                ScrollView {
                    Text(m.log).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
            }
            .font(.callout)
        }
    }

    var actions: some View {
        HStack {
            if m.installed {
                Button("Desinstalar", role: .destructive, action: m.uninstall).disabled(m.busy)
            }
            Spacer()
            Button(action: m.apply) {
                Text(m.installed ? "Aplicar \(m.selected.name)" : "Instalar \(m.selected.name)").frame(minWidth: 140)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(m.busy || !m.claudeExists || (!m.installed && !m.accepted))
        }
    }

    func bullet(_ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); Text(s).fixedSize(horizontal: false, vertical: true) }
            .font(.system(size: 12)).foregroundStyle(.secondary)
    }
    func banner(_ s: String, _ icon: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(s).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.08)))
    }
}

struct AppIconView: View {
    let swatches = ["#000000", "#282a36", "#2e3440", "#002b36"]
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#2a2a2e"), Color(hex: "#0b0b0c")], startPoint: .top, endPoint: .bottom))
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: s * 0.07, style: .continuous)
                        .fill(Color(hex: swatches[i]))
                        .overlay(RoundedRectangle(cornerRadius: s * 0.07, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: max(1, s * 0.008)))
                        .frame(width: s * 0.42, height: s * 0.52)
                        .rotationEffect(.degrees(Double(i - 2) * 11 + 6), anchor: .bottom)
                        .offset(y: -s * 0.02)
                }
                Circle().fill(Color(hex: "#d97757")).frame(width: s * 0.14).offset(x: s * 0.17, y: s * 0.2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct TemasClaudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model = Model()

    init() { Snapshot.runIfRequested() }

    var body: some Scene {
        WindowGroup("Temas para Claude") {
            ContentView().environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

// Modo sin ventana para generar el ícono y capturas: --icon out.png | --snapshot out.png [--dark]
enum Snapshot {
    @MainActor static func runIfRequested() {
        let a = CommandLine.arguments
        func arg(_ k: String) -> String? { a.firstIndex(of: k).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }
        if let out = arg("--icon") {
            render(AnyView(AppIconView().frame(width: 1024, height: 1024)), size: CGSize(width: 1024, height: 1024), out: out, dark: true)
            exit(0)
        }
        // Prueba sin ventana del mismo flujo que el botón: APP=/copia/Claude.app TemasClaude --test-apply <n>|uninstall
        if let what = arg("--test-apply") {
            let m = Model()
            if what == "uninstall" { m.uninstall() } else { m.accepted = true; m.selected = m.themes[Int(what) ?? 0]; m.apply() }
            let end = Date().addingTimeInterval(900)
            repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) } while (m.busy || m.phase == .idle) && Date() < end
            print(m.log); print("PHASE:", m.phase); print("INSTALLED:", m.installed, m.activeName ?? "-")
            if case .done = m.phase { exit(0) } else { exit(1) }
        }
        if let out = arg("--snapshot") {
            let m = Model()
            if let i = arg("--select").flatMap(Int.init), i < m.themes.count { m.selected = m.themes[i] }
            let v = ContentView().environmentObject(m)
            render(AnyView(v.background(Color(nsColor: .windowBackgroundColor))), size: nil, out: out, dark: a.contains("--dark"))
            exit(0)
        }
    }
    @MainActor static func render(_ view: AnyView, size: CGSize?, out: String, dark: Bool) {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        let sz = size ?? host.fittingSize
        host.frame = CGRect(origin: .zero, size: sz)
        let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = app.appearance
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
    }
}
