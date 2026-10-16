import SwiftUI

@main
struct SkylineCrewApp: App {
    @StateObject private var app = AppBootstrap.make()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.light)
                .statusBar(hidden: false)
        }
        .onChange(of: scenePhase) { phase in
            app.handleLifecycle(active: phase == .active)
        }
    }
}

/// Composition root: Data implementations are wired into the domain ports here.
enum AppBootstrap {
    @MainActor
    static func make() -> AppModel {
        let content: GameContent
        do {
            content = try BundleJSONLevelRepository().loadContent()
        } catch {
            fatalError("Bundled campaign data is missing or invalid: \(error)")
        }
        ArtCache.shared.preload(["F01", "F02", "F03", "F04", "F05", "F06", "P01", "P02", "P03"])
        #if DEBUG
        if let id = UserDefaults.standard.string(forKey: "fixture"), !id.isEmpty {
            return FixtureFactory.make(id: id, content: content)
        }
        #endif
        let repository = AtomicFileProfileRepository(content: content)
        #if DEBUG
        // UI-test hooks: start from a clean device state or simulate a damaged primary save.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "resetProfile") {
            try? FileManager.default.removeItem(at: repository.directory)
            try? FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
        }
        if let seed = defaults.string(forKey: "seedProfile"), let levels = Int(seed), levels > 0 {
            var seeded = FixtureFactory.partialProfile(content, Date(), levels: min(levels, content.levels.count))
            seeded.walletBalance = 300
            try? repository.save(seeded)
        }
        if defaults.bool(forKey: "corruptProfile") {
            try? Data("{ damaged".utf8).write(to: repository.primaryURL)
        }
        #endif
        let audio = AudioEngine()
        let model = AppModel(content: content, repository: repository, clock: SystemClock(), random: SystemRandomSource(),
                             audio: audio, haptics: HapticEngine())
        audio.onInterruption = { [weak model] began in
            guard let model else { return }
            if began { model.game?.appWillResignActive() } else if model.scenePhaseActive && model.route != .play {
                model.audio.resumeMusicIfNeeded()
            }
        }
        return model
    }
}
