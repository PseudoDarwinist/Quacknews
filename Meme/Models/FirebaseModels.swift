import Foundation

// Add this at the top level
enum NewsCategory: String, Codable, CaseIterable {
    case sports = "Sports"
    case elonMusk = "Elon Musk"
    case entertainment = "Entertainment"
    case ads = "Ads"
    case politics = "Politics"
    
    // Add conversion to app's NewsCategory
    func toAppCategory() -> NewsItem.NewsCategory {
        switch self {
        case .sports: return .sports
        case .elonMusk: return .elonMusk
        case .entertainment: return .entertainment
        case .ads: return .ads
        case .politics: return .politics
        }
    }
}

struct FirebaseNewsItem: Codable, Identifiable {
    var id: String?
    let title: String
    let summary: String
    let imageURL: String
    let category: NewsCategory
    let publishedDate: Date
    let source: NewsSource
    let redditURL: String?
    let tags: [String]
    
    enum NewsSource: String, Codable {
        case manual
        case reddit
    }
    
    // Add initializer
    init(id: String? = nil,
         title: String,
         summary: String,
         imageURL: String,
         category: NewsCategory,
         publishedDate: Date = Date(),
         source: NewsSource = .manual,
         redditURL: String? = nil,
         tags: [String] = []) {
        self.id = id
        self.title = title
        self.summary = summary
        self.imageURL = imageURL
        self.category = category
        self.publishedDate = publishedDate
        self.source = source
        self.redditURL = redditURL
        self.tags = tags
    }
    
    // Convert to app's NewsItem model
    func toNewsItem(with memes: [FirebaseMeme]) -> NewsItem {
        NewsItem(
            title: title,
            summary: summary,
            imageURL: URL(string: imageURL),
            category: category.toAppCategory(),  // Use conversion method
            publishedDate: publishedDate,
            relatedMemes: memes.map { $0.toMeme() },
            redditURL: URL(string: redditURL ?? "")!
        )
    }
}

struct FirebaseMeme: Codable, Identifiable {
    var id: String?
    let imageURL: String
    let title: String?
    let source: MemeSource
    let newsId: String
    let category: NewsCategory
    let tags: [String]
    
    enum MemeSource: String, Codable {
        case manual
        case reddit
    }
    
    // Add initializer
    init(id: String? = nil,
         imageURL: String,
         title: String?,
         source: MemeSource,
         newsId: String,
         category: NewsCategory,
         tags: [String]) {
        self.id = id
        self.imageURL = imageURL
        self.title = title
        self.source = source
        self.newsId = newsId
        self.category = category
        self.tags = tags
    }
    
    // Convert to app's Meme model
    func toMeme() -> Meme {
        Meme(
            imageURL: URL(string: imageURL)!,
            source: source == .reddit ? .reddit : .manual,
            title: title,
            redditURL: URL(string: "https://reddit.com")!
        )
    }
} 
