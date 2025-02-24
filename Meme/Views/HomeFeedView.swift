import SwiftUI

struct HomeFeedView: View {
    @State private var selectedCategory: NewsItem.NewsCategory?
    @State private var newsItems: [NewsItem] = []
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @Environment(\.openURL) private var openURL
    
    private let animation = Animation.spring(response: 0.5, dampingFraction: 0.8)
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Category Selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            CategoryButton(title: "All", isSelected: selectedCategory == nil) {
                                withAnimation(animation) {
                                    selectedCategory = nil
                                }
                            }
                            
                            ForEach(NewsItem.NewsCategory.allCases, id: \.self) { category in
                                CategoryButton(
                                    title: category.rawValue,
                                    isSelected: selectedCategory == category
                                ) {
                                    withAnimation(animation) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                    
                    if !newsItems.isEmpty {
                        // News Cards
                        LazyVStack(spacing: 20) {
                            ForEach(filteredNews) { newsItem in
                                NavigationLink {
                                    NewsDetailView(newsItem: newsItem)
                                } label: {
                                    NewsCard(newsItem: newsItem)
                                        .transition(.opacity.combined(with: .scale))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView(
                            label: {
                                Label(
                                    errorMessage ?? "Loading News...",
                                    systemImage: errorMessage != nil ? "exclamationmark.triangle" : "newspaper"
                                )
                            },
                            description: {
                                if errorMessage != nil {
                                    Text("Pull to refresh and try again")
                                }
                            }
                        )
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
                await refreshContent()
            }
            .task {
                if newsItems.isEmpty {
                    await refreshContent()
                }
            }
        }
    }
    
    private var filteredNews: [NewsItem] {
        guard let selectedCategory = selectedCategory else { return newsItems }
        return newsItems.filter { $0.category == selectedCategory }
    }
    
    private func refreshContent() async {
        isRefreshing = true
        errorMessage = nil
        
        do {
            newsItems = try await RedditService.shared.fetchNews()
        } catch {
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