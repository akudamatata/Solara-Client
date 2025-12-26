import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var keyword: String = ""
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var results: [Song] = []
    @Published var selectedSource: SongSource = .netease {
        didSet {
            if !keyword.isEmpty {
                search()
            }
        }
    }
    @Published var lastError: String?

    private let apiClient: APIClient
    private var searchTask: Task<Void, Never>?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func reset() {
        keyword = ""
        results = []
        lastError = nil
    }

    func search() {
        searchTask?.cancel()
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            return
        }
        isSearching = true
        lastError = nil
        
        searchTask = Task { [weak self, selectedSource] in
            guard let self else { return }
            await performSearch(query: query, source: selectedSource)
        }
    }

    private func performSearch(query: String, source: SongSource) async {
        do {
            let songs = try await apiClient.search(keyword: query, source: source)
            if !Task.isCancelled {
                await MainActor.run {
                    self.results = songs
                    self.isSearching = false
                }
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }
}
