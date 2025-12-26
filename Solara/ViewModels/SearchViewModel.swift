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
    @Published var currentPage: Int = 1
    @Published var hasMore: Bool = true

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
        currentPage = 1
        hasMore = true
        results = [] // Clear existing results
        
        searchTask = Task { [weak self, selectedSource] in
            guard let self else { return }
            await performSearch(query: query, source: selectedSource, page: 1)
        }
    }
    
    func loadMore() {
        guard !isSearching, hasMore, !keyword.isEmpty else { return }
        
        isSearching = true
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextPage = currentPage + 1
        
        searchTask = Task { [weak self, selectedSource] in
            guard let self else { return }
            await performSearch(query: query, source: selectedSource, page: nextPage)
        }
    }

    private func performSearch(query: String, source: SongSource, page: Int) async {
        do {
            let limit = 20
            let songs = try await apiClient.search(keyword: query, source: source, limit: limit, page: page)
            
            if !Task.isCancelled {
                await MainActor.run {
                    if page == 1 {
                        self.results = songs
                    } else {
                        self.results.append(contentsOf: songs)
                    }
                    
                    self.currentPage = page
                    self.hasMore = songs.count >= limit // Simple heuristic
                    self.isSearching = false
                }
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run {
                    // Only show error for first page, otherwise just stop loading more
                    if page == 1 {
                        self.lastError = error.localizedDescription
                    }
                    self.isSearching = false
                }
            }
        }
    }
}
