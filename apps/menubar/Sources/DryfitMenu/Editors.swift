import DryfitAPI
import SwiftUI

/// Adds a library, or changes how one is built: shows what dryfit detected and lets the user correct
/// the build command and the folder that gets published.
struct LibraryEditor: View {
  let root: String
  let model: MenuModel
  let navigation: AppNavigation
  @Environment(\.dismiss) private var dismiss
  @State private var preview: LibraryPreview?
  @State private var buildLine = ""
  @State private var publishDir = ""
  @State private var loadError: String?
  @State private var saveError: String?
  @State private var saving = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let preview {
        form(preview)
      } else if let loadError {
        SheetHeader(symbol: "shippingbox", title: "Not a library", subtitle: abbreviatedPath(root))
        Callout(condition: .failed, title: "dryfit can't use this folder", message: loadError).padding(.top, 14)
      } else {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Reading \(projectName(root))'s package.json…").foregroundStyle(DS.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
      }
      HStack(spacing: 8) {
        if saving { ProgressView().controlSize(.small) }
        Spacer()
        if loadError != nil {
          // Nothing to add: one way out, not a Cancel beside a button that can never be clicked.
          // Return through the default action, Escape through the exit command below.
          Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
        } else {
          Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
          Button(preview?.registered == true ? "Save" : "Add library") { save() }
            .keyboardShortcut(.defaultAction)
            .disabled(preview == nil || publishDir.isEmpty || saving)
        }
      }
      .padding(.top, 14)
    }
    .font(DS.body)
    .padding(20)
    .frame(width: 440)
    // Closed mid-save, the save would still finish and then move the window to the library.
    .interactiveDismissDisabled(saving)
    // The error state has no Cancel to carry Escape.
    .onExitCommand { if loadError != nil { dismiss() } }
    .task {
      do {
        let found = try await model.inspect(root)
        buildLine = found.build?.line ?? ""
        publishDir = found.publishDir
        preview = found
      } catch {
        loadError = error.localizedDescription
      }
    }
  }

  @ViewBuilder private func form(_ preview: LibraryPreview) -> some View {
    SheetHeader(
      symbol: "shippingbox", title: preview.registered ? "Build settings for \(preview.name)" : preview.name,
      subtitle: "\(preview.version) · \(abbreviatedPath(preview.root))")
    SheetLabel("Build command")
    TextField("Build command", text: $buildLine, prompt: Text("No build step"))
      .field(monospaced: true)
    Footnote("Runs in the library's folder before each publish." + (preview.registered ? "" : " \(detectedNote(preview))"))
    SheetLabel("Publish folder")
    HairlineGroup {
      GroupRow {
        Text(publishDir == preview.root ? "The library's folder" : relative(publishDir, to: preview.root))
          .foregroundStyle(DS.muted)
          .lineLimit(1)
          .truncationMode(.head)
        Spacer(minLength: 8)
        Button("Choose…") { Task { await choosePublishDir() } }.buttonStyle(.pill)
      }
    }
    Footnote("The folder whose package.json gets published, usually where the build writes its output.")
    if let saveError {
      Callout(condition: .failed, title: "Couldn't save", message: saveError).padding(.top, 12)
    }
  }

  /// "dist/ui" for a folder inside the library, the full path otherwise.
  private func relative(_ path: String, to root: String) -> String {
    let prefix = root.hasSuffix("/") ? root : root + "/"
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : abbreviatedPath(path)
  }

  private func detectedNote(_ preview: LibraryPreview) -> String {
    switch preview.detected {
    case "nx": "Detected an Nx library."
    case "angular": "Detected an Angular CLI library."
    case "npm-script": "Detected the build script in package.json."
    default: "dryfit found no build step. Add a command if the library needs one."
    }
  }

  private func choosePublishDir() async {
    let chosen = await FolderPanel.choose(
      prompt: "Choose", message: "Choose the folder whose package.json gets published.", startingAt: root)
    if let folder = chosen.first { publishDir = folder }
  }

  private func save() {
    saving = true
    saveError = nil
    Task {
      do {
        try await model.register(root, publishDir: publishDir, build: BuildCommand(line: buildLine))
        if let name = preview?.name { navigation.selection = .library(name) }
        dismiss()
      } catch {
        saveError = error.localizedDescription
      }
      saving = false
    }
  }
}

/// Creates a group, or changes which apps one holds.
struct GroupEditor: View {
  let request: GroupEditorRequest
  let model: MenuModel
  let navigation: AppNavigation
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var members: [String] = []
  @State private var extra: [String] = []
  @State private var saveError: String?
  @State private var saving = false
  @State private var search = ""

  /// The apps whose name or folder holds every word typed.
  private var shown: [String] {
    let words = search.split(separator: " ")
    return projects.filter { project in
      words.allSatisfy { projectName(project).localizedStandardContains($0) || project.localizedStandardContains($0) }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Groups can't be renamed, so editing names the group in the title instead of a greyed-out field.
      if case .edit(let group) = request {
        SheetHeader(
          symbol: "square.stack.3d.up", tint: .purple, title: "Edit \(group.name)",
          subtitle: "Choose the apps dryfit links and restores together.")
      } else {
        SheetHeader(
          symbol: "square.stack.3d.up", tint: .purple, title: "New group",
          subtitle: "A group links a library into all of its apps at once.")
        SheetLabel("Name")
        TextField("Name", text: $name, prompt: Text("storefront"))
          .field()
        if nameTaken {
          Label("There's already a group called \(trimmedName).", systemImage: "exclamationmark.triangle.fill")
            .font(DS.caption).foregroundStyle(DS.badText).padding(.top, 4)
        }
      }
      SheetLabel(members.isEmpty ? "Apps" : "Apps · \(members.count) selected")
      // Thirty apps need finding, not scrolling.
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(DS.muted).accessibilityHidden(true)
        TextField("Filter apps", text: $search, prompt: Text("Filter apps")).textFieldStyle(.plain)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(DS.neutralFill, in: .rect(cornerRadius: DS.buttonRadius))
      .padding(.bottom, 8)
      ScrollView {
        HairlineGroup {
          if projects.isEmpty {
            GroupRow { Text("No apps found in your project folders. Add one below.").foregroundStyle(DS.muted) }
          }
          if shown.isEmpty && !projects.isEmpty {
            GroupRow { Text("No app matches \u{201C}\(search)\u{201D}.").foregroundStyle(DS.muted) }
          }
          ForEach(shown, id: \.self) { project in
            GroupRow {
              Toggle(isOn: Binding(
                get: { members.contains(project) },
                set: { on in
                  if on { members.append(project) } else { members.removeAll { $0 == project } }
                })
              ) {
                Text(projectName(project))
              }
              .toggleStyle(.checkbox13)
              Spacer(minLength: 8)
              Text(abbreviatedPath(project)).font(DS.mono).foregroundStyle(DS.muted).lineLimit(1)
                .truncationMode(.head)
            }
          }
          GroupRow {
            Spacer()
            Button("Add app…") { Task { await addFolder() } }.buttonStyle(.pill)
          }
        }
        .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollIndicators(.hidden)
      .frame(maxHeight: 320)
      .fixedSize(horizontal: false, vertical: true)
      if let saveError {
        Callout(condition: .failed, title: "Couldn't save", message: saveError).padding(.top, 12)
      }
      HStack(spacing: 8) {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
        Button(isEditing ? "Save" : "Create group") { save() }
          .buttonStyle(.primaryPill)
          .keyboardShortcut(.defaultAction)
          .disabled(trimmedName.isEmpty || nameTaken || members.isEmpty || saving)
      }
      .padding(.top, 14)
    }
    .font(DS.body)
    .padding(20)
    .frame(width: 440)
    .interactiveDismissDisabled(saving)
    .onAppear {
      if case .edit(let group) = request {
        name = group.name
        members = group.consumers
      }
    }
  }

  private var isEditing: Bool {
    if case .edit = request { true } else { false }
  }

  private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

  /// Saving a new group under an existing name would replace that group's apps.
  private var nameTaken: Bool {
    !isEditing && model.groups.contains { $0.name == trimmedName }
  }

  private var projects: [String] {
    var all = model.knownProjects
    for path in extra + members where !all.contains(path) { all.append(path) }
    return all
  }

  private func addFolder() async {
    let chosen = await FolderPanel.choose(
      prompt: "Add", message: "Choose apps to add to the group.", multiple: true, startingAt: model.roots?.first)
    for path in chosen where !projects.contains(path) { extra.append(path) }
    for path in chosen where !members.contains(path) { members.append(path) }
  }

  private func save() {
    saving = true
    saveError = nil
    Task {
      do {
        try await model.saveGroup(trimmedName, consumers: members)
        navigation.selection = .group(trimmedName)
        dismiss()
      } catch {
        saveError = error.localizedDescription
      }
      saving = false
    }
  }
}

/// A sheet's tile, title and one line about what it shows.
private struct SheetHeader: View {
  let symbol: String
  var tint = Color.teal
  let title: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 10) {
      Tile(symbol: symbol, tint: tint, size: 30)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(DS.sheetTitle).lineLimit(1)
        Text(subtitle).font(DS.caption).foregroundStyle(DS.muted).lineLimit(1).truncationMode(.middle)
      }
    }
  }
}

/// The label above a field in a sheet: 11 pt, 12 pt above it.
private struct SheetLabel: View {
  let text: String
  let top: CGFloat
  init(_ text: String, top: CGFloat = 12) {
    self.text = text
    self.top = top
  }

  var body: some View {
    Text(text).font(DS.caption).foregroundStyle(DS.muted).padding(.top, top).padding(.bottom, 4)
  }
}
