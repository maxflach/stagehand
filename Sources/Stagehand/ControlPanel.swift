import Carbon.HIToolbox
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
        .frame(minWidth: 900, minHeight: 700)
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
            PowerSwitch(model: model)
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
            .popover(isPresented: $showShortcuts, arrowEdge: .top) { ShortcutSheet(model: model) }
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
                    .overlay {
                        if !model.isOn { OffNotice(model: model) }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(model.current == nil ? Palette.cardStroke : Palette.coral.opacity(0.7), lineWidth: 2)
                    )

            }

            HStack(spacing: 8) {
                if !model.isOn {
                    Text("Off: nothing is captured and the Stagehand screen is gone.")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.6))
                } else if let current = model.current {
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

private struct PowerSwitch: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button { model.toggleOn() } label: {
            HStack(spacing: 8) {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(model.isOn ? Palette.deep : .white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(model.isOn ? AnyShapeStyle(Palette.mint) : AnyShapeStyle(Color.white.opacity(0.1))))
                Text(model.isOn ? "On" : "Off")
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .frame(minWidth: 26, alignment: .leading)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(model.isOn ? Palette.mint.opacity(0.16) : Palette.card))
            .overlay(Capsule().stroke(model.isOn ? Palette.mint.opacity(0.6) : Palette.cardStroke))
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.isOn)
        }
        .buttonStyle(.plain)
        .help(model.shortcutLabel(.power).map { "Turn Stagehand on or off (\($0))" } ?? "Turn Stagehand on or off")
        .contextMenu {
            Toggle("Turn off when the screen locks", isOn: $model.offWhenLocked)
        }
    }
}

private struct OffNotice: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.75))
            VStack(spacing: 12) {
                Image(systemName: "power").font(.system(size: 30, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                Text("Stagehand is off").font(.system(.title3, design: .rounded).weight(.bold))
                Text("Turn it on before you share. Picking a window turns it on too.")
                    .font(.callout).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                Button("Turn on") { model.setOn(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.mint)
                Toggle("Turn off when the screen locks", isOn: $model.offWhenLocked)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(20)
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
        let isCard = model.card != nil && model.breakEnd == nil
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                ToggleTile(title: "Follow", subtitle: "Share where you work", symbol: "figure.walk.motion",
                           tint: Palette.mint, isOn: model.follow) { model.follow.toggle() }
                ToggleTile(title: "Side by side", subtitle: "Your last two windows", symbol: "rectangle.split.2x1.fill",
                           tint: Palette.sky, isOn: model.split) { model.toggleSplit() }
                ToggleTile(title: "Zoom", subtitle: "\(model.zoomLevel.formatted(.number.precision(.fractionLength(0...1))))× around the pointer",
                           symbol: "plus.magnifyingglass", tint: Palette.violet, isOn: model.zoomOn,
                           action: { model.zoomOn.toggle() }) { ZoomOptions(model: model) }
                ToggleTile(title: "Webcam", subtitle: model.cameraStyle.fullScreen ? "Just me, full screen" : "Bubble in the corner",
                           symbol: "video.fill", tint: Palette.sky, isOn: model.cameraOn,
                           action: { model.setCamera(!model.cameraOn) }) { CameraOptions(model: model) }
            }
            GridRow {
                ToggleTile(title: "Spotlight", subtitle: "Dim all but the pointer", symbol: "light.overhead.right.fill",
                           tint: Palette.gold, isOn: model.spotlight) { model.spotlight.toggle() }
                ToggleTile(title: "Highlight", subtitle: "Ring around pointer", symbol: "cursorarrow.rays",
                           tint: Palette.gold, isOn: model.highlight) { model.highlight.toggle() }
                ToggleTile(title: "Cards", subtitle: isCard ? "Showing a card" : "Be right back, name tag",
                           symbol: "rectangle.inset.filled", tint: Palette.coral, isOn: isCard || model.lowerThirdOn,
                           action: { isCard ? model.hideCard() : model.showBeRightBack() }) { CardOptions(model: model) }
                ToggleTile(title: model.breakEnd == nil ? "Break" : "End break",
                           subtitle: model.breakEnd == nil ? "\(model.breakMinutes) min countdown" : "Countdown on stage",
                           symbol: "cup.and.saucer.fill", tint: Palette.coral, isOn: model.breakEnd != nil,
                           action: { model.breakEnd == nil ? model.startBreak() : model.stopBreak() }) { BreakOptions(model: model) }
            }
        }
    }
}

private struct ToggleTile<Options: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void
    let options: Options?
    @State private var hover = false
    @State private var showOptions = false

    init(title: String, subtitle: String, symbol: String, tint: Color, isOn: Bool,
         action: @escaping () -> Void, @ViewBuilder options: () -> Options) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.isOn = isOn
        self.action = action
        self.options = options()
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    Circle()
                        .fill(isOn ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.55)],
                                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                                   : AnyShapeStyle(Color.white.opacity(0.08)))
                        .frame(width: 36, height: 36)
                        .shadow(color: isOn ? tint.opacity(0.7) : .clear, radius: 10)
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isOn ? Palette.deep : .white.opacity(0.75))
                        .symbolEffect(.bounce, value: isOn)
                }
                Text(title).font(.system(.subheadline, design: .rounded).weight(.bold)).lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? tint.opacity(0.16) : Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isOn ? tint.opacity(0.6) : Palette.cardStroke, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if let options {
                    Button { showOptions.toggle() } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(hover || showOptions ? 0.16 : 0.07)))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Options")
                    .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                        options.padding(16).frame(width: 280)
                    }
                }
            }
            .scaleEffect(hover ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isOn)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

extension ToggleTile where Options == EmptyView {
    init(title: String, subtitle: String, symbol: String, tint: Color, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.isOn = isOn
        self.action = action
        self.options = nil
    }
}

// MARK: Tile options

private struct OptionsHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.system(.headline, design: .rounded))
    }
}

private struct ZoomOptions: View {
    @ObservedObject var model: AppModel

    private var zoomHelp: String {
        var parts: [String] = []
        if let toggle = model.shortcutLabel(.zoom) { parts.append("\(toggle) turns zoom on and off.") }
        let zoomIn = model.shortcutLabel(.zoomIn), zoomOut = model.shortcutLabel(.zoomOut)
        if let zoomIn, let zoomOut { parts.append("\(zoomIn) and \(zoomOut) change the level.") }
        parts.append("The view follows your pointer.")
        return parts.joined(separator: " ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionsHeader(title: "Zoom")
            HStack {
                Text("1.5×").font(.caption)
                Slider(value: $model.zoomLevel, in: 1.5...4, step: 0.5)
                Text("4×").font(.caption)
            }
            Text(zoomHelp)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CameraOptions: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionsHeader(title: "Webcam")
            Toggle("Just me (full screen)", isOn: Binding(get: { model.cameraStyle.fullScreen },
                                                          set: { on in if on, !model.cameraOn { model.setCamera(true) }
                                                                     model.cameraStyle.fullScreen = on }))
            Picker("Corner", selection: $model.cameraStyle.corner) {
                Text("Bottom right").tag(CameraStyle.Corner.bottomRight)
                Text("Bottom left").tag(CameraStyle.Corner.bottomLeft)
                Text("Top right").tag(CameraStyle.Corner.topRight)
                Text("Top left").tag(CameraStyle.Corner.topLeft)
            }
            Picker("Size", selection: $model.cameraStyle.size) {
                Text("S").tag(CameraStyle.Size.small)
                Text("M").tag(CameraStyle.Size.medium)
                Text("L").tag(CameraStyle.Size.large)
            }
            .pickerStyle(.segmented)
            Picker("Shape", selection: $model.cameraStyle.shape) {
                Image(systemName: "circle").tag(CameraStyle.Shape.circle)
                Image(systemName: "app").tag(CameraStyle.Shape.rounded)
            }
            .pickerStyle(.segmented)
            Divider()
            Button {
                model.showVideoEffects()
            } label: {
                Label("Background blur and effects…", systemImage: "camera.filters")
            }
            Text("Opens macOS's own camera effects: Portrait blur, Studio Light and backgrounds.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CardOptions: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionsHeader(title: "Title cards")
            HStack {
                Text("Be right back")
                Spacer()
                Button(model.card == .beRightBack ? "Hide" : "Show") {
                    model.card == .beRightBack ? model.hideCard() : model.showBeRightBack()
                }
            }
            HStack {
                Text("Starting soon at")
                DatePicker("", selection: $model.startTime, displayedComponents: .hourAndMinute).labelsHidden()
                Spacer()
                Button(isStartingSoon ? "Hide" : "Show") {
                    isStartingSoon ? model.hideCard() : model.showStartingSoon()
                }
            }
            Divider()
            Toggle("Name tag at the bottom", isOn: $model.lowerThirdOn)
            TextField("Name", text: $model.lowerName)
            TextField("Role, e.g. Product lead", text: $model.lowerRole)
        }
    }

    private var isStartingSoon: Bool {
        if case .startingSoon = model.card { return true }
        return false
    }
}

private struct BreakOptions: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionsHeader(title: "Break")
            Stepper("\(model.breakMinutes) minutes", value: $model.breakMinutes, in: 1...90)
            HStack {
                ForEach([5, 10, 15, 30], id: \.self) { minutes in
                    Button("\(minutes)") { model.breakMinutes = minutes }
                }
            }
        }
    }
}

// MARK: Sources

private struct SourcesColumn: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Favourites", detail: model.favoriteModifiers.map { "\($0) + number" })
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
                .help(model.shortcutLabel(.refresh).map { "Refresh (\($0))" } ?? "Refresh")
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
                Text(model.favoriteModifiers.map { "Star windows below to pin them to \($0)1–9. Drag to reorder." }
                     ?? "Star windows below to give them a shortcut. Drag to reorder.")
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
        let live = source.map { model.isOnStage($0) } ?? false
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
        let live = model.isOnStage(source)
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
        .contextMenu {
            Button("Show on stage") { model.select(source) }
            Button("Show on the right, side by side") { model.showOnRight(source) }
            Divider()
            Button(starred ? "Remove from favourites" : "Add to favourites") { model.toggleFavorite(source) }
        }
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
    @ObservedObject var model: AppModel
    @State private var recording: ShortcutAction?
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shortcuts").font(.system(.headline, design: .rounded))
                Spacer()
                Button("Reset to defaults") {
                    stopRecording()
                    model.resetShortcuts()
                    hint = nil
                }
            }
            Text(hint ?? "Click a shortcut, then press the new keys. Delete removes it, Esc cancels.")
                .font(.caption)
                .foregroundStyle(hint == nil ? Color.secondary : Palette.coral)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(ShortcutAction.groups, id: \.self) { group in
                        GridRow {
                            Text(group.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .gridCellColumns(2)
                        }
                        ForEach(ShortcutAction.allCases.filter { $0.group == group }) { action in
                            GridRow {
                                Text(action.title).font(.callout)
                                recorder(for: action).gridColumnAlignment(.trailing)
                            }
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(height: 460)
        }
        .padding(16)
        .frame(width: 400)
        .onDisappear { stopRecording() }
    }

    private func recorder(for action: ShortcutAction) -> some View {
        let isRecording = recording == action
        let taken = model.unavailableShortcuts.contains(action)
        let label = isRecording ? "Press keys…" : (model.shortcutLabel(action) ?? "None")
        return Button { isRecording ? stopRecording() : startRecording(action) } label: {
            Text(label)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(taken ? Palette.coral : (model.shortcut(action) == nil && !isRecording ? .secondary : .primary))
                .strikethrough(taken)
                .frame(minWidth: 96)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Palette.violet.opacity(0.45) : Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Palette.violet : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(taken ? "Another app already uses this shortcut, so it does nothing. Pick another one." : "Click to change")
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recording = action
        hint = nil
        model.pauseHotkeys(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let strong: NSEvent.ModifierFlags = [.command, .control, .option]
            let plain = event.modifierFlags.intersection(strong).isEmpty
            switch Int(event.keyCode) {
            case kVK_Escape where plain:
                stopRecording()
            case kVK_Delete where plain, kVK_ForwardDelete where plain:
                model.setShortcut(nil, for: action)
                stopRecording()
            default:
                let combo = KeyCombo(event: event)
                guard combo.isUsable else {
                    hint = "Add ⌘, ⌃ or ⌥ to the key (F-keys work on their own)."
                    return nil
                }
                hint = model.setShortcut(combo, for: action)
                stopRecording()
            }
            return nil // the key press only sets the shortcut
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil {
            recording = nil
            model.pauseHotkeys(false)
        }
    }
}
