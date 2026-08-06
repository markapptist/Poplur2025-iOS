//
//  PoplurAlert.swift
//  Poplur2025
//
//  Poplur's own alert; the app ships no system alerts. The iOS alert's shape and
//  weight rebuilt in Poplur's clay, on the house palette (neonPink rgb(255,20,140) on
//  cardBg rgb(13,8,20)) at the approved 194pt card / 39pt button metrics. It does NOT
//  replace, fake or intercept iOS's own permission sheet — nobody can restyle that —
//  so every `requestAccess` / `requestAuthorization` call is left alone.
//
//  Call sites DESCRIBE their buttons rather than build them. The previous version applied
//  `.buttonStyle(...)` to the caller's `Button`s via `Group(subviews:)`, which SwiftUI
//  silently ignores: a Button resolves its style when the view list is created, from the
//  environment at the *Group*, so that style's `makeBody` never ran. The component's
//  dismissal lived inside it, so an alert whose caller passed an empty `{ }` closure could
//  not be closed at all — and the scrim swallows every touch, so the user was trapped. The
//  component now builds the real `Button`: styling and dismissal are guaranteed.
//
//  It presents in a window-level `fullScreenCover`, not an `.overlay`: CubeTabView's
//  alert hangs off a VStack inside a ScrollView (an overlay would scroll away and clip)
//  and StreetViewButton's off a capsule over MapKit (it could land under the map).
//

import SwiftUI

// MARK: - Public surface

/// One button in a `poplurAlert`; `action` may be empty, as every tap closes the alert.
struct PoplurAlertButton: Identifiable {
    enum Role { case `default`, cancel, destructive }

    /// Stable across re-evaluations of the caller's body. A fresh `UUID()` here
    /// looks harmless but is not: the caller rebuilds this array every render, so
    /// every button got a new identity, `ForEach` tore down and recreated the
    /// Buttons underneath the user's finger, and an in-flight press was silently
    /// cancelled. MediaPickerView publishes state while its permission alert is
    /// up, so "Open Settings" could just quietly not register.
    var id: String { title }
    let title: String
    let role: Role
    let action: () -> Void

    init(_ title: String, role: Role = .default, action: @escaping () -> Void = {}) {
        self.title = title
        self.role = role
        self.action = action
    }

    /// The declining / dismissing choice. Put it first, the way iOS does.
    static func cancel(_ t: String = "OK", action: @escaping () -> Void = {}) -> Self {
        Self(t, role: .cancel, action: action)
    }
    static func `default`(_ t: String, action: @escaping () -> Void = {}) -> Self {
        Self(t, role: .default, action: action)
    }
    /// Gets the red ramp, so "delete" never reads as just another choice.
    static func destructive(_ t: String, action: @escaping () -> Void = {}) -> Self {
        Self(t, role: .destructive, action: action)
    }
}

/// The clay chip above the title; an empty name is how the card skips the icon gutter.
enum PoplurAlertIcon: Equatable {
    case none, photos, camera, location
    case symbol(String)

    var symbolName: String {
        switch self {
        case .none:             return ""
        case .photos:           return "photo.fill"
        case .camera:           return "camera.fill"
        case .location:         return "location.fill"
        case .symbol(let name): return name
        }
    }
}

/// `.neon` exists because the clay card reads as a hole punched in a very dark surface,
/// and Game Maker, the map and FPS are all near-black.
enum PoplurAlertStyle: Equatable { case clay, neon }

/// `.standard` is the approved web value at 1:1; `.wide` is iOS's own, for long copy.
enum PoplurAlertWidth: Equatable {
    case standard, wide
    var points: CGFloat { self == .standard ? 194 : 270 }
}

extension View {
    /// Poplur's alert. Every button dismisses it; `action` runs on the same tap.
    func poplurAlert(
        _ title: LocalizedStringKey, isPresented: Binding<Bool>, message: String? = nil,
        icon: PoplurAlertIcon = .none, style: PoplurAlertStyle = .clay,
        width: PoplurAlertWidth = .standard, accessibilityLabel: String? = nil,
        buttons: [PoplurAlertButton] = [.cancel()]
    ) -> some View {
        modifier(PoplurAlertPresenter(
            isPresented: isPresented, icon: icon, style: style, width: width,
            accessibilityLabel: accessibilityLabel,
            resolve: { PoplurAlertContent(title: title, message: message, buttons: buttons) }
        ))
    }

    /// Optional-item overload: the item is non-optional inside the builders, so no shim.
    func poplurAlert<Item>(
        _ title: LocalizedStringKey, presenting item: Binding<Item?>,
        icon: PoplurAlertIcon = .none, style: PoplurAlertStyle = .clay,
        width: PoplurAlertWidth = .standard, accessibilityLabel: String? = nil,
        message: @escaping (Item) -> String,
        buttons: @escaping (Item) -> [PoplurAlertButton]
    ) -> some View {
        modifier(PoplurAlertPresenter(
            // The presenter only ever *clears* this — it cannot fabricate an Item.
            isPresented: Binding(get: { item.wrappedValue != nil },
                                 set: { if !$0 { item.wrappedValue = nil } }),
            icon: icon, style: style, width: width, accessibilityLabel: accessibilityLabel,
            resolve: {
                guard let v = item.wrappedValue else { return nil }
                return PoplurAlertContent(title: title, message: message(v), buttons: buttons(v))
            }
        ))
    }
}

// MARK: - Tokens

/// NOT `DS.Color.accent` (#FF2D96): house neon pink is #FF148C and the clay ramp is
/// #FF62AD -> #D90F6D. Three pinks, and only the last one is the approved design.
enum PoplurAlertTokens {
    static let cornerRadius: CGFloat = 8, buttonHeight: CGFloat = 39
    static let contentInsets = EdgeInsets(top: 20, leading: 17, bottom: 16, trailing: 17)
    static let iconBottomMargin: CGFloat = 13, titleBottomMargin: CGFloat = 7
    static let shadowRadius: CGFloat = 21, shadowOffsetY: CGFloat = 18
    static let scrimFill = colour(0x0A070D).opacity(0.45)      // rgba(10,7,13,0.45)
    static let neonPink = colour(0xFF148C)                     // house neonPink
    static let clayCardFill = colour(0xFFF7FB).opacity(0.94)   // cream clay slab
    static let neonCardFill = colour(0x0D0814).opacity(0.94)   // house cardBg
    static let clayCardBorder = Color.white.opacity(0.44), neonCardBorder = neonPink.opacity(0.55)
    static let clayCardShadow = colour(0x39001E).opacity(0.38), neonCardShadow = Color.black.opacity(0.75)
    static let clayHairline = colour(0x5F364D).opacity(0.18), neonHairline = neonPink.opacity(0.22)
    /// First choice is a plain slab, later ones take the gradient and so read heavier.
    static let clayFirstButtonFill = Color.white.opacity(0.58), neonFirstButtonFill = Color.white.opacity(0.05)
    static let clayButtonPressed = colour(0xFFE1EF), neonButtonPressed = neonPink.opacity(0.30)
    static let clayButtonFill = vGradient(.white, colour(0xFFF0F7))
    static let neonButtonFill = vGradient(Color.white.opacity(0.10), neonPink.opacity(0.14))
    /// Glyph chip — linear-gradient(145deg, #ff62ad, #d90f6d).
    static let clayGlyphFill = LinearGradient(colors: [colour(0xFF62AD), colour(0xD90F6D)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    static let clayGlyphShadow = colour(0xC2117A).opacity(0.26)

    // Label ramps — the signature is gradient-filled text, not flat ink. The neon set
    // raises the dark anchors for near-black; destructive pulls it onto the red end.
    static let clayTitleRamp = ramp(0x8B214F, 0xFF6CAD, 0x25131F), neonTitleRamp = ramp(0xFFFFFF, 0xFF8EC6, 0xFFFFFF)
    static let clayLabelRamp = ramp(0xE20C75, 0xFF70B4, 0x7D345B), neonLabelRamp = ramp(0xFF148C, 0xFFA8D2, 0x61D4F2)
    static let clayMessageInk = colour(0x69515F), neonMessageInk = colour(0xE6CFDD)
    static let destructiveRamp = ramp(0xE20C2D, 0xFF5A66, 0x8B0F2F)
    static let titleFont = Font.system(size: 15, weight: .black, design: .rounded)
    static let messageFont = Font.system(size: 10, weight: .bold, design: .rounded)
    static let buttonFont = Font.system(size: 11, weight: .black, design: .rounded)
    static let titleLineSpacing: CGFloat = 2.7, messageLineSpacing: CGFloat = 4.2
    /// `permIn`: 0.5s cubic-bezier(0.2,1.35,0.4,1) — the 1.35 overshoot is its character.
    static let entrance = Animation.timingCurve(0.2, 1.35, 0.4, 1, duration: 0.5)
    static let exit = Animation.easeOut(duration: 0.18)
    static let exitDuration: TimeInterval = 0.18
    static func colour(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
    private static func ramp(_ hexes: UInt32...) -> LinearGradient {
        LinearGradient(colors: hexes.map(colour), startPoint: .leading, endPoint: .trailing)
    }
    private static func vGradient(_ top: Color, _ bottom: Color) -> LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

private typealias Tok = PoplurAlertTokens

// MARK: - Card

private struct PoplurAlertContent {
    let title: LocalizedStringKey
    let message: String?
    let buttons: [PoplurAlertButton]
}

private struct PoplurAlertButtonStyle: ButtonStyle {
    let index: Int
    let role: PoplurAlertButton.Role
    let style: PoplurAlertStyle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tok.buttonFont).lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(labelRamp).padding(.horizontal, 6)
            .frame(maxWidth: .infinity).frame(height: Tok.buttonHeight)
            .background(fill(pressed: configuration.isPressed))
            .contentShape(Rectangle())
    }

    private var labelRamp: LinearGradient {
        if role == .destructive { return Tok.destructiveRamp }
        return style == .clay ? Tok.clayLabelRamp : Tok.neonLabelRamp
    }
    private func fill(pressed: Bool) -> AnyShapeStyle {
        let clay = style == .clay
        if pressed { return AnyShapeStyle(clay ? Tok.clayButtonPressed : Tok.neonButtonPressed) }
        if index == 0 { return AnyShapeStyle(clay ? Tok.clayFirstButtonFill : Tok.neonFirstButtonFill) }
        return AnyShapeStyle(clay ? Tok.clayButtonFill : Tok.neonButtonFill)
    }
}

private struct PoplurAlertCard: View {
    let content: PoplurAlertContent
    let icon: PoplurAlertIcon
    let style: PoplurAlertStyle
    let width: PoplurAlertWidth
    let accessibilityLabel: String?
    let activate: (PoplurAlertButton) -> Void

    /// An alert with no way out is a trap, so an empty list still gets an OK.
    private var buttons: [PoplurAlertButton] { content.buttons.isEmpty ? [.cancel()] : content.buttons }
    private var isClay: Bool { style == .clay }
    private var shape: RoundedRectangle { .init(cornerRadius: Tok.cornerRadius, style: .continuous) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if !icon.symbolName.isEmpty { glyph.padding(.bottom, Tok.iconBottomMargin) }
                Text(content.title).font(Tok.titleFont).lineSpacing(Tok.titleLineSpacing)
                    .foregroundStyle(isClay ? Tok.clayTitleRamp : Tok.neonTitleRamp)
                // Backend/AVFoundation copy is any length and has hard newlines: never clips.
                if let message = content.message, !message.isEmpty {
                    Text(message).font(Tok.messageFont).lineSpacing(Tok.messageLineSpacing)
                        .foregroundStyle(isClay ? Tok.clayMessageInk : Tok.neonMessageInk)
                        .padding(.top, Tok.titleBottomMargin)
                }
            }
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(Tok.contentInsets).frame(maxWidth: .infinity)

            divider(vertical: false)
            buttonRow
        }
        .frame(width: width.points)
        // Tint in front, material behind (a later `.background` sits further back): CSS
        // `background` + `backdrop-filter` in order, then the lit top edge, then clip.
        .background(isClay ? Tok.clayCardFill : Tok.neonCardFill, in: shape)
        .background(.regularMaterial, in: shape)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(isClay ? 0.90 : 0.16)).frame(height: 1)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(isClay ? Tok.clayCardBorder : Tok.neonCardBorder, lineWidth: 1) }
        .shadow(color: isClay ? Tok.clayCardShadow : Tok.neonCardShadow, radius: Tok.shadowRadius, y: Tok.shadowOffsetY)
        // Pin the scheme so the material cannot go dark under the cream clay tint.
        .environment(\.colorScheme, isClay ? .light : .dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel.map { Text($0) } ?? Text(content.title))
        .accessibilityAddTraits(.isModal)
    }

    /// Two choices sit side by side, declining one left; otherwise they stack full width.
    private var buttonRow: some View {
        let twoUp = buttons.count == 2
        let layout = twoUp ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        return layout {
            // Keyed by POSITION, so two buttons sharing a title still get distinct
            // identities and neither is rebuilt when the caller re-renders.
            ForEach(Array(buttons.enumerated()), id: \.offset) { index, item in
                if index > 0 { divider(vertical: twoUp) }
                button(item, index: index)
            }
        }
    }

    /// A real `Button`, built here not handed in: the style attaches the ordinary way,
    /// `activate` is always on the tap path, and VoiceOver gets a labelled element free.
    private func button(_ item: PoplurAlertButton, index: Int) -> some View {
        Button { activate(item) } label: { Text(item.title) }
            .buttonStyle(PoplurAlertButtonStyle(index: index, role: item.role, style: style))
            .accessibilityLabel(Text(item.title))
    }

    private func divider(vertical: Bool) -> some View {
        Rectangle().fill(isClay ? Tok.clayHairline : Tok.neonHairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? Tok.buttonHeight : 1)
    }

    /// The `inset 0 2px 2px rgba(255,255,255,0.45)` lip makes the chip read as clay, not a
    /// flat swatch. It restates the title, so VoiceOver skips it.
    private var glyph: some View {
        let chip = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return chip.fill(Tok.clayGlyphFill).frame(width: 44, height: 34)
            .overlay {
                chip.stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 2).blur(radius: 0.8)
            }
            .overlay {
                Image(systemName: icon.symbolName)
                    .font(.system(size: 17, weight: .black)).foregroundStyle(.white)
            }
            .shadow(color: Tok.clayGlyphShadow, radius: 6.5, y: 6)
            .accessibilityHidden(true)
    }
}

// MARK: - Presenter

private struct PoplurAlertPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let icon: PoplurAlertIcon
    let style: PoplurAlertStyle
    let width: PoplurAlertWidth
    let accessibilityLabel: String?
    let resolve: () -> PoplurAlertContent?

    /// Drives the cover. Deliberately *not* the caller's binding: it must be raised and
    /// lowered with animation disabled, or iOS slides a scrim up before the card appears.
    @State private var isCoverUp = false
    @State private var cardIsIn = false     // the card's own transform inside the cover
    @State private var isClosing = false    // guards the two dismissal paths from racing
    /// Held so the `presenting:` overload never renders an empty card during the exit.
    @State private var held: PoplurAlertContent?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // `onChange` never fires for a binding already true on first render.
            .onAppear { if isPresented { present() } }
            .onChange(of: isPresented) { _, now in if now { present() } else { beginClose() } }
            .fullScreenCover(
                isPresented: $isCoverUp,
                // Backstop only: nothing else lowers this cover, but nothing may stick.
                onDismiss: { isClosing = false; if isPresented { isPresented = false } }
            ) {
                // `.clear` keeps the app visible behind the scrim, not a black slab.
                alertOverlay.presentationBackground(.clear)
            }
    }

    /// The point of the descriptor API: the close is unconditional and happens on this tap,
    /// before the caller's closure gets a say, so an empty action still dismisses. The
    /// caller's work then runs while the card is still on screen — GameMaker's "Got it"
    /// tears down its whole sheet, which must not race a cover already gone.
    private func activate(_ button: PoplurAlertButton) {
        beginClose()
        button.action()
    }
    private var alertOverlay: some View {
        ZStack {
            // No tap-to-dismiss, as iOS has none: the empty gesture *swallows* touches.
            Tok.scrimFill.background(.ultraThinMaterial).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture { }
                .opacity(cardIsIn ? 1 : 0).zIndex(0)

            if let shown = resolve() ?? held {
                PoplurAlertCard(content: shown, icon: icon, style: style, width: width,
                                accessibilityLabel: accessibilityLabel, activate: activate)
                    .scaleEffect(cardIsIn ? 1 : 0.86)   // `permIn`: opacity 0, 0.86, y +10
                    .offset(y: cardIsIn ? 0 : 10)
                    .opacity(cardIsIn ? 1 : 0)
                    // Dead to touch the instant a choice is made. `activate` runs
                    // beginClose() and then the caller's action, but the card stays on
                    // screen for the 0.18s exit — leaving it live let a second tap in
                    // that window fire a DIFFERENT button too (tap OK, catch Open
                    // Settings on the way out). beginClose() itself is idempotent; this
                    // closes the gap for the other buttons.
                    .allowsHitTesting(!isClosing)
                    .zIndex(1)
            }
        }
        .onAppear {
            guard !reduceMotion else { cardIsIn = true; return }
            // One runloop hop: flipped inside the raising transaction it would be swallowed.
            DispatchQueue.main.async { withAnimation(Tok.entrance) { cardIsIn = true } }
        }
    }
    private func present() {
        // Re-presenting mid-exit catches the card: clearing `isClosing` voids `finishClose`.
        if isClosing {
            isClosing = false
            withAnimation(Tok.entrance) { cardIsIn = true }
            return
        }
        guard !isCoverUp else { return }
        held = resolve()
        cardIsIn = false
        withoutAnimation { isCoverUp = true }
    }
    private func beginClose() {
        guard isCoverUp, !isClosing else { return }
        if let live = resolve() { held = live }   // snapshot before the item clears
        isClosing = true
        if isPresented { isPresented = false }    // re-enters onChange; guard eats it
        guard !reduceMotion else { return finishClose() }
        withAnimation(Tok.exit) { cardIsIn = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + Tok.exitDuration + 0.02) { finishClose() }
    }
    private func finishClose() {
        guard isClosing else { return }   // stale if `present()` cleared it mid-exit
        isClosing = false
        withoutAnimation { isCoverUp = false }
        if isPresented { isPresented = false }
        held = nil
    }
    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}
