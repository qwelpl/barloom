import AppKit
import SwiftUI

struct StartMenuView: View {
    @ObservedObject var model: TaskbarModel
    @ObservedObject var library: AppLibrary
    let dismiss: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(92), spacing: 4), count: 6)

    private var pinned: [AppEntry] {
        model.items.filter(\.pinned).map { AppEntry(url: $0.url, name: $0.name) }
    }

    private var results: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return library.apps
            .filter { $0.name.localizedCaseInsensitiveContains(q) }
            .sorted { rank($0.name, q) < rank($1.name, q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 18)

            ScrollView {
                if query.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("Pinned")
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(pinned) { tile($0) }
                        }
                        sectionHeader("All apps").padding(.top, 14)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(library.apps) { tile($0) }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                } else if results.isEmpty {
                    Text("No apps match “\(query)”")
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                            row(entry, highlighted: index == 0)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .scrollIndicators(.never)

            footer
        }
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search for apps", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onSubmit {
                    if let first = results.first { launch(first) }
                }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(searchFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .padding(.leading, 10)
            .padding(.bottom, 2)
    }

    private func tile(_ entry: AppEntry) -> some View {
        Button { launch(entry) } label: {
            VStack(spacing: 6) {
                AppIcon(url: entry.url, size: 32)
                Text(entry.name)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28, alignment: .top)
            }
            .frame(width: 92, height: 82)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlateButtonStyle(pressScale: 0.94))
        .contextMenu { entryMenu(entry) }
    }

    private func row(_ entry: AppEntry, highlighted: Bool) -> some View {
        Button { launch(entry) } label: {
            HStack(spacing: 12) {
                AppIcon(url: entry.url, size: 32)
                Text(entry.name).font(.system(size: 13))
                Spacer()
                if highlighted {
                    Image(systemName: "return")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlateButtonStyle(selected: highlighted))
        .contextMenu { entryMenu(entry) }
    }

    @ViewBuilder private func entryMenu(_ entry: AppEntry) -> some View {
        if model.isPinned(entry.url) {
            Button("Unpin from taskbar") { model.unpin(entry.url) }
        } else {
            Button("Pin to taskbar") { model.pin(entry.url) }
        }
        Button("Show in Finder") {
            model.revealInFinder(entry.url)
            dismiss()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.62),
                                              Color(red: 0.55, green: 0.4, blue: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .overlay(
                    Text(String(NSFullUserName().prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                )
            Text(NSFullUserName())
                .font(.system(size: 12.5))
            Spacer()

            Menu {
                Picker("Taskbar Size", selection: $model.size) {
                    ForEach(TaskbarSize.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Keep Windows Above Taskbar", isOn: $model.managesDock)
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.launchesAtLogin = $0 }
                ))
                Divider()
                Button("Quit Barloom") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 36, height: 36)
            .help("Barloom settings")

            Menu {
                Button("Sleep") { act(Power.sleep) }
                Button("Turn Off Display") { act(Power.displayOff) }
                Divider()
                Button("Log Out…") { act(Power.logOut) }
                Button("Restart…") { act(Power.restart) }
                Button("Shut Down…") { act(Power.shutDown) }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 36, height: 36)
            .help("Power")
        }
        .padding(.horizontal, 40)
        .frame(height: 64)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
    }

    private func launch(_ entry: AppEntry) {
        model.open(entry.url)
        dismiss()
    }

    private func act(_ action: () -> Void) {
        dismiss()
        action()
    }

    /// Prefix matches first, then word-start matches, then anything else.
    private func rank(_ name: String, _ q: String) -> Int {
        let lower = name.lowercased(), q = q.lowercased()
        if lower.hasPrefix(q) { return 0 }
        if lower.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 1 }
        return 2
    }
}
