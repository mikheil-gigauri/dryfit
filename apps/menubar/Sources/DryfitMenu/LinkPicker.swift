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
/// click. It is drawn inside the card, not in a popover: a popover is a window of its own, and the
/// menu bar panel closes when it loses focus.
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
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass").foregroundStyle(DS.muted).accessibilityHidden(true)
          TextField("Search \(candidates.count) apps", text: $query)
            .textFieldStyle(.plain)
            .focused($searching)
            .accessibilityLabel("Search apps that use \(library)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(DS.neutralFill, in: .rect(cornerRadius: DS.buttonRadius))
        Button("Done", action: done).buttonStyle(.pill)
      }
      .padding(10)
      Hairline()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(shown) { consumer in
            HStack(spacing: 8) {
              Image(systemName: "macwindow").foregroundStyle(DS.muted).frame(width: 18).accessibilityHidden(true)
              TwoLine(
                title: projectName(consumer.root),
                caption: [consumer.packageManager.name, abbreviatedPath(consumer.root)].compactMap { $0 }
                  .joined(separator: " · "), titleFont: DS.rowTitle)
              Spacer(minLength: 8)
              Button("Link") { Task { await model.link(library, into: consumer.root) } }
                .buttonStyle(.accentPill(busy: model.isBusy(.link(library, consumer.root))))
                .help("Install the dev build of \(library) into \(projectName(consumer.root))")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
          }
          if shown.isEmpty {
            Text("No app matches “\(query)”").foregroundStyle(DS.muted).padding(12)
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(maxHeight: 220)
      .fixedSize(horizontal: false, vertical: true)
      Hairline()
      HStack {
        Text("\(candidates.count) depend on \(library)").font(DS.caption).foregroundStyle(DS.muted)
        Spacer(minLength: 8)
        Button("Choose folder…") { Task { await model.chooseAppAndLink(library) } }.buttonStyle(.pill)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .onAppear { searching = true }
  }
}
