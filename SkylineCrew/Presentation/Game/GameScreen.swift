import SwiftUI
import SpriteKit

/// 08–14, 39, 40: SpriteKit scene between the top HUD and the bottom sheet.
struct GameScreen: View {
    @ObservedObject var game: GameController
    @EnvironmentObject private var app: AppModel
    @Environment(\.mockMetrics) private var m

    var body: some View {
        ZStack(alignment: .topLeading) {
            MockCanvas {
                BackgroundArt(id: game.background)
                SpriteView(scene: game.scene, preferredFramesPerSecond: 120, options: [.allowsTransparency])
                    .frame(width: m.size.width, height: m.size.height)
                    .accessibilityHidden(true)
                topHUD
                if let hint = game.hud.tutorialHint { tutorialBubble(hint) }
                bottomSheet
                if case .countdown(let n) = game.overlay { countdown(n) }
            }
            .accessibilityAction(named: "Drop Floor") { game.dropTapped() }
            .accessibilityHidden(game.overlay == .paused || game.overlay == .restartConfirm)

            switch game.overlay {
            case .paused?:
                pauseDialog.transition(.opacity)
            case .restartConfirm?:
                restartDialog.transition(.opacity)
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: game.overlay)
        .onAppear { game.scene.metrics = m }
        .onChange(of: m) { game.scene.metrics = $0 }
    }

    // MARK: Top HUD (pinned to the top safe area)

    private var topHUD: some View {
        ZStack(alignment: .topLeading) {
            LogoView(scale: 0.74).mock(22, 52, 220 * 0.74, 64 * 0.74, h: .leading)
            Button {
                game.pauseTapped()
            } label: { EmptyView() }
            .buttonStyle(PauseSkinStyle())
            .accessibilityLabel("Pause")
            .mock(318, 61, 50, 48, h: .trailing)

            UIAsset("hud_chip").mock(20, 122, 350, 42, h: .stretch)
            Text(game.hud.title).mockStyle(16).mockText(32, 149, .start)
            Text(game.hud.progress).mockStyle(16)
                .accessibilityLabel(progressAccessibility)
                .mockText(356, 149, .end)
            Text(game.hud.objective).mockStyle(16).mockText(22, 187, .start)

            if let arrow = game.hud.windArrow {
                UIAsset("icon_wind").mock(22, 216, 33, 33, h: .leading)
                Text("Wind \(arrow)").mockStyle(16)
                    .accessibilityLabel(arrow == "→" ? "Wind pushing right" : "Wind pushing left")
                    .mockText(61, 239, .start)
            }
        }
    }

    private var progressAccessibility: String {
        switch game.mode {
        case .campaign: return game.hud.progress.replacingOccurrences(of: " / ", with: " of ").lowercased()
        default: return game.hud.progress.lowercased()
        }
    }

    private func tutorialBubble(_ lines: [String]) -> some View {
        ZStack(alignment: .topLeading) {
            CreamCard(radius: 24).mock(20, 221, 225, 106, h: .leading)
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text(line).mockStyle(17, Palette.secondary).accessibilityHidden(true).mockText(38, 251 + 23 * CGFloat(i), .start)
            }
            UIAsset("icon_arrow").mock(32, 278, 30, 30, h: .leading)
            AXLabel(label: lines.joined(separator: " ")).mock(20, 221, 225, 106, h: .leading)
        }
    }

    // MARK: Bottom sheet (pinned to the bottom safe area)

    private var bottomSheet: some View {
        let sheetHeight = max(190, 170 + m.safeBottom)
        let hud = game.hud
        return ZStack(alignment: .topLeading) {
            CreamCard(radius: 24).mock(0, 664, 390, sheetHeight, v: .bottom, h: .stretch)
            Text("Strain \(hud.strain)/\(hud.maxStrain)").mockStyle(14)
                .accessibilityLabel("Strain \(hud.strain) of \(hud.maxStrain)")
                .accessibilityValue(hud.strain >= RunRules.strainCritical ? "critical" : hud.strain >= RunRules.strainWarning ? "high" : "steady")
                .mockText(22, 691, .start, v: .bottom)
            StrainBar(value: hud.strain, maxValue: hud.maxStrain).mock(165, 680, 203, 10, v: .bottom, h: .stretch)
            Text(hud.streakLine).mockStyle(16).mockText(22, 718, .start, v: .bottom)
            if hud.braceCharged && !hud.braceArmed {
                IconButton(icon: "icon_brace", label: "Use Brace", sound: nil) { game.braceTapped() }
                    .accessibilityHint("The next floor lands safely in place")
                    .mock(321, 696, 38, 38, v: .bottom, h: .trailing)
            }
            Button {
                game.dropTapped()
            } label: { EmptyView() }
            .buttonStyle(SkinButtonStyle(title: hud.dropTitle, style: .primary, enabled: !hud.dropLooksDisabled))
            .allowsHitTesting(game.overlay == nil)
            .accessibilityLabel(hud.dropTitle)
            .accessibilityIdentifier("dropFloor")
            .accessibilityValue(hud.aligned ? "aligned" : "")
            .accessibilityHint("Releases the hanging floor")
            .mock(20, 738, 350, 60, v: .bottom, h: .stretch)
        }
    }

    // MARK: 40 Resume countdown

    private func countdown(_ n: Int) -> some View {
        let top = 200 + m.topShift
        let bottom = 663 + m.bottomShift
        return ZStack(alignment: .topLeading) {
            Palette.deepBlue.placed(0, top, m.size.width, bottom - top)
            Text("\(n)").font(Typo.font(100)).foregroundColor(.white)
                .accessibilityLabel("Resuming in \(n)")
                .accessibilityIdentifier("countdown")
                .placedText(m.size.width / 2, top + (bottom - top) / 2 + 26.5, .middle)
        }
    }

    // MARK: 15 / 16

    private var pauseDialog: some View {
        let floors = Array(game.session.placements.prefix(4).map(\.assetID))
        var actions = [DialogAction(title: "Resume", style: .primary) { game.resumeTapped() }]
        if game.mode == .tutorial {
            actions.append(DialogAction(title: "Skip Tutorial", style: .quiet) { game.skipTutorial() })
        } else {
            actions.append(DialogAction(title: "Restart", style: .quiet, sound: nil) { game.restartTapped() })
        }
        actions.append(DialogAction(title: "Home", style: .quiet, sound: .back) { game.homeTapped() })
        return DialogScreen(background: game.background, character: "C01",
                            towerFloors: floors.count == 4 ? floors : ["F06", "F05", "F04", "F03"],
                            title: "Take a breather", lines: ["Your tower is safe right here."], actions: actions)
    }

    private var restartDialog: some View {
        let floors = Array(game.session.placements.prefix(4).map(\.assetID))
        return DialogScreen(background: game.background, character: "C03",
                            towerFloors: floors.count == 4 ? floors : ["F06", "F05", "F04", "F03"],
                            title: "Start this tower again?",
                            lines: ["This attempt will be replaced.", "Your best result stays."],
                            actions: [
                                DialogAction(title: "Restart", style: .primary, sound: nil) { game.confirmRestart() },
                                DialogAction(title: "Keep Building", style: .quiet, sound: nil) { game.keepBuilding() }
                            ])
    }
}

/// The 50×48 pause control: secondary button skin squeezed exactly like the SVG, icon on top.
private struct PauseSkinStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return ZStack(alignment: .topLeading) {
            UIAsset(pressed ? "button_secondary_pressed" : "button_secondary_normal")
            UIAsset("icon_pause").frame(width: 42, height: 42).offset(x: 4, y: 1 + (pressed ? 3 : 0))
        }
        .frame(width: 50, height: 48, alignment: .topLeading)
        .contentShape(Rectangle())
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}
