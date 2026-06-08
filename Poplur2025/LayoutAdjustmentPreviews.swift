import SwiftUI

#if DEBUG
enum LayoutPreviewTab: String, CaseIterable, Identifiable {
    case map = "Map"
    case record = "Record"
    case feed = "Feed"
    case profile = "Profile"

    var id: String { rawValue }
}

private struct LayoutPreviewPlacement {
    var alignment: Alignment
    var offset: CGSize = .zero
}

private enum LayoutPreviewPositions {
    static let canvasSize = CGSize(width: 390, height: 844)

    static let mapTitle = LayoutPreviewPlacement(alignment: .topLeading, offset: CGSize(width: 20, height: 56))
    static let mapSubtitle = LayoutPreviewPlacement(alignment: .topLeading, offset: CGSize(width: 20, height: 96))
    static let mapLocationButton = LayoutPreviewPlacement(alignment: .topTrailing, offset: CGSize(width: -20, height: 58))
    static let mapZoomOutButton = LayoutPreviewPlacement(alignment: .bottomLeading, offset: CGSize(width: 24, height: -54))
    static let mapZoomInButton = LayoutPreviewPlacement(alignment: .bottomTrailing, offset: CGSize(width: -24, height: -54))

    static let recordTitle = LayoutPreviewPlacement(alignment: .top, offset: CGSize(width: 0, height: 62))
    static let recordSubtitle = LayoutPreviewPlacement(alignment: .top, offset: CGSize(width: 0, height: 102))
    static let recordFlipButton = LayoutPreviewPlacement(alignment: .topTrailing, offset: CGSize(width: -22, height: 58))
    static let recordLibraryButton = LayoutPreviewPlacement(alignment: .bottomLeading, offset: CGSize(width: 28, height: -64))
    static let recordCaptureButton = LayoutPreviewPlacement(alignment: .bottom, offset: CGSize(width: 0, height: -48))

    static let feedTitle = LayoutPreviewPlacement(alignment: .topLeading, offset: CGSize(width: 20, height: 54))
    static let feedSubtitle = LayoutPreviewPlacement(alignment: .topLeading, offset: CGSize(width: 20, height: 92))
    static let feedFilterButton = LayoutPreviewPlacement(alignment: .topTrailing, offset: CGSize(width: -20, height: 58))
    static let feedActionStack = LayoutPreviewPlacement(alignment: .trailing, offset: CGSize(width: -18, height: 80))

    static let profileAvatar = LayoutPreviewPlacement(alignment: .topLeading, offset: CGSize(width: 20, height: 58))
    static let profileTitle = LayoutPreviewPlacement(alignment: .topLeading, offset: CGSize(width: 126, height: 68))
    static let profileSubtitle = LayoutPreviewPlacement(alignment: .topLeading, offset: CGSize(width: 126, height: 104))
    static let profileSettingsButton = LayoutPreviewPlacement(alignment: .topTrailing, offset: CGSize(width: -20, height: 62))
    static let profileTabs = LayoutPreviewPlacement(alignment: .top, offset: CGSize(width: 0, height: 178))
}

struct LayoutAdjustmentCanvas: View {
    let tab: LayoutPreviewTab
    var showGrid = true

    var body: some View {
        ZStack {
            background

            if showGrid {
                LayoutGrid()
                    .opacity(0.45)
            }

            switch tab {
            case .map:
                MapLayoutPreview()
            case .record:
                RecordLayoutPreview()
            case .feed:
                FeedLayoutPreview()
            case .profile:
                ProfileLayoutPreview()
            }
        }
        .frame(width: LayoutPreviewPositions.canvasSize.width, height: LayoutPreviewPositions.canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(Color.black)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.07, blue: 0.08),
                Color(red: 0.12, green: 0.15, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct LayoutGrid: View {
    var body: some View {
        Canvas { context, size in
            var fine = Path()
            for x in stride(from: 0, through: size.width, by: CGFloat(20)) {
                fine.move(to: CGPoint(x: x, y: 0))
                fine.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: CGFloat(20)) {
                fine.move(to: CGPoint(x: 0, y: y))
                fine.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(fine, with: .color(.white.opacity(0.10)), lineWidth: 0.5)

            var major = Path()
            for x in stride(from: 0, through: size.width, by: CGFloat(100)) {
                major.move(to: CGPoint(x: x, y: 0))
                major.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: CGFloat(100)) {
                major.move(to: CGPoint(x: 0, y: y))
                major.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(major, with: .color(.white.opacity(0.22)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct MapLayoutPreview: View {
    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(0.18))
                    .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
                    .frame(width: CGFloat(18 + (index % 3) * 8), height: CGFloat(18 + (index % 3) * 8))
                    .position(
                        x: [74, 148, 246, 326, 110, 286, 210, 52, 344][index],
                        y: [154, 238, 184, 312, 428, 500, 620, 694, 724][index]
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Toronto")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("Now playing - local radio")
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(0.72)
            }
            .foregroundStyle(.white)
            .place(LayoutPreviewPositions.mapTitle)

            IconButton(systemName: "location.fill")
                .place(LayoutPreviewPositions.mapLocationButton)
            IconButton(systemName: "minus")
                .place(LayoutPreviewPositions.mapZoomOutButton)
            IconButton(systemName: "plus")
                .place(LayoutPreviewPositions.mapZoomInButton)
        }
    }
}

private struct RecordLayoutPreview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.22))
                .overlay {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 74, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(18)

            Text("Record")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .place(LayoutPreviewPositions.recordTitle)

            Text("Hold to capture")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
                .place(LayoutPreviewPositions.recordSubtitle)

            IconButton(systemName: "arrow.triangle.2.circlepath.camera")
                .place(LayoutPreviewPositions.recordFlipButton)
            IconButton(systemName: "photo.on.rectangle")
                .place(LayoutPreviewPositions.recordLibraryButton)

            Circle()
                .strokeBorder(.white, lineWidth: 5)
                .background(Circle().fill(.white.opacity(0.18)))
                .frame(width: 86, height: 86)
                .place(LayoutPreviewPositions.recordCaptureButton)
        }
    }
}

private struct FeedLayoutPreview: View {
    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                ForEach(0..<2, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hue: Double(index) * 0.12 + 0.55, saturation: 0.36, brightness: 0.82),
                                    .black.opacity(0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 330)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 126)

            VStack(alignment: .leading, spacing: 4) {
                Text("United States")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                Text("Food")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(0.70)
            }
            .foregroundStyle(.white)
            .place(LayoutPreviewPositions.feedTitle)

            IconButton(systemName: "slider.horizontal.3")
                .place(LayoutPreviewPositions.feedFilterButton)

            VStack(spacing: 18) {
                IconButton(systemName: "heart.fill")
                IconButton(systemName: "bubble.right.fill")
                IconButton(systemName: "paperplane.fill")
            }
            .place(LayoutPreviewPositions.feedActionStack)
        }
    }
}

private struct ProfileLayoutPreview: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.16))
                .overlay {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .frame(width: 92, height: 92)
                .place(LayoutPreviewPositions.profileAvatar)

            VStack(alignment: .leading, spacing: 7) {
                Text("@preview_user")
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                Text("42 posts  |  18.4 km")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.74)
            }
            .foregroundStyle(.white)
            .place(LayoutPreviewPositions.profileTitle)

            IconButton(systemName: "gearshape.fill")
                .place(LayoutPreviewPositions.profileSettingsButton)

            HStack(spacing: 10) {
                Text("Media")
                    .pill(isSelected: true)
                Text("Messages")
                    .pill(isSelected: false)
                IconButton(systemName: "plus", size: 40)
            }
            .place(LayoutPreviewPositions.profileTabs)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(0..<12, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hue: Double(index % 8) / 8.0, saturation: 0.36, brightness: 0.78))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 236)
        }
    }
}

private struct IconButton: View {
    let systemName: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.43, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.white.opacity(0.14), in: Circle())
    }
}

private extension View {
    func place(_ placement: LayoutPreviewPlacement) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement.alignment)
            .offset(placement.offset)
    }
}

private extension Text {
    func pill(isSelected: Bool) -> some View {
        font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(isSelected ? .black : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(isSelected ? .white : .white.opacity(0.14), in: Capsule())
    }
}

struct LayoutAdjustmentPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            LayoutAdjustmentCanvas(tab: .map)
                .previewDisplayName("Map Layout")
            LayoutAdjustmentCanvas(tab: .record)
                .previewDisplayName("Record Layout")
            LayoutAdjustmentCanvas(tab: .feed)
                .previewDisplayName("Feed Layout")
            LayoutAdjustmentCanvas(tab: .profile)
                .previewDisplayName("Profile Layout")
        }
    }
}
#endif
