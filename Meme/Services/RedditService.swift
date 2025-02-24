import Foundation

// Reddit API Response Models
struct RedditListing: Codable {
    let data: RedditListingData
}

struct RedditListingData: Codable {
    let children: [RedditPost]
}

struct RedditPost: Codable {
    let data: RedditPostData
}

struct RedditPostData: Codable {
    let title: String
    let selftext: String
    let url: String?
    let thumbnail: String?
    let created_utc: Double
    let subreddit: String
    let permalink: String
    let preview: Preview?
    
    struct Preview: Codable {
        let images: [Image]
        
        struct Image: Codable {
            let source: Source
            
            struct Source: Codable {
                let url: String
            }
        }
    }
}

class RedditService {
    static let shared = RedditService()
    private let session = URLSession.shared
    private let baseURL = "https://www.reddit.com"
    
    // Major news subreddits mapped to categories
    private let newsSubreddits = [
        "Cricket": NewsItem.NewsCategory.sports,        // Cricket news
        "SpaceX": NewsItem.NewsCategory.elonMusk,      // Elon/Tesla/SpaceX news
        "movies": NewsItem.NewsCategory.entertainment,  // Major movie news
        "SuperBowl": NewsItem.NewsCategory.ads,        // Super Bowl ads
        "worldnews": NewsItem.NewsCategory.politics    // Major world politics
    ]
    
    // Meme subreddits with high engagement
    private let memeSubreddits = [
        NewsItem.NewsCategory.sports: ["CricketShitpost", "sportsshitpost"],
        NewsItem.NewsCategory.elonMusk: ["SpaceXMasterrace", "elonmemes"],
        NewsItem.NewsCategory.entertainment: ["moviememes", "PrequelMemes"],
        NewsItem.NewsCategory.ads: ["CommercialMemes", "SuperbOwl"],
        NewsItem.NewsCategory.politics: ["PoliticalMemes", "worldpoliticsmemes"]
    ]
    
    func fetchNews() async throws -> [NewsItem] {
        var allNews: [NewsItem] = []
        
        for (subreddit, category) in newsSubreddits {
            let url = URL(string: "\(baseURL)/r/\(subreddit)/hot.json?limit=3")!
            var request = URLRequest(url: url)
            request.setValue("Meme News App/1.0", forHTTPHeaderField: "User-Agent")
            
            let (data, _) = try await session.data(from: url)
            let listing = try JSONDecoder().decode(RedditListing.self, from: data)
            
            let news = try await processNewsItems(listing.data.children, category: category)
            allNews.append(contentsOf: news)
            
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
        }
        
        return allNews.sorted { $0.publishedDate > $1.publishedDate }
    }
    
    private func processNewsItems(_ posts: [RedditPost], category: NewsItem.NewsCategory) async throws -> [NewsItem] {
        var newsItems: [NewsItem] = []
        
        for post in posts {
            let postData = post.data
            
            // Get the best available image URL
            let imageURL = getBestImageURL(from: postData)
            guard let finalImageURL = imageURL else { continue }
            
            // Only process posts that likely represent major news
            guard isMajorNews(title: postData.title, category: category) else { continue }
            
            // Fetch related memes for this category
            let memes = try await fetchMemesForCategory(category, limit: 4, keywords: getKeywords(from: postData.title))
            guard !memes.isEmpty else { continue } // Skip if no relevant memes found
            
            let newsItem = NewsItem(
                title: postData.title,
                summary: cleanupText(postData.selftext),
                imageURL: finalImageURL,
                category: category,
                publishedDate: Date(timeIntervalSince1970: postData.created_utc),
                relatedMemes: memes,
                redditURL: URL(string: "\(baseURL)\(postData.permalink)")!
            )
            
            newsItems.append(newsItem)
        }
        
        return newsItems
    }
    
    private func getBestImageURL(from postData: RedditPostData) -> URL? {
        if let preview = postData.preview?.images.first?.source.url {
            let decodedURL = preview.replacingOccurrences(of: "&amp;", with: "&")
            return URL(string: decodedURL)
        }
        if let url = postData.url, url.hasSuffix(".jpg") || url.hasSuffix(".png") {
            return URL(string: url)
        }
        return URL(string: postData.thumbnail ?? "")
    }
    
    private func isMajorNews(title: String, category: NewsItem.NewsCategory) -> Bool {
        let keywords: Set<String>
        switch category {
        case .sports:
            keywords = ["World Cup", "Final", "Semi-Final", "Champions Trophy", "India", "Pakistan", "Australia"]
        case .elonMusk:
            keywords = ["Launch", "Tesla", "SpaceX", "Starship", "Twitter", "X", "Cybertruck"]
        case .entertainment:
            keywords = ["Oscar", "Box Office", "Marvel", "Star Wars", "Record", "Award"]
        case .ads:
            keywords = ["Super Bowl", "Commercial", "Campaign", "Advertisement"]
        case .politics:
            keywords = ["Election", "President", "Prime Minister", "Crisis", "War", "Peace", "Treaty"]
        }
        
        let titleWords = Set(title.components(separatedBy: " "))
        return !keywords.intersection(titleWords).isEmpty
    }
    
    private func getKeywords(from title: String) -> [String] {
        return title.components(separatedBy: " ")
            .filter { $0.count > 3 }
            .prefix(3)
            .map { $0.lowercased() }
    }
    
    private func fetchMemesForCategory(_ category: NewsItem.NewsCategory, limit: Int, keywords: [String]) async throws -> [Meme] {
        guard let subreddits = memeSubreddits[category] else { return [] }
        
        var allMemes: [Meme] = []
        for subreddit in subreddits {
            let url = URL(string: "\(baseURL)/r/\(subreddit)/hot.json?limit=10")!
            var request = URLRequest(url: url)
            request.setValue("Meme News App/1.0", forHTTPHeaderField: "User-Agent")
            
            let (data, _) = try await session.data(from: url)
            let listing = try JSONDecoder().decode(RedditListing.self, from: data)
            
            let memes = listing.data.children.compactMap { post -> Meme? in
                guard let imageURL = getBestImageURL(from: post.data),
                      isRelevantMeme(title: post.data.title, keywords: keywords) else { return nil }
                
                return Meme(
                    imageURL: imageURL,
                    source: .reddit,
                    title: post.data.title,
                    redditURL: URL(string: "\(baseURL)\(post.data.permalink)")!
                )
            }
            
            allMemes.append(contentsOf: memes)
            if allMemes.count >= limit { break }
            
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        }
        
        return Array(allMemes.prefix(limit))
    }
    
    private func isRelevantMeme(title: String, keywords: [String]) -> Bool {
        let titleLower = title.lowercased()
        return keywords.contains { titleLower.contains($0) }
    }
    
    private func cleanupText(_ text: String) -> String {
        return text.isEmpty ? "Click to read more on Reddit..." : text
            .replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 