import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var keyword: String = ""
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var results: [Song] = []
    @Published var hasSearched: Bool = false
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
    
    // Multi-select
    @Published var isSelectionMode: Bool = false {
        didSet {
            if !isSelectionMode {
                selectedSongs.removeAll()
            }
        }
    }
    @Published var selectedSongs: Set<String> = []

    private let apiClient: APIClient
    private var searchTask: Task<Void, Never>?
    private let persistence = PersistenceManager.shared

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        // Load history? Or just let PersistenceManager handle it until UI needs it.
        // User asked for "Last Search History" to be persisted, not necessarily shown on launch (though it's good UX).
        // Let's restore last keyword if desired, or just ensure we save it.
    }

    func reset() {
        keyword = ""
        results = []
        lastError = nil
        isSelectionMode = false
        hasSearched = false
    }

    func search() {
        searchTask?.cancel()
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            return
        }
        
        // Save History
        persistence.saveHistory(lastQuery: query, recentQueries: []) // Implement robust history list if needed later
        
        isSearching = true
        lastError = nil
        currentPage = 1
        hasMore = true
        results = [] // Clear existing results
        // Exit selection mode on new search
        isSelectionMode = false
        
        searchTask = Task { [weak self, selectedSource] in
            guard let self else { return }
            await performSearch(query: query, source: selectedSource, page: 1)
        }
    }
    
    func toggleSelection(_ song: Song) {
        guard isSelectionMode else { return }
        if selectedSongs.contains(song.identity) {
            selectedSongs.remove(song.identity)
        } else {
            selectedSongs.insert(song.identity)
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
                    self.hasSearched = true
                }
            }
        } catch {
             // ...
             if !Task.isCancelled {
                await MainActor.run {
                    if page == 1 {
                         self.lastError = error.localizedDescription
                    }
                    self.isSearching = false
                    self.hasSearched = true
                }
             }
        }
    }

}
