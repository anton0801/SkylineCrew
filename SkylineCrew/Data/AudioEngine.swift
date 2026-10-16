import AVFoundation
import UIKit

/// Local WAV playback (36 files bundled). Buses and rules from integration/audio_events.json:
/// master .8, music .45, effects .8, ambience .25; max 6 SFX voices; 600 ms music crossfade;
/// −7 dB music duck during fanfares; Music off fades in 200 ms; Effects off stops SFX at once.
final class AudioEngine: NSObject, AudioService, AVAudioPlayerDelegate {
    private let masterBus: Float = 0.8
    private let musicBus: Float = 0.45
    private let effectsBus: Float = 0.8
    private let ambienceBus: Float = 0.25
    private let maxVoices = 6
    private let crossfade: TimeInterval = 0.6
    private let duckFactor: Float = pow(10, -7.0 / 20.0)

    private var settings = GameSettings()
    private var urls: [String: URL] = [:]
    private var idle: [SoundCue: [AVAudioPlayer]] = [:]
    private var voices: [(player: AVAudioPlayer, cue: SoundCue, started: TimeInterval)] = []
    private var music: AVAudioPlayer?
    private var musicTrack: MusicTrack?
    private var wantedTrack: MusicTrack?
    private var fading: [AVAudioPlayer] = []
    private var ambience: [AmbienceLoop: AVAudioPlayer] = [:]
    private var wantedAmbience: Set<AmbienceLoop> = []
    private var loopsSuspended = false
    private var duckDepth = 0
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        super.init()
        configureSession()
        indexFiles()
        NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChange(_:)),
                                               name: AVAudioSession.routeChangeNotification, object: nil)
        // Warm the most frequent gameplay cues so the first drop has no load hitch.
        for cue in [SoundCue.tap, .release, .fallAir, .landStone, .landWood, .landMetal, .perfectOne] {
            if let p = makePlayer(cue.rawValue) { idle[cue, default: []].append(p) }
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // Ambient respects the silent switch and mixes with other audio; no background audio.
        try? session.setCategory(.ambient, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func indexFiles() {
        let names = SoundCue.allCases.map(\.rawValue)
            + [MusicTrack.sunnyRooftops, .steadyHands, .harborBreeze, .depotDelivery].map(\.rawValue)
            + [AmbienceLoop.cityAir, .craneMotor].map(\.rawValue)
        for name in names {
            if let url = bundle.url(forResource: name, withExtension: "wav")
                ?? bundle.url(forResource: name, withExtension: "wav", subdirectory: "Resources/Audio") {
                urls[name] = url
            }
        }
    }

    private func makePlayer(_ name: String) -> AVAudioPlayer? {
        guard let url = urls[name], let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay()
        return p
    }

    // MARK: Settings

    func apply(settings new: GameSettings) {
        let old = settings
        settings = new
        if old.effects && !new.effects {
            stopEffects()
            for (_, p) in ambience { p.pause() }
        } else if !old.effects && new.effects, !loopsSuspended {
            for loop in [AmbienceLoop.cityAir, .craneMotor] { applyAmbience(loop) }
        }
        if old.music && !new.music {
            if let m = music { fadeOut(m, duration: 0.2) }
            music = nil
            musicTrack = nil
        } else if !old.music && new.music, !loopsSuspended {
            startWantedMusic()
        }
    }

    // MARK: Effects

    func play(_ cue: SoundCue) {
        guard settings.effects else { return }
        voices.removeAll { !$0.player.isPlaying }
        if voices.count >= maxVoices {
            // Drop the oldest lowest-priority voice if the new one is at least as important.
            if let victim = voices.enumerated().min(by: { a, b in
                a.element.cue.priority != b.element.cue.priority ? a.element.cue.priority < b.element.cue.priority : a.element.started < b.element.started
            }), victim.element.cue.priority <= cue.priority {
                victim.element.player.stop()
                voices.remove(at: victim.offset)
            } else {
                return
            }
        }
        let player: AVAudioPlayer
        if var pool = idle[cue], let free = pool.firstIndex(where: { !$0.isPlaying }) {
            player = pool.remove(at: free)
            idle[cue] = pool
        } else if let fresh = makePlayer(cue.rawValue) {
            player = fresh
        } else {
            return
        }
        player.delegate = self
        player.currentTime = 0
        player.volume = masterBus * effectsBus
        player.play()
        voices.append((player, cue, ProcessInfo.processInfo.systemUptime))
        if cue.isFanfare { duck(for: player.duration) }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if let i = voices.firstIndex(where: { $0.player === player }) {
            let cue = voices[i].cue
            voices.remove(at: i)
            if (idle[cue]?.count ?? 0) < 3 { idle[cue, default: []].append(player) }
        }
    }

    func stopEffects() {
        for v in voices { v.player.stop() }
        voices.removeAll()
    }

    private func duck(for duration: TimeInterval) {
        duckDepth += 1
        if let m = music { m.setVolume(musicVolume * duckFactor, fadeDuration: 0.15) }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            self.duckDepth = max(0, self.duckDepth - 1)
            if self.duckDepth == 0, let m = self.music { m.setVolume(self.musicVolume, fadeDuration: 0.4) }
        }
    }

    // MARK: Music & loops

    private var musicVolume: Float { masterBus * musicBus }

    func setMusic(_ track: MusicTrack?) {
        wantedTrack = track
        guard settings.music, !loopsSuspended else { return }
        startWantedMusic()
    }

    private func startWantedMusic() {
        guard wantedTrack != musicTrack || music?.isPlaying != true else { return }
        if let old = music { fadeOut(old, duration: crossfade) }
        music = nil
        musicTrack = nil
        guard let track = wantedTrack, let p = makePlayer(track.rawValue) else { return }
        p.numberOfLoops = -1
        p.volume = 0
        p.play()
        p.setVolume(duckDepth > 0 ? musicVolume * duckFactor : musicVolume, fadeDuration: crossfade)
        music = p
        musicTrack = track
    }

    private func fadeOut(_ p: AVAudioPlayer, duration: TimeInterval) {
        fading.append(p)
        p.setVolume(0, fadeDuration: duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            p.stop()
            self?.fading.removeAll { $0 === p }
        }
    }

    func setAmbience(_ loop: AmbienceLoop, on: Bool) {
        if on { wantedAmbience.insert(loop) } else { wantedAmbience.remove(loop) }
        guard !loopsSuspended else { return }
        applyAmbience(loop)
    }

    private func applyAmbience(_ loop: AmbienceLoop) {
        let wanted = wantedAmbience.contains(loop) && settings.effects
        if wanted {
            if ambience[loop]?.isPlaying == true { return }
            guard let p = ambience[loop] ?? makePlayer(loop.rawValue) else { return }
            p.numberOfLoops = -1
            p.volume = masterBus * ambienceBus
            p.play()
            ambience[loop] = p
        } else if let p = ambience[loop] {
            p.pause()
            p.currentTime = 0
        }
    }

    func stopAllLoops() {
        loopsSuspended = true
        if let m = music { m.stop() }
        music = nil
        musicTrack = nil
        for (_, p) in ambience { p.pause() }
        for p in fading { p.stop() }
        fading.removeAll()
    }

    func resumeMusicIfNeeded() {
        loopsSuspended = false
        try? AVAudioSession.sharedInstance().setActive(true)
        if settings.music { startWantedMusic() }
        for loop in [AmbienceLoop.cityAir, .craneMotor] { applyAmbience(loop) }
    }

    // MARK: System events

    var onInterruption: ((Bool) -> Void)?

    @objc private func interruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if type == .began {
                self.stopEffects()
                self.stopAllLoops()
                self.onInterruption?(true)
            } else {
                self.onInterruption?(false)
            }
        }
    }

    @objc private func routeChange(_ note: Notification) {
        // Headphones unplugged: keep ambient category behaviour, no auto-boost.
    }
}

final class HapticEngine: HapticService {
    var enabled = true
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    init() {
        soft.prepare()
        notification.prepare()
    }

    func play(_ kind: HapticKind) {
        guard enabled else { return }
        switch kind {
        case .landing: soft.impactOccurred(); soft.prepare()
        case .perfect: notification.notificationOccurred(.success); notification.prepare()
        case .failure: notification.notificationOccurred(.warning); notification.prepare()
        case .selection: selection.selectionChanged()
        }
    }
}

/// Silent implementations for fixtures and unit tests.
final class SilentAudio: AudioService {
    func apply(settings: GameSettings) {}
    func play(_ cue: SoundCue) {}
    func setMusic(_ track: MusicTrack?) {}
    func setAmbience(_ loop: AmbienceLoop, on: Bool) {}
    func stopAllLoops() {}
    func stopEffects() {}
    func resumeMusicIfNeeded() {}
}

final class SilentHaptics: HapticService {
    var enabled = false
    func play(_ kind: HapticKind) {}
}
