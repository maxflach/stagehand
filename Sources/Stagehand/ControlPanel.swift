import SwiftUI

// MARK: Palette (matches the app icon: indigo stage, warm spotlight)

enum Palette {
    static let deep = Color(red: 0.06, green: 0.05, blue: 0.14)
    static let indigo = Color(red: 0.20, green: 0.16, blue: 0.42)
    static let violet = Color(red: 0.45, green: 0.32, blue: 0.95)
    static let gold = Color(red: 1.00, green: 0.80, blue: 0.40)
    static let coral = Color(red: 1.00, green: 0.45, blue: 0.38)
    static let mint = Color(red: 0.35, green: 0.90, blue: 0.75)
    static let sky = Color(red: 0.35, green: 0.70, blue: 1.00)
    static let card = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.10)
}

struct ControlPanel: View {
    @ObservedObject var model: AppModel
    @State private var showShortcuts = false

    var body: some View {
        ZStack {
            Backdrop()
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    StageCard(model: model)
                    ToggleRow(model: model)
                    Spacer(minLength: 0)
                    footer
                }
                .frame(minWidth: 460)
                SourcesColumn(model: model)
                    .frame(width: 320)
            }
            .padding(.horizontal, 22)
            .padding(.top, 34) // room for the transparent title bar
            .padding(.bottom, 18)
        }
        .frame(minWidth: 860, minHeight: 600)
        .preferredColorScheme(.dark)
        .task { await model.refreshSources() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Stagehand")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.white, Palette.gold], startPoint: .leading, endPoint: .trailing))
            Spacer()
            if let status = model.status {
                Label(status, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Palette.coral)
                    .lineLimit(2)
                    .transition(.opacity)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundStyle(Palette.gold)
                (Text("In your meeting app, share the screen named ") + Text("Stagehand").bold())
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Palette.card))
            .overlay(Capsule().stroke(Palette.cardStroke))
            Spacer()
            Button { showShortcuts.toggle() } label: {
                Label("Shortcuts", systemImage: "command")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.card))
                    .overlay(Capsule().stroke(Palette.cardStroke))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showShortcuts, arrowEdge: .top) { ShortcutSheet() }
        }
    }
}

// MARK: Background

private struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.indigo, Palette.deep], startPoint: .top, endPoint: .bottom)
            // A warm spotlight from the top left, and a cool bounce light bottom right.
            RadialGradient(colors: [Palette.gold.opacity(0.28), .clear], center: UnitPoint(x: 0.22, y: -0.05),
                           startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Palette.violet.opacity(0.30), .clear], center: UnitPoint(x: 1.0, y: 1.05),
                           startRadius: 10, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

// MARK: Stage preview

private struct StageCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let glow = model.current == nil ? Palette.violet : Palette.coral
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                // Static glow behind the preview. A shadow on the preview itself would be recomputed every frame.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(glow.opacity(0.35))
                    .blur(radius: 22)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .drawingGroup()
                PreviewRepresentable(view: model.preview)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(model.current == nil ? Palette.cardStroke : Palette.coral.opacity(0.7), lineWidth: 2)
                    )

            }

            HStack(spacing: 8) {
                if let current = model.current {
                    OnAirBadge()
                    if let icon = current.icon {
                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    }
                    Text(current.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(model.hasScreenAccess ? "Nothing on stage yet. Pick a window on the right."
                                               : "Allow Screen Recording for Stagehand in System Settings, then reopen it.")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.current?.id)
        }
    }
}

private struct OnAirBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(Palette.coral)
                .symbolEffect(.pulse, options: .repeating)
            Text("ON AIR")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.coral.opacity(0.18)))
        .overlay(Capsule().stroke(Palette.coral.opacity(0.5)))
    }
}

// MARK: Toggle tiles

private struct ToggleRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            ToggleTile(title: "Follow", subtitle: "Share where you work", symbol: "figure.walk.motion",
                       tint: Palette.mint, isOn: model.follow) { model.follow.toggle() }
            ToggleTile(title: "Webcam", subtitle: "Bubble in the corner", symbol: "video.fill",
                       tint: Palette.sky, isOn: model.cameraOn) { model.setCamera(!model.cameraOn) }
            ToggleTile(title: "Spotlight", subtitle: "Dim all but the pointer", symbol: "light.overhead.right.fill",
                       tint: Palette.gold, isOn: model.spotlight) { model.spotlight.toggle() }
            ToggleTile(title: "Highlight", subtitle: "Ring around pointer", symbol: "cursorarrow.rays",
                       tint: Palette.violet, isOn: model.highlight) { model.highlight.toggle() }
            BreakTile(model: model)
        }
    }
}

private struct ToggleTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isOn ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.55)],
                                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                                   : AnyShapeStyle(Color.white.opacity(0.08)))
                        .frame(width: 40, height: 40)
                        .shadow(color: isOn ? tint.opacity(0.7) : .clear, radius: 12)
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isOn ? Palette.deep : .white.opacity(0.75))
                        .symbolEffect(.bounce, value: isOn)
                }
                Text(title).font(.system(.subheadline, design: .rounded).weight(.bold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? tint.opacity(0.16) : Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isOn ? tint.opacity(0.6) : Palette.cardStroke, lineWidth: 1)
            )
            .scaleEffect(hover ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isOn)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct BreakTile: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let isOn = model.breakEnd != nil
        ToggleTile(title: isOn ? "End break" : "Break",
                   subtitle: isOn ? "Countdown on stage" : "\(model.breakMinutes) min countdown",
                   symbol: "cup.and.saucer.fill", tint: Palette.coral, isOn: isOn) {
            isOn ? model.stopBreak() : model.startBreak()
        }
        .contextMenu {
            ForEach([2, 5, 10, 15, 30], id: \.self) { minutes in
                Button("\(minutes) minutes") { model.breakMinutes = minutes }
            }
        }
        .help("Right-click to change the length")
    }
}

// MARK: Sources

private struct SourcesColumn: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Favourites", detail: "⌃⌥⌘ + number")
            FavoritesList(model: model)

            HStack {
                SectionHeader(title: "All windows", detail: nil)
                Spacer()
                Button {
                    Task { await model.refreshSources() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .padding(7)
                        .background(Circle().fill(Palette.card))
                }
                .buttonStyle(.plain)
                .help("Refresh (⌃⌥⌘R)")
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(model.sources.enumerated()), id: \.element.id) { index, source in
                        SourceRow(model: model, source: source,
                                  number: model.favorites.isEmpty && index < 9 ? index + 1 : nil)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.cardStroke))
    }
}

private struct SectionHeader: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.6))
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}

private struct FavoritesList: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.favorites.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "star.fill").foregroundStyle(Palette.gold)
                Text("Star windows below to pin them to ⌃⌥⌘1–9. Drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.white.opacity(0.2)))
        } else {
            List {
                ForEach(Array(model.favorites.enumerated()), id: \.element.id) { index, favorite in
                    FavoriteRow(model: model, favorite: favorite, number: index + 1)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove { model.moveFavorites(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(model.favorites.count) * 46)
        }
    }
}

private struct FavoriteRow: View {
    @ObservedObject var model: AppModel
    let favorite: Favorite
    let number: Int
    @State private var hover = false

    var body: some View {
        let source = model.resolve(favorite)
        let live = source != nil && model.current == source
        Button {
            model.select(slot: number - 1)
        } label: {
            HStack(spacing: 10) {
                SlotBadge(number: number, live: live)
                if let icon = source?.icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(favorite.label).font(.callout.weight(.semibold)).lineLimit(1)
                    if source == nil {
                        Text("Not open").font(.caption2).foregroundStyle(.white.opacity(0.4))
                    } else if !favorite.detail.isEmpty {
                        Text(source?.rawTitle ?? favorite.detail)
                            .font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                if hover {
                    Button { model.removeFavorite(favorite) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Remove from favourites")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(live ? Palette.coral.opacity(0.2) : (hover ? Color.white.opacity(0.10) : Palette.card)))
            .opacity(source == nil ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct SourceRow: View {
    @ObservedObject var model: AppModel
    let source: Source
    let number: Int?
    @State private var hover = false

    var body: some View {
        let live = model.current == source
        let starred = model.favorite(for: source) != nil
        HStack(spacing: 10) {
            if let number {
                SlotBadge(number: number, live: live)
            }
            if let icon = source.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(source.appName).font(.callout.weight(.medium)).lineLimit(1)
                if case .window = source, !source.rawTitle.isEmpty {
                    Text(source.rawTitle).font(.caption2).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if live {
                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Palette.coral)
            }
            Button { model.toggleFavorite(source) } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .foregroundStyle(starred ? Palette.gold : .white.opacity(hover ? 0.6 : 0.25))
                    .symbolEffect(.bounce, value: starred)
            }
            .buttonStyle(.plain)
            .help(starred ? "Remove from favourites" : "Pin to a shortcut slot")
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(live ? Palette.coral.opacity(0.2) : (hover ? Color.white.opacity(0.10) : Color.clear)))
        .contentShape(Rectangle())
        .onTapGesture { model.select(source) }
        .onHover { hover = $0 }
    }
}

private struct SlotBadge: View {
    let number: Int
    let live: Bool

    var body: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(live ? Palette.deep : .white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(live ? AnyShapeStyle(Palette.coral)
                           : AnyShapeStyle(LinearGradient(colors: [Palette.violet, Palette.indigo],
                                                          startPoint: .top, endPoint: .bottom))))
    }
}

private struct ShortcutSheet: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(AppModel.shortcutHelp, id: \.0) { keys, text in
                GridRow {
                    Text(keys).font(.system(.callout, design: .monospaced).weight(.semibold))
                    Text(text).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }
}
