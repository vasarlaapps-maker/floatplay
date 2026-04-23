import SwiftUI

// MARK: - Built-in platforms (always shown, not removable)

private let builtInOTT: [(name: String, url: String)] = [
    ("YouTube",    "https://www.youtube.com"),
    ("Netflix",    "https://www.netflix.com"),
    ("Prime",      "https://www.primevideo.com"),
    ("Disney+",    "https://www.disneyplus.com"),
    ("Apple TV+",  "https://tv.apple.com"),
    ("Hulu",       "https://www.hulu.com"),
    ("Max",        "https://www.max.com"),
    ("Peacock",    "https://www.peacocktv.com"),
    ("Paramount+", "https://www.paramountplus.com"),
    ("ESPN+",      "https://www.espnplus.com"),
]

// MARK: - Custom platform persistence

final class OTTStore: ObservableObject {
    struct Platform: Codable, Identifiable {
        let id: UUID
        var name: String
        var url: String
        init(name: String, url: String) {
            self.id = UUID(); self.name = name; self.url = url
        }
    }

    @Published private(set) var custom: [Platform] = [] {
        didSet { save() }
    }

    private let key = "customOTTPlatforms"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Platform].self, from: data) {
            custom = decoded
        }
    }

    func add(name: String, url: String) {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.hasPrefix("http://") && !u.hasPrefix("https://") { u = "https://" + u }
        custom.append(Platform(name: name.trimmingCharacters(in: .whitespacesAndNewlines), url: u))
    }

    func remove(id: UUID) {
        custom.removeAll { $0.id == id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Add-platform popover

private struct AddPlatformPopover: View {
    @ObservedObject var store: OTTStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var url  = ""

    var canAdd: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                       !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Platform").font(.headline)
            TextField("Name (e.g. SunNXT)", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            TextField("URL (e.g. sunnxt.com)", text: $url)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.borderless)
                Button("Add") {
                    store.add(name: name, url: url)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
                .keyboardShortcut(.return)
            }
        }
        .padding(14)
    }
}

// MARK: - Main view

struct ContentView: View {
    @StateObject private var controller = BrowserController()
    @StateObject private var ottStore   = OTTStore()
    @State private var urlFieldText = "https://www.youtube.com"
    @State private var showAddPopover  = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ottBar
            Divider()
            YouTubeBrowserView(controller: controller)
        }
        .onChange(of: controller.displayURL) { newURL in
            urlFieldText = newURL
        }
    }

    // MARK: - OTT shortcut bar

    var ottBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Built-in pills
                    ForEach(builtInOTT, id: \.name) { item in
                        pillButton(label: item.name) { controller.loadURL(item.url) }
                    }
                    // Custom pills with ✕ remove button
                    ForEach(ottStore.custom) { item in
                        HStack(spacing: 0) {
                            pillButton(label: item.name) { controller.loadURL(item.url) }
                            Button {
                                ottStore.remove(id: item.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 2)
                                    .padding(.trailing, 5)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(item.name)")
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }

            // + button to add custom platform
            Button {
                showAddPopover = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("Add a streaming platform")
            .popover(isPresented: $showAddPopover, arrowEdge: .bottom) {
                AddPlatformPopover(store: ottStore, isPresented: $showAddPopover)
            }
            .padding(.trailing, 6)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func pillButton(label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Toolbar

    var toolbar: some View {
        HStack(spacing: 4) {
            Button { controller.goBack() } label: {
                Image(systemName: "chevron.left").frame(width: 26, height: 26)
            }
            .disabled(!controller.canGoBack).buttonStyle(.borderless).help("Back")

            Button { controller.goForward() } label: {
                Image(systemName: "chevron.right").frame(width: 26, height: 26)
            }
            .disabled(!controller.canGoForward).buttonStyle(.borderless).help("Forward")

            Button { controller.reload() } label: {
                Image(systemName: controller.isLoading ? "xmark" : "arrow.clockwise")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless).help(controller.isLoading ? "Stop" : "Reload")

            Button { controller.goHome() } label: {
                Image(systemName: "house").frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless).help("Home (YouTube)")

            TextField("Enter URL…", text: $urlFieldText, onCommit: {
                controller.loadURL(urlFieldText)
            })
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))

            Button { controller.floatCurrentVideo() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pip.fill")
                    Text("Float").font(.caption).fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red)
                .cornerRadius(6)
            }
            .buttonStyle(.borderless)
            .help("Float current page above all apps")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor))
    }
}


#Preview {
    ContentView()
}
