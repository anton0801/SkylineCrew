import SwiftUI

// MARK: - 26 Tower Collection / 28 Collection Empty

struct CollectionScreen: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.mockMetrics) private var m

    private enum Tile: Hashable {
        case level(Int)
        case free
    }

    var body: some View {
        let bests = app.profile.levelBests
        if bests.isEmpty && app.profile.freeBest == nil {
            emptyState
        } else {
            list(bests)
        }
    }

    private var emptyState: some View {
        MockCanvas {
            BackgroundArt(id: "BG03")
            ScreenHeader(title: "Tower Collection") { app.pop() }
            MockBand(from: 210, to: 470) {
                ArtView("C01", .fit).placed(105, 220, 181, 240).accessibilityHidden(true)
            }
            CreamCard(radius: 24).mock(20, 485, 350, 129, v: .bottom, h: .stretch)
            Text("Your first rooftop awaits").mockStyle(25).mockText(195, 515, .middle, v: .bottom)
            Text("Finish a level to keep its tower").mockStyle(17, Palette.secondary).mockText(195, 549, .middle, v: .bottom)
            Text("here.").mockStyle(17, Palette.secondary).mockText(195, 572, .middle, v: .bottom)
            SkinButton(title: "Build a Tower") {
                let first = app.campaign.nextLevelID ?? 1
                app.push(.brief(first))
            }
            .mock(20, 716, 350, 60, v: .bottom, h: .stretch)
        }
    }

    private func list(_ bests: [LevelBest]) -> some View {
        var tiles: [Tile] = bests.map { .level($0.levelID) }
        if app.profile.freeBest != nil { tiles.append(.free) }
        let rows = (tiles.count + 1) / 2
        let contentBottom = 166 + 281 * CGFloat(rows) + 4
        let stars = app.profile.totalStars
        let built = app.profile.completedCount
        return MockCanvas {
            BackgroundArt(id: "BG03")
            ScreenHeader(title: "Your rooftops", subtitle: "\(built) \(built == 1 ? "tower" : "towers") built · \(stars) \(stars == 1 ? "star" : "stars")") { app.pop() }
            MockScrollBand(from: 150, to: 740, contentBottom: max(740, contentBottom)) {
                ForEach(Array(tiles.enumerated()), id: \.element) { i, tile in
                    let x: CGFloat = i % 2 == 0 ? 20 : 201
                    let y: CGFloat = 166 + 281 * CGFloat(i / 2)
                    tileView(tile, x: x, y: y, column: i % 2)
                }
            }
            SkinButton(title: "Free Build") {
                if app.campaign.freeBuildUnlocked { app.push(.freeBuild) } else { app.dialog = .freeBuildLocked }
            }
            .mock(20, 752, 350, 60, v: .bottom, h: .stretch)
        }
    }

    private func tileView(_ tile: Tile, x: CGFloat, y: CGFloat, column: Int) -> some View {
        let layout: [Placement]
        let label: String
        let a11y: String
        switch tile {
        case .level(let id):
            let best = app.profile.best(for: id)!
            layout = best.layout
            label = "Tower \(id)"
            a11y = "Tower \(id), \(best.bestStars) stars, \(Scoring.percent(best.layoutPrecision)) percent precision\(best.layoutAssisted ? ", assisted" : "")"
        case .free:
            let rec = app.profile.freeBest!
            layout = rec.layout
            label = "Free Build"
            a11y = "Free Build record, \(rec.height) floors"
        }
        // Two columns keep 20 pt outer margins and a 12 pt gutter on every width.
        let tileW = (m.size.width - 52) / 2
        let tileX = column == 0 ? 20 : 32 + tileW
        let spec = TowerSpec.collectionTile(originX: tileX + (tileW - 169) / 2, originY: y)
        return ZStack(alignment: .topLeading) {
            CreamCard(radius: 24).placed(tileX, y, tileW, 260)
            TowerView(spec: spec, floors: layout.towerFloors(floorWidth: 93), fitTop: y + 14)
                .allowsHitTesting(false)
            Text(label).mockStyle(18).placedText(tileX + tileW / 2, y + 232, .middle)
            TapArea(label: a11y) {
                switch tile {
                case .level(let id): app.push(.towerDetail(.level(id)))
                case .free: app.push(.towerDetail(.freeBest))
                }
            }
            .placed(tileX, y, tileW, 260)
        }
    }
}

// MARK: - 27 Tower Detail

struct TowerDetailScreen: View {
    let ref: TowerRef
    @EnvironmentObject private var app: AppModel

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        switch ref {
        case .level(let id):
            if let best = app.profile.best(for: id), let district = app.content.district(forLevel: id) {
                detail(title: "\(district.name) · Tower \(id)",
                       subtitle: "\(best.layout.count) floors · \(Scoring.percent(best.layoutPrecision))% precision\(best.layoutAssisted ? " · Assisted" : "")",
                       footer: "Best build · \(best.bestStars) \(best.bestStars == 1 ? "star" : "stars") · \(Self.dateFormat.string(from: best.layoutDate))",
                       layout: best.layout) {
                    app.push(.brief(id))
                }
            } else {
                Color.clear.onAppear { app.pop() }
            }
        case .freeBest:
            if let rec = app.profile.freeBest {
                detail(title: "Free Build record",
                       subtitle: "\(rec.height) floors · \(Scoring.percent(rec.precision))% precision\(rec.assisted ? " · Assisted" : "")",
                       footer: "Best tower · \(Self.dateFormat.string(from: rec.date))",
                       layout: rec.layout) {
                    app.startFreeBuild()
                }
            } else {
                Color.clear.onAppear { app.pop() }
            }
        }
    }

    private func detail(title: String, subtitle: String, footer: String, layout: [Placement], again: @escaping () -> Void) -> some View {
        MockCanvas {
            BackgroundArt(id: "BG03")
            ScreenHeader(title: title, subtitle: subtitle) { app.pop() }
            MockBand(from: 150, to: 706, align: 1) {
                // Saved assetIDs and offsets — fit-to-height for tall towers.
                TowerView(spec: .showcase, floors: layout.towerFloors(floorWidth: 160), roof: !layout.isEmpty, fitTop: 160)
            }
            Text(footer).mockStyle(18).mockText(195, 707, .middle, v: .bottom)
            SkinButton(title: "Build Again", sound: .levelSelect, action: again)
                .mock(20, 742, 350, 60, v: .bottom, h: .stretch)
        }
    }
}
