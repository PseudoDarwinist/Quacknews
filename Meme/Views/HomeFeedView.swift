import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.quacknews.app", category: "HomeFeedView")

struct HomeFeedView: View {
    @State private var selectedCategory: NewsItem.NewsCategory?
    @State private var newsItems: [NewsItem] = []
    @State private var isRefreshing = false
    @State private var errorMessage: String?
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
                    
                    if !newsItems.isEmpty {
                        // News Cards
                        LazyVStack(spacing: 20) {
                            ForEach(filteredNews) { newsItem in
                                NavigationLink(destination: NewsDetailView(newsItem: newsItem)) {
                                    NewsCard(newsItem: newsItem)
                                        .transition(.opacity.combined(with: .scale))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .simultaneousGesture(TapGesture().onEnded {
                                    logger.debug("Tapped news item: \(newsItem.title)")
                                })
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView {
                            Label(
                                errorMessage ?? "Loading News...",
                                systemImage: errorMessage != nil ? "exclamationmark.triangle" : "newspaper"
                            )
                        } description: {
                            if errorMessage != nil {
                                Text("Pull to refresh and try again")
                            }
                        }
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
        }
    }
    
    private var filteredNews: [NewsItem] {
        guard let selectedCategory = selectedCategory else { 
            logger.debug("Showing all news items: \(newsItems.count)")
            return newsItems 
        }
        let filtered = newsItems.filter { $0.category == selectedCategory }
        logger.debug("Filtered news items for \(selectedCategory.rawValue): \(filtered.count)")
        return filtered
    }
    
    private func refreshContent() async {
        logger.info("Starting content refresh")
        isRefreshing = true
        errorMessage = nil
        
        do {
            let startTime = Date()
            newsItems = try await RedditService.shared.fetchNews()
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Content refresh completed in \(String(format: "%.2f", duration))s with \(newsItems.count) items")
        } catch {
            logger.error("Content refresh failed: \(error.localizedDescription)")
            errorMessage = "Failed to load news: \(error.localizedDescription)"
        }
        
        isRefreshing = false
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
    }
}

#Preview {
    HomeFeedView()
} 