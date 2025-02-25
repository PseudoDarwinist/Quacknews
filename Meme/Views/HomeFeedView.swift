import SwiftUI
import OSLog
import FirebaseFirestore

private let logger = Logger(subsystem: "com.quacknews.app", category: "HomeFeedView")

struct HomeFeedView: View {
    @State private var selectedCategory: NewsItem.NewsCategory?
    @State private var newsItems: [NewsItem] = []
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var isOffline = false
    @State private var showDebugInfo = false
    @State private var debugInfo: String = ""
    @State private var includeRedditContent = true
    @Environment(\.openURL) private var openURL
    
    private let animation = Animation.spring(response: 0.5, dampingFraction: 0.8)
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(spacing: 16) {
                    // Category Selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            CategoryButton(
                                title: "All",
                                isSelected: selectedCategory == nil,
                                action: {
                                    withAnimation(animation) {
                                        logger.debug("Category selected: All")
                                        selectedCategory = nil
                                    }
                                }
                            )
                            
                            ForEach(NewsItem.NewsCategory.allCases, id: \.self) { category in
                                CategoryButton(
                                    title: category.rawValue,
                                    isSelected: selectedCategory == category,
                                    action: {
                                        withAnimation(animation) {
                                            logger.debug("Category selected: \(category.rawValue)")
                                            selectedCategory = category
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemBackground))
                    .zIndex(1) // Ensure category selector is above other content
                    
                    Divider()
                        .padding(.bottom, 8)
                    
                    if isOffline {
                        OfflineBanner()
                    }
                    
                    if !newsItems.isEmpty {
                        // News Cards
                        LazyVStack(spacing: 20) {
                            ForEach(filteredNews) { newsItem in
                                NavigationLink(destination: NewsDetailView(newsItem: newsItem)) {
                                    NewsCard(newsItem: newsItem)
                                        .transition(.opacity.combined(with: .scale))
                                }
                                .id(newsItem.id.uuidString)
                                .buttonStyle(PlainButtonStyle())
                                .simultaneousGesture(TapGesture().onEnded {
                                    logger.debug("Tapped news item: \(newsItem.title) with category: \(newsItem.category.rawValue)")
                                })
                            }
                        }
                        .padding(.horizontal)
                        .id(selectedCategory?.rawValue ?? "all")
                    } else if isRefreshing {
                        ProgressView("Loading News...")
                            .padding(.top, 100)
                    } else {
                        ContentUnavailableView {
                            Label(
                                errorMessage ?? "No News Available",
                                systemImage: errorMessage != nil ? "exclamationmark.triangle" : "newspaper"
                            )
                        } description: {
                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                
                                Button("Try Again") {
                                    Task {
                                        await refreshContent()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .padding(.top)
                            } else {
                                Text("Pull to refresh and try again")
                            }
                        }
                        .padding(.top, 100)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                        Text("QuackNews")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        NavigationLink("Admin Upload") {
                            AdminUploadView()
                        }
                        
                        Toggle("Include Reddit Content", isOn: $includeRedditContent)
                            .onChange(of: includeRedditContent) { _ in
                                Task {
                                    await refreshContent(forceRefresh: true)
                                }
                            }
                        
                        Button("Debug Firebase") {
                            Task {
                                await debugFirebase()
                            }
                        }
                        
                        Button(showDebugInfo ? "Hide Debug Info" : "Show Debug Info") {
                            showDebugInfo.toggle()
                        }
                        
                        Button("Force Refresh") {
                            Task {
                                await refreshContent(forceRefresh: true)
                            }
                        }
                        
                        Button("Fix Categories") {
                            Task {
                                await fixCategories()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                logger.debug("Manual refresh triggered")
                await refreshContent()
            }
            .task {
                if newsItems.isEmpty {
                    logger.debug("Initial content load")
                    await refreshContent()
                }
            }
            .sheet(isPresented: $showDebugInfo) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading) {
                            Text(debugInfo)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                        }
                    }
                    .navigationTitle("Debug Information")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Close") {
                                showDebugInfo = false
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Copy") {
                                UIPasteboard.general.string = debugInfo
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var filteredNews: [NewsItem] {
        guard let selectedCategory = selectedCategory else { 
            logger.debug("Showing all news items: \(newsItems.count)")
            return newsItems 
        }
        
        // Log all categories for debugging
        let allCategories = newsItems.map { $0.category.rawValue }
        logger.debug("All available categories: \(Set(allCategories).joined(separator: ", "))")
        
        // Filter by exact category match using string comparison to avoid enum comparison issues
        let selectedCategoryString = selectedCategory.rawValue
        let filtered = newsItems.filter { item in
            let itemCategoryString = item.category.rawValue
            let matches = itemCategoryString == selectedCategoryString
            logger.debug("Item '\(item.title)' category: \(itemCategoryString), selected: \(selectedCategoryString), matches: \(matches)")
            return matches
        }
        
        logger.debug("Filtered news items for \(selectedCategory.rawValue): \(filtered.count) out of \(newsItems.count)")
        
        if filtered.isEmpty {
            logger.warning("No items found for category: \(selectedCategory.rawValue)")
        }
        
        return filtered
    }
    
    private func refreshContent(forceRefresh: Bool = false) async {
        logger.info("Starting content refresh")
        isRefreshing = true
        errorMessage = nil
        isOffline = false
        
        do {
            let startTime = Date()
            
            // Try Firebase first
            do {
                let firebaseNews = try await FirebaseManager.shared.fetchNews(includeReddit: includeRedditContent)
                if !firebaseNews.isEmpty {
                    newsItems = firebaseNews
                    logger.info("Loaded \(firebaseNews.count) news items")
                    
                    // Add debug info
                    debugInfo = "News items: \(firebaseNews.count)\n"
                    
                    // Count items by source
                    let manualCount = firebaseNews.filter { $0.redditURL.absoluteString.contains("reddit.com") == false }.count
                    let redditCount = firebaseNews.count - manualCount
                    debugInfo += "Manual items: \(manualCount)\n"
                    debugInfo += "Reddit items: \(redditCount)\n"
                    
                    // Count by category
                    let categoryCounts = Dictionary(grouping: firebaseNews, by: { $0.category.rawValue })
                        .mapValues { $0.count }
                        .sorted(by: { $0.value > $1.value })
                    
                    debugInfo += "\nItems by category:\n"
                    for (category, count) in categoryCounts {
                        debugInfo += "- \(category): \(count)\n"
                    }
                    
                    debugInfo += "\nDetailed news items:\n"
                    for (index, item) in firebaseNews.enumerated() {
                        let source = item.redditURL.absoluteString.contains("reddit.com") ? "Reddit" : "Manual"
                        debugInfo += "\n\(index+1). \(item.title)\n"
                        debugInfo += "   Category: \(item.category.rawValue)\n"
                        debugInfo += "   Source: \(source)\n"
                        debugInfo += "   Memes: \(item.relatedMemes.count)\n"
                        debugInfo += "   Date: \(item.publishedDate)\n"
                    }
                } else if forceRefresh || newsItems.isEmpty {
                    // Fallback to Reddit if no data
                    logger.info("No data, falling back to Reddit")
                    newsItems = try await RedditService.shared.fetchNews()
                }
            } catch {
                // If Firebase fails, try Reddit
                logger.warning("Firebase fetch failed: \(error.localizedDescription)")
                debugInfo = "Firebase error: \(error.localizedDescription)"
                
                if forceRefresh || newsItems.isEmpty {
                    do {
                        newsItems = try await RedditService.shared.fetchNews()
                    } catch {
                        // If both fail, check if it's a network error
                        logger.error("Reddit fetch also failed: \(error.localizedDescription)")
                        debugInfo += "\nReddit error: \(error.localizedDescription)"
                        
                        if let nsError = error as NSError?, 
                           nsError.domain == NSURLErrorDomain && 
                           (nsError.code == NSURLErrorNotConnectedToInternet || 
                            nsError.code == NSURLErrorNetworkConnectionLost) {
                            isOffline = true
                            errorMessage = "You appear to be offline. Please check your internet connection."
                        } else {
                            errorMessage = "Failed to load news: \(error.localizedDescription)"
                        }
                        
                        // If we have cached news, keep showing them
                        if newsItems.isEmpty {
                            errorMessage = "No news available. Please check your connection and try again."
                        }
                    }
                }
            }
            
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Content refresh completed in \(String(format: "%.2f", duration))s with \(newsItems.count) items")
        } catch {
            logger.error("Content refresh failed: \(error.localizedDescription)")
            errorMessage = "Failed to load news: \(error.localizedDescription)"
            debugInfo = "Refresh error: \(error.localizedDescription)"
        }
        
        isRefreshing = false
    }
    
    private func debugFirebase() async {
        debugInfo = "Starting Firebase debug...\n"
        showDebugInfo = true
        
        do {
            // List all documents
            await FirebaseManager.shared.listAllDocuments()
            
            // Try to fetch news
            let news = try await FirebaseManager.shared.fetchNews(includeReddit: false)
            debugInfo += "\nFetched \(news.count) news items from Firebase\n"
            
            // Group by category
            var newsByCategory: [String: [NewsItem]] = [:]
            for item in news {
                let category = item.category.rawValue
                if newsByCategory[category] == nil {
                    newsByCategory[category] = []
                }
                newsByCategory[category]?.append(item)
            }
            
            // Show items by category
            debugInfo += "\n--- News Items by Category ---\n"
            for (category, items) in newsByCategory.sorted(by: { $0.key < $1.key }) {
                debugInfo += "\n\(category) (\(items.count) items):\n"
                for (index, item) in items.enumerated() {
                    debugInfo += "  \(index+1). \(item.title)\n"
                }
            }
            
            debugInfo += "\n--- Detailed News Items ---\n"
            for (index, item) in news.enumerated() {
                debugInfo += "\n\(index+1). \(item.title)\n"
                debugInfo += "   Category: \(item.category.rawValue)\n"
                debugInfo += "   Memes: \(item.relatedMemes.count)\n"
                debugInfo += "   Date: \(formatDate(item.publishedDate))\n"
                debugInfo += "   Image URL: \(item.imageURL?.absoluteString ?? "nil")\n"
            }
            
            if news.isEmpty {
                debugInfo += "\nNo news items found in Firebase. Possible issues:\n"
                debugInfo += "1. Firebase collection 'news' might be empty\n"
                debugInfo += "2. There might be permission issues\n"
                debugInfo += "3. The data format might be incorrect\n"
                
                // Try to fetch directly from Firestore
                do {
                    let snapshot = try await Firestore.firestore().collection("news").getDocuments()
                    debugInfo += "\nRaw Firestore query found \(snapshot.documents.count) documents\n"
                    
                    for (index, doc) in snapshot.documents.enumerated() {
                        let data = doc.data()
                        debugInfo += "\n\(index+1). Document ID: \(doc.documentID)\n"
                        debugInfo += "   Title: \(data["title"] as? String ?? "nil")\n"
                        debugInfo += "   Category: \(data["category"] as? String ?? "nil")\n"
                    }
                } catch {
                    debugInfo += "\nError querying Firestore directly: \(error.localizedDescription)\n"
                }
            }
            
            // Try to fetch Reddit news
            if includeRedditContent {
                do {
                    let redditNews = try await RedditService.shared.fetchNews()
                    debugInfo += "\nFetched \(redditNews.count) news items from Reddit\n"
                    
                    debugInfo += "\n--- Reddit News Items ---\n"
                    for (index, item) in redditNews.enumerated() {
                        debugInfo += "\n\(index+1). \(item.title)\n"
                        debugInfo += "   Category: \(item.category.rawValue)\n"
                        debugInfo += "   Memes: \(item.relatedMemes.count)\n"
                    }
                } catch {
                    debugInfo += "\nError fetching from Reddit: \(error.localizedDescription)\n"
                }
            } else {
                debugInfo += "\nReddit content is disabled\n"
            }
        } catch {
            debugInfo += "\nError: \(error.localizedDescription)"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func fixCategories() async {
        debugInfo = "Starting category fix...\n"
        showDebugInfo = true
        isRefreshing = true
        
        // First, log current categories
        debugInfo += "Current news items and categories:\n"
        for (index, item) in newsItems.enumerated() {
            debugInfo += "\(index+1). \(item.title): \(item.category.rawValue)\n"
        }
        
        // Update categories in Firebase
        await FirebaseManager.shared.updateNewsCategories()
        
        // Refresh content to get updated categories
        await refreshContent(forceRefresh: true)
        
        // Log updated categories
        debugInfo += "\nUpdated news items and categories:\n"
        for (index, item) in newsItems.enumerated() {
            debugInfo += "\(index+1). \(item.title): \(item.category.rawValue)\n"
        }
        
        debugInfo += "\nCategory fix completed. Please check if categories are now correct."
        isRefreshing = false
    }
}

struct OfflineBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("You're offline")
            Spacer()
        }
        .font(.subheadline)
        .foregroundColor(.white)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.8))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.1))
                )
        }
        .contentShape(Rectangle()) // Ensure the entire button area is tappable
        .buttonStyle(ScaledButtonStyle()) // Custom button style for better feedback
    }
}

// Custom button style to provide better tap feedback
struct ScaledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    HomeFeedView()
} 
