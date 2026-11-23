import AppKit
import SwiftUI

/// The failures this session, with each one's full output: what a notification opens. Drawn from the
/// mockup's `.fw`: a list of them on the left when there are several, the output of the chosen one.
public struct FailureView: View {
  let failures: [Failure]
  @Binding var selection: Failure.ID?
  /// Brings the dryfit window up on a library's page.
  let openLibrary: (String) -> Void

  public init(
    failures: [Failure], selection: Binding<Failure.ID?>, openLibrary: @escaping (String) -> Void = { _ in }
  ) {
    self.failures = failures
    self._selection = selection
    self.openLibrary = openLibrary
  }

  public var body: some View {
    HStack(spacing: 0) {
      if failures.count > 1 { list }
      if let failure = selected {
        Detail(failure: failure, openLibrary: openLibrary)
      } else {
        VStack(spacing: 0) {
          Text("✓").font(.system(size: 26)).foregroundStyle(Theme.ok)
          Text("No failures").font(Theme.bodySemibold).foregroundStyle(Theme.text).padding(.top, 8)
          Text("Everything dryfit ran this session worked.").foregroundStyle(Theme.muted)
        }
        .lh(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .font(Theme.body)
    .foregroundStyle(Theme.text)
    .frame(minWidth: 520, minHeight: 320)
    .background(Theme.window)
    .onAppear { if selection == nil { selection = failures.first?.id } }
  }

  private var list: some View {
    ScrollView {
      VStack(spacing: 0) {
        ForEach(failures) { failure in
          let chosen = failure.id == selected?.id
          HStack(alignment: .top, spacing: 8) {
            StatusGlyph(kind: .failed, size: 14).padding(.top, 1)
            VStack(alignment: .leading, spacing: 0) {
              Text(failure.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2).lh(12.5)
              Text(failure.date, format: .dateTime.hour().minute()).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lh(11.5)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(chosen ? Theme.selection : .clear, in: .rect(cornerRadius: 8))
          .contentShape(.rect(cornerRadius: 8))
          .onTapGesture { selection = failure.id }
          .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 12)
    }
    .frame(width: 230)
    .background(Theme.sidebar)
    .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    .focusable()
    .focusEffectDisabled()
    .onKeyPress(.upArrow) { step(-1) }
    .onKeyPress(.downArrow) { step(1) }
  }

  private func step(_ offset: Int) -> KeyPress.Result {
    guard let current = failures.firstIndex(where: { $0.id == selected?.id }) else { return .ignored }
    selection = failures[min(max(current + offset, 0), failures.count - 1)].id
    return .handled
  }

  private var selected: Failure? {
    failures.first { $0.id == selection } ?? failures.first
  }
}

private struct Detail: View {
  let failure: Failure
  let openLibrary: (String) -> Void
  @Environment(\.timeZone) private var timeZone

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        StatusGlyph(kind: .failed, size: 18)
        VStack(alignment: .leading, spacing: 0) {
          Text(failure.title).font(.system(size: 15, weight: .semibold)).lineLimit(2).lh(15)
          Text(subtitle).muted().lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Button("Copy output") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(failure.detail, forType: .string)
        }
        .buttonStyle(.flat(small: true))
        if let library = failure.library {
          Button("Open library") { openLibrary(library) }.buttonStyle(.flat(small: true))
        }
      }
      ScrollView([.vertical, .horizontal]) {
        Text(failure.detail.isEmpty ? "No output was captured." : failure.detail)
          .font(Theme.mono)
          .lineSpacing(4.8)
          .foregroundStyle(Theme.text)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
      }
      // Opens on the output's first line, not wherever the content's centre falls.
      .defaultScrollAnchor(.topLeading)
      .background(Theme.code, in: .rect(cornerRadius: 10))
      .padding(.top, 12)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
  }

  /// "Today at 14:32 · ~/repos/ui-lib".
  private var subtitle: String {
    [when, failure.consumer.map(abbreviatedPath)].compactMap { $0 }.joined(separator: " · ")
  }

  /// "Today at 14:32".
  private var when: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    formatter.timeZone = timeZone
    return formatter.string(from: failure.date)
  }
}

/// Owns the failures window, so a notification or the menu can bring it forward.
public final class FailureWindow {
  private var window: NSWindow?
  private let model: MenuModel
  private let openLibrary: (String) -> Void

  public init(model: MenuModel, openLibrary: @escaping (String) -> Void = { _ in }) {
    self.model = model
    self.openLibrary = openLibrary
  }

  public func show(selecting id: Failure.ID?) {
    let root = FailureWindowRoot(model: model, initial: id, openLibrary: openLibrary)
    if let window {
      window.contentView = NSHostingView(rootView: root)
    } else {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 760, height: 440),
        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
      window.title = "Failures"
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(rootView: root)
      window.center()
      self.window = window
    }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }
}

private struct FailureWindowRoot: View {
  let model: MenuModel
  let openLibrary: (String) -> Void
  @State private var selection: Failure.ID?

  init(model: MenuModel, initial: Failure.ID?, openLibrary: @escaping (String) -> Void) {
    self.model = model
    self.openLibrary = openLibrary
    self._selection = State(initialValue: initial)
  }

  var body: some View {
    FailureView(failures: model.failures, selection: $selection, openLibrary: openLibrary)
  }
}
