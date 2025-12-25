import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var keyword: String = ""
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var results: [SongSource: [Song]] = [:]
    @Published private(set) var aggregated: [Song] = []
    @Published var selected: Set<String> = []
    @Published var lastError: String?

    private let apiClient: APIClient
    private var searchTask: Task<Void, Never>?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func toggleSelection(for song: Song) {
        if selected.contains(song.identity) {
            selected.remove(song.identity)
        } else {
            selected.insert(song.identity)
        }
    }

    func clearSelection() {
        selected.removeAll()
    }

    func searchAllSources() {
        searchTask?.cancel()
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            aggregated = []
            results = [:]
            return
        }
        isSearching = true
        lastError = nil
        searchTask = Task { [weak self] in
            guard let self else { return }
            await performAggregatedSearch(query: query)
        }
    }

    private func performAggregatedSearch(query: String) async {
        var container: [SongSource: [Song]] = [:]
        do {
            try await withThrowingTaskGroup(of: (SongSource, [Song]).self) { group in
                for source in SongSource.allCases {
                    group.addTask {
                        let songs = try await self.apiClient.search(keyword: query, source: source)
                        return (source, songs)
                    }
                }
                for try await result in group {
                    container[result.0] = result.1
                }
            }
            await MainActor.run {
                results = container
                aggregated = SongSource.allCases.flatMap { container[$0] ?? [] }
                isSearching = false
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
                isSearching = false
            }
        }
    }
}
