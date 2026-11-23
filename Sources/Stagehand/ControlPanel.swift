import SwiftUI

struct ControlPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sourceList
                .frame(minWidth: 340)
            Divider()
            sidebar
                .frame(width: 290)
        }
        .frame(minWidth: 680, minHeight: 460)
        .task { await model.refreshSources() }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("On stage").font(.headline)
                Spacer()
                Button {
                    Task { await model.refreshSources() }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            .padding(12)

            if let status = model.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            List(Array(model.sources.enumerated()), id: \.element.id) { index, source in
                Button { model.select(source) } label: {
                    HStack(spacing: 10) {
                        Text(index < 9 ? "\(index + 1)" : " ")
                            .font(.system(.caption, design: .monospaced).bold())
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        if let icon = source.icon {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        }
                        Text(source.title).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if model.current == source {
                            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.red)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(model.current == source ? Color.accentColor.opacity(0.18) : Color.clear)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("How to share") {
                Text("In Teams, Zoom, Meet or Slack, share the screen named **\(VirtualDisplay.name)**. Then switch what it shows here or with the shortcuts, without stopping the share.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Overlays") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Webcam", isOn: Binding(get: { model.cameraOn }, set: { model.setCamera($0) }))
                    Toggle("Spotlight around cursor", isOn: $model.spotlight)
                    Toggle("Highlight cursor", isOn: $model.highlight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Break") {
                HStack {
                    Stepper("\(model.breakMinutes) min", value: $model.breakMinutes, in: 1...60)
                    Spacer()
                    if model.breakEnd == nil {
                        Button("Start") { model.startBreak() }
                    } else {
                        Button("End break") { model.stopBreak() }
                    }
                }
            }

            GroupBox("Shortcuts") {
                Grid(alignment: .leading, verticalSpacing: 3) {
                    ForEach(AppModel.shortcutHelp, id: \.0) { keys, text in
                        GridRow {
                            Text(keys).font(.system(.caption, design: .monospaced))
                            Text(text).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(12)
    }
}
