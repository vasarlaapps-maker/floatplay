import Foundation
import Combine

final class RecentVideosManager: ObservableObject {

    struct VideoItem: Codable, Identifiable {
        let id: String          // UUID string
        let videoID: String     // YouTube video ID
        let addedAt: Date

        /// Falls back to the raw video ID when no custom title is stored.
        var displayTitle: String { videoID }
    }

    @Published private(set) var recentVideos: [VideoItem] = []

    private let maxItems = 15
    private let storageKey = "sos_recentVideos"

    init() {
        load()
    }

    // MARK: - Public

    func add(videoID: String) {
        var updated = recentVideos.filter { $0.videoID != videoID }
        let item = VideoItem(id: UUID().uuidString, videoID: videoID, addedAt: Date())
        updated.insert(item, at: 0)
        recentVideos = Array(updated.prefix(maxItems))
        persist()
    }

    func clearAll() {
        recentVideos = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(recentVideos) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let items = try? JSONDecoder().decode([VideoItem].self, from: data)
        else { return }
        recentVideos = items
    }
}
