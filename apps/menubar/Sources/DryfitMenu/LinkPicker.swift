import DryfitAPI
import SwiftUI

/// The apps that could be linked, in name order, narrowed to those whose name or folder contains every
/// word typed. Case and accents are ignored. With thirty apps this is how one is found.
func filterLinkCandidates(_ candidates: [DiscoveredConsumer], matching query: String) -> [DiscoveredConsumer] {
  let sorted = candidates.sorted {
    projectName($0.root).localizedStandardCompare(projectName($1.root)) == .orderedAscending
  }
  let words = query.split(whereSeparator: \.isWhitespace)
  guard !words.isEmpty else { return sorted }
  return sorted.filter { consumer in
    let haystack = projectName(consumer.root) + " " + abbreviatedPath(consumer.root)
    return words.allSatisfy { haystack.localizedStandardContains($0) }
  }
}

/// A search over the apps that depend on a library and are not linked to it, each linked with one
/// click (the mockup's `.pop`). It is drawn inside the card, not in a popover: a popover is a window of
/// its own, and the menu bar panel closes when it loses focus.
struct LinkPicker: View {
  let library: String
  let candidates: [DiscoveredConsumer]
  let model: MenuModel
  let done: () -> Void
  @State private var query = ""
  @FocusState private var searching: Bool

  var body: some View {
    let shown = filterLinkCandidates(candidates, matching: query)
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Well(style: .input) {
          Icon(kind: .search, size: 13, color: Theme.muted)
          TextField("Search \(candidates.count) apps", text: $query)
            .textFieldStyle(.plain)
            .focused($searching)
            .accessibilityLabel("Search apps that use \(library)")
        }
        Button("Done", action: done).buttonStyle(.flat)
      }
      .padding(10)
      Hair()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(shown) { consumer in
            HStack(spacing: 8) {
              Icon(kind: .app, size: 16, color: Theme.muted)
              VStack(alignment: .leading, spacing: 0) {
                Text(projectName(consumer.root)).font(Theme.bodySemibold).lineLimit(1)
                Text([consumer.packageManager.name, abbreviatedPath(consumer.root)].compactMap { $0 }.joined(separator: " · "))
                  .font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
              }
              Spacer(minLength: 8)
              Button("Link") { Task { await model.link(library, into: consumer.root) } }
                .buttonStyle(.flat(.accent, small: true))
                .disabled(model.isBusy(.link(library, consumer.root)))
                .help("Install the dev build of \(library) into \(projectName(consumer.root))")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
          }
          if shown.isEmpty {
            Text("No app matches “\(query)”").foregroundStyle(Theme.muted).padding(12)
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(maxHeight: 250)
      .fixedSize(horizontal: false, vertical: true)
      Hair()
      HStack {
        Text("\(candidates.count) depend on \(library)").muted()
        Spacer(minLength: 8)
        Button("Choose folder…") { Task { await model.chooseAppAndLink(library) } }.buttonStyle(.flat(.accent, small: true))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .onAppear { searching = true }
  }
}
