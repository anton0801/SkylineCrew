import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    /// The opaque dialog fully covers the screen → the screen below leaves the accessibility tree.
    @State private var dialogCovering = false

    var body: some View {
        MetricsReader {
            ZStack(alignment: .topLeading) {
                Palette.sky
                switch app.phase {
                case .recovery(let info):
                    RecoveryScreen(info: info)
                        .accessibilityHidden(app.dialog != nil)
                case .ready:
                    if !(app.dialog != nil && dialogCovering) {
                        screen(for: app.route)
                            .id(app.route)
                            .transition(transition)
                            .zIndex(1)
                            .accessibilityHidden(app.dialog != nil)
                    }
                }
                if let dialog = app.dialog {
                    DialogHost(kind: dialog)
                        .transition(.opacity)
                        .zIndex(10)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if app.dialog != nil { dialogCovering = true }
                            }
                        }
                        .onDisappear { dialogCovering = false }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: app.dialog)
        }
        .environment(\.uiSound, { cue in app.playSound(cue) })
        .onChange(of: app.route) { _ in app.updateMusic() }
        .onChange(of: app.dialog) { d in if d == nil { dialogCovering = false } }
        .onAppear { app.updateMusic() }
    }

    private var transition: AnyTransition {
        let forward = app.navForward
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func screen(for route: Route) -> some View {
        switch route {
        case .onboarding(let step): OnboardingScreen(step: step)
        case .home: HomeScreen()
        case .districts: DistrictsScreen()
        case .levelMap(let id): LevelMapScreen(districtID: id)
        case .brief(let id): BriefScreen(levelID: id)
        case .play:
            if let game = app.game {
                GameScreen(game: game).id(ObjectIdentifier(game))
            } else {
                Color.clear.onAppear { app.goHome() }
            }
        case .results: ResultsScreen()
        case .freeBuild: FreeBuildScreen()
        case .daily: DailyScreen()
        case .workshop: WorkshopScreen()
        case .collection: CollectionScreen()
        case .towerDetail(let ref): TowerDetailScreen(ref: ref)
        case .settings: SettingsScreen()
        case .help: HelpScreen()
        case .stats: StatsScreen()
        case .data: DataScreen()
        case .cityComplete: CityCompleteScreen()
        }
    }
}

// MARK: - 25b, 33, 34, 41, replace-session

struct DialogHost: View {
    let kind: DialogKind
    @EnvironmentObject private var app: AppModel

    private func close() {
        app.playSound(.sheetClose)
        app.dialog = nil
    }

    var body: some View {
        switch kind {
        case .themeLocked(let id):
            let theme = app.content.theme(id)
            DialogScreen(background: "BG02", character: "C03", towerFloors: themeFloors(id),
                         title: "A few more Bolts",
                         lines: ["\(theme?.name ?? "This theme") needs \(theme?.cost ?? 0) Bolts.", "You have \(app.profile.walletBalance)."],
                         actions: [
                            DialogAction(title: "Keep Building", style: .primary) { app.dialog = nil; app.goHome() },
                            DialogAction(title: "Back", style: .quiet, sound: nil) { close() }
                         ])
        case .themeUnlock(let id):
            let theme = app.content.theme(id)
            DialogScreen(background: "BG02", character: "C01", towerFloors: themeFloors(id),
                         title: "Unlock \(theme?.name ?? "theme")?",
                         lines: ["\(theme?.cost ?? 0) of your \(app.profile.walletBalance) Bolts.", "Colors only — same timing."],
                         actions: [
                            DialogAction(title: "Unlock · \(theme?.cost ?? 0) Bolts", style: .primary, sound: nil) { app.purchaseTheme(id) },
                            DialogAction(title: "Back", style: .quiet, sound: nil) { close() }
                         ])
        case .resetConfirm:
            DialogScreen(background: "BG01", character: "C03",
                         title: "Clear your city?",
                         lines: ["Towers, Bolts and unlocked", "colors will be removed."],
                         actions: [
                            DialogAction(title: "Hold to Clear", style: .danger, hold: true) {
                                if case .recovery = app.phase { app.startFresh() } else { app.resetProgress() }
                            },
                            DialogAction(title: "Cancel", style: .quiet, sound: nil) { close() }
                         ])
        case .saveProblem:
            let inGame = app.pendingSave?.context == .game
            let daily = app.pendingSave?.context == .daily
            DialogScreen(background: "BG01", character: "C03",
                         title: "Couldn’t save this build",
                         lines: daily ? ["Your delivery isn’t saved yet,", "so nothing was added. Try again."]
                                      : ["Your current tower is still", "here. Try saving again."],
                         actions: [
                            DialogAction(title: "Retry Save", style: .primary) { app.retrySave() },
                            DialogAction(title: inGame ? "Back to Tower" : "Back", style: .quiet, sound: .back) { app.dismissSaveProblem() }
                         ])
        case .freeBuildLocked:
            DialogScreen(background: "BG03", character: "C01",
                         title: "A little practice first",
                         lines: ["Finish Level \(GameContent.freeBuildUnlockLevel) to unlock Free", "Build."],
                         actions: [
                            DialogAction(title: "Keep Building", style: .primary) {
                                app.dialog = nil
                                app.push(.brief(app.campaign.nextLevelID ?? 1))
                            },
                            DialogAction(title: "Back", style: .quiet, sound: nil) { close() }
                         ])
        case .replaceSession(let newID):
            let active = app.profile.activeSession
            let activeName = active?.mode.levelID.map { "Level \($0)" } ?? "Free Build"
            DialogScreen(background: "BG01", character: "C03",
                         title: "Start a new tower?",
                         lines: ["Your unfinished \(activeName) tower", "will be replaced."],
                         actions: [
                            DialogAction(title: newID.map { "Start Level \($0)" } ?? "Start Free Build", style: .primary, sound: nil) { app.replaceSessionAndStart(levelID: newID) },
                            DialogAction(title: "Resume \(activeName)", style: .quiet) { app.resumeActiveSession() },
                            DialogAction(title: "Cancel", style: .quiet, sound: nil) { close() }
                         ])
        }
    }

    private func themeFloors(_ id: String) -> [String] {
        let seq = app.content.themeSequence(id)
        return (0..<4).map { seq[$0 % seq.count] }
    }
}

// MARK: - 36 Recovery

struct RecoveryScreen: View {
    let info: RecoveryInfo
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let lines: [String]
        if info.futureSchema {
            lines = ["This save is from a newer", "version. It was kept safely."]
        } else if info.backupAvailable {
            lines = ["The latest save could not be", "read."]
        } else {
            lines = ["The latest save could not be", "read and no backup was found."]
        }
        return DialogScreen(background: "BG01", character: "C03",
                            title: "Let’s restore your skyline",
                            lines: lines,
                            actions: [
                                DialogAction(title: "Restore Backup", style: .primary, enabled: info.backupAvailable) { app.restoreBackup() },
                                DialogAction(title: "Retry", style: .quiet) { app.retryLoad() },
                                DialogAction(title: "Start Fresh", style: .quiet, sound: .sheetOpen) { app.dialog = .resetConfirm }
                            ])
    }
}
