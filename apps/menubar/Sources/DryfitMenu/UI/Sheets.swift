import DryfitAPI
import SwiftUI

/// The frame of a sheet (`.sheet`): 440 wide, 18 pt of padding, on the window's colour.
private struct SheetFrame<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .font(Theme.body)
      .foregroundStyle(Theme.text)
      .padding(18)
      .frame(width: 440)
      .background(Theme.window)
      .presentationBackground(Theme.window)
  }
}

/// A sheet's tile, title and one line about what it shows (`.sh`).
private struct SheetHeader: View {
  let icon: Icon.Kind
  var tint = Theme.releaseTint
  var color = Theme.release
  let title: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 12) {
      Icon(kind: icon, size: 20, color: color).frame(width: 36, height: 36).background(tint, in: .rect(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 0) {
        Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1).lh(15)
        Text(subtitle).muted().lineLimit(1).truncationMode(.middle)
      }
    }
    .padding(.bottom, 14)
  }
}

/// The label above a field (`label`): 12 pt semibold, 12 above it and 5 below.
private struct FieldLabel<Extra: View>: View {
  let text: String
  @ViewBuilder var extra: Extra
  var body: some View {
    HStack(spacing: 4) {
      Text(text).font(.system(size: 12, weight: .semibold))
      extra
    }
    .lh(12)
    .padding(.top, 12)
    .padding(.bottom, 5)
  }
}

extension FieldLabel where Extra == EmptyView {
  fileprivate init(_ text: String) { self.init(text: text) { EmptyView() } }
}

private struct Note: View {
  let text: String
  var bad = false
  var body: some View {
    Text(text).foregroundStyle(bad ? Theme.bad : Theme.muted).font(.system(size: 12)).lh(12)
      .fixedSize(horizontal: false, vertical: true).padding(.top, 5)
  }
}

/// The buttons at the foot of a sheet (`.bar`).
private struct Bar<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    HStack(spacing: 8) { Spacer(); content }.padding(.top, 18)
  }
}

// MARK: Library

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
    SheetFrame {
      if let preview {
        form(preview)
      } else if let loadError {
        SheetHeader(icon: .library, title: "Not a library", subtitle: abbreviatedPath(root))
        Text(loadError).font(.system(size: 12.5)).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
        Bar {
          // Nothing to add here: another folder, or out. Return takes the way out, Escape too.
          Button("Choose another folder…") {
            dismiss()
            Task { await model.chooseLibraryFolder(navigation: navigation) }
          }
          .buttonStyle(.flat(bar: true))
          Button("Close") { dismiss() }.buttonStyle(.flat(.primary, bar: true)).keyboardShortcut(.defaultAction)
        }
      } else {
        HStack(spacing: 8) {
          Spin()
          Text("Reading \(projectName(root))'s package.json…").foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        Bar {
          Button("Cancel") { dismiss() }.buttonStyle(.flat(bar: true)).keyboardShortcut(.cancelAction)
          Button("Add library") {}.buttonStyle(.flat(.primary, bar: true)).disabled(true)
        }
      }
    }
    // Closed mid-save, the save would still finish and then move the window to the library.
    .interactiveDismissDisabled(saving)
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
      icon: .library, title: preview.registered ? "Build settings for \(preview.name)" : preview.name,
      subtitle: "\(preview.version) · \(abbreviatedPath(preview.root))")
    FieldLabel("Build command")
    Well(style: .input) {
      TextField("", text: $buildLine, prompt: Text("No build step").foregroundStyle(Theme.muted))
        .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).focusEffectDisabled()
        .accessibilityLabel("Build command")
    }
    (Text("Runs in the library's folder before each publish.") + (preview.registered ? Text("") : Text(" ") + Text(detectedNote(preview)).bold().foregroundColor(Theme.release)))
      .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
    FieldLabel("Publish folder")
    Well(style: .input) {
      Text(publishDir == preview.root ? "The library's folder" : relative(publishDir, to: preview.root))
        .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.head)
      Spacer(minLength: 8)
      Button("Choose…") { Task { await choosePublishDir() } }.buttonStyle(.flat(small: true))
    }
    Note(text: "The folder whose package.json gets published, usually where the build writes its output.")
    if let saveError {
      Note(text: "Couldn't save: \(saveError)", bad: true).padding(.top, 8)
    }
    Bar {
      if saving { Spin() }
      Button("Cancel") { dismiss() }.buttonStyle(.flat(bar: true)).keyboardShortcut(.cancelAction).disabled(saving)
      Button(preview.registered ? "Save" : "Add library") { save() }
        .buttonStyle(.flat(.primary, bar: true))
        .keyboardShortcut(.defaultAction)
        .disabled(publishDir.isEmpty || saving)
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

// MARK: Group

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
    SheetFrame {
      // Groups can't be renamed, so editing names the group in the title instead of a greyed-out field.
      if case .edit(let group) = request {
        SheetHeader(
          icon: .group, tint: Theme.purpleTint, color: Theme.purple, title: "Edit \(group.name)",
          subtitle: "Choose the apps dryfit links and restores together.")
      } else {
        SheetHeader(
          icon: .group, tint: Theme.purpleTint, color: Theme.purple, title: "New group",
          subtitle: "A group links a library into all of its apps at once.")
        FieldLabel("Name")
        Well(style: nameTaken ? .error : .input) {
          TextField("", text: $name, prompt: Text("storefront").foregroundStyle(Theme.muted))
            .textFieldStyle(.plain).focusEffectDisabled().accessibilityLabel("Name")
        }
        if nameTaken { Note(text: "There's already a group called \(trimmedName).", bad: true) }
      }
      FieldLabel(text: "Apps") {
        if !members.isEmpty { Text("· \(members.count) selected").font(.system(size: 12)).foregroundStyle(Theme.muted) }
      }
      // Thirty apps need finding, not scrolling.
      Well {
        Icon(kind: .search, size: 13)
        TextField("", text: $search, prompt: Text("Filter apps").foregroundStyle(Theme.muted))
          .textFieldStyle(.plain).focusEffectDisabled().accessibilityLabel("Filter apps")
      }
      .padding(.bottom, 8)
      ScrollView {
        VStack(spacing: 0) {
          if projects.isEmpty {
            row { Text("No apps found in your project folders. Add one below.").foregroundStyle(Theme.muted) }
          }
          if shown.isEmpty && !projects.isEmpty {
            row { Text("No app matches \u{201C}\(search)\u{201D}.").foregroundStyle(Theme.muted) }
          }
          ForEach(shown, id: \.self) { project in
            Hair()
            row {
              Check(
                isOn: Binding(
                  get: { members.contains(project) },
                  set: { on in
                    if on { members.append(project) } else { members.removeAll { $0 == project } }
                  }),
                label: projectName(project))
              Text(projectName(project)).font(.system(size: 13, weight: .medium)).lh(13)
              Spacer(minLength: 8)
              Text(abbreviatedPath(project)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.muted)
                .lineLimit(1).truncationMode(.head)
            }
          }
          Hair()
          row {
            Spacer()
            Button("Add app…") { Task { await addFolder() } }.buttonStyle(.flat(small: true))
          }
        }
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
      .frame(maxHeight: 220)
      .fixedSize(horizontal: false, vertical: true)
      .background(Theme.card, in: .rect(cornerRadius: 10))
      .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder, lineWidth: 0.5) }
      .clipShape(.rect(cornerRadius: 10))
      if let saveError { Note(text: "Couldn't save: \(saveError)", bad: true).padding(.top, 8) }
      Bar {
        Button("Cancel") { dismiss() }.buttonStyle(.flat(bar: true)).keyboardShortcut(.cancelAction).disabled(saving)
        Button(isEditing ? "Save" : "Create group") { save() }
          .buttonStyle(.flat(.primary, bar: true))
          .keyboardShortcut(.defaultAction)
          .disabled(trimmedName.isEmpty || nameTaken || members.isEmpty || saving)
      }
    }
    .interactiveDismissDisabled(saving)
    .onAppear {
      if case .edit(let group) = request {
        name = group.name
        members = group.consumers
      }
    }
  }

  private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: 10) { content() }.padding(.horizontal, 12).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
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
