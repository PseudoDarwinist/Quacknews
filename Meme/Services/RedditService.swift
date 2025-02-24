import Foundation
import OSLog

private let logger = Logger(subsystem: "com.quacknews.app", category: "RedditService")

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
    let over_18: Bool
    let is_video: Bool
    let post_hint: String?
    
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
        "Cricket+CricketBanter+sports": NewsItem.NewsCategory.sports,  // Prioritize cricket news
        "spacex+tesla": NewsItem.NewsCategory.elonMusk,      // Elon/Tesla/SpaceX news
        "movies+television": NewsItem.NewsCategory.entertainment,  // Entertainment news
        "advertising": NewsItem.NewsCategory.ads,        // Ad industry news
        "worldnews+news": NewsItem.NewsCategory.politics    // World politics
    ]
    
    // Meme subreddits with high engagement
    private let memeSubreddits = [
        NewsItem.NewsCategory.sports: [
            "CricketShitpost",         // Primary cricket memes
            "cricketitaly",            // More cricket memes
            "CricketMemes",            // Additional cricket memes
            "sportsshitpost"           // General sports memes as backup
        ],
        NewsItem.NewsCategory.elonMusk: ["SpaceXMasterrace", "elonmemes"],
        NewsItem.NewsCategory.entertainment: ["moviememes", "PrequelMemes"],
        NewsItem.NewsCategory.ads: ["CommercialMemes", "SuperbOwl"],
        NewsItem.NewsCategory.politics: ["PoliticalMemes", "worldpoliticsmemes"]
    ]
    
    func fetchNews() async throws -> [NewsItem] {
        // Only log start of major operations
        logger.info("Fetching news from Reddit")
        var allNews: [NewsItem] = []
        var lastError: Error?
        
        // Create async tasks for parallel fetching
        async let newsTaskResults = withThrowingTaskGroup(of: [NewsItem].self) { group in
            for (subreddit, category) in newsSubreddits {
                group.addTask {
                    do {
                        let encodedSubreddit = subreddit.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? subreddit
                        let url = URL(string: "\(self.baseURL)/r/\(encodedSubreddit)/hot.json?limit=3")!
                        
                        var request = URLRequest(url: url)
                        request.setValue("QuackNews/1.0", forHTTPHeaderField: "User-Agent")
                        request.timeoutInterval = 30
                        
                        let (data, response) = try await self.session.data(for: request)
                        
                        if let httpResponse = response as? HTTPURLResponse,
                           !(200...299).contains(httpResponse.statusCode) {
                            logger.error("HTTP \(httpResponse.statusCode) for \(subreddit)")
                            return []
                        }
                        
                        let listing = try JSONDecoder().decode(RedditListing.self, from: data)
                        return try await self.processNewsItems(listing.data.children, category: category)
                    } catch {
                        logger.error("Failed fetching \(subreddit): \(error.localizedDescription)")
                        return []
                    }
                }
                
                // Add small delay between task creation to avoid rate limits
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            }
            
            var results: [NewsItem] = []
            for try await items in group {
                results.append(contentsOf: items)
            }
            return results
        }
        
        // Await all results
        allNews = try await newsTaskResults
        
        logger.info("Completed news fetch with \(allNews.count) items")
        
        if allNews.isEmpty {
            throw NSError(domain: "RedditService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No news items found"])
        }
        
        return allNews.sorted { $0.publishedDate > $1.publishedDate }
    }
    
    private func processNewsItems(_ posts: [RedditPost], category: NewsItem.NewsCategory) async throws -> [NewsItem] {
        var newsItems: [NewsItem] = []
        
        for post in posts {
            let postData = post.data
            logger.debug("Processing post: \(postData.title)")
            
            // Get the best available image URL
            let imageURL = getBestImageURL(from: postData)
            guard let finalImageURL = imageURL else {
                logger.debug("Skipping post - no valid image URL found")
                continue
            }
            
            // Only process posts that likely represent major news
            guard isMajorNews(title: postData.title, category: category) else {
                logger.debug("Skipping post - not considered major news")
                continue
            }
            
            // Fetch related memes for this category
            logger.debug("Fetching memes for post: \(postData.title)")
            let memes = try await fetchMemesForCategory(category, limit: 4, keywords: getKeywords(from: postData.title))
            
            guard !memes.isEmpty else {
                logger.debug("Skipping post - no related memes found")
                continue
            }
            
            let redditURL = URL(string: "\(baseURL)\(postData.permalink)")!
            logger.debug("Created Reddit URL: \(redditURL)")
            
            let newsItem = NewsItem(
                title: postData.title,
                summary: cleanupText(postData.selftext),
                imageURL: finalImageURL,
                category: category,
                publishedDate: Date(timeIntervalSince1970: postData.created_utc),
                relatedMemes: memes,
                redditURL: redditURL
            )
            
            newsItems.append(newsItem)
            logger.debug("Successfully added news item")
        }
        
        return newsItems
    }
    
    private func getBestImageURL(from postData: RedditPostData) -> URL? {
        if let preview = postData.preview?.images.first?.source.url {
            let decodedURL = preview.replacingOccurrences(of: "&amp;", with: "&")
            logger.debug("Using preview image URL: \(decodedURL)")
            return URL(string: decodedURL)
        }
        if let url = postData.url, url.hasSuffix(".jpg") || url.hasSuffix(".png") {
            logger.debug("Using direct image URL: \(url)")
            return URL(string: url)
        }
        logger.debug("Falling back to thumbnail URL: \(postData.thumbnail ?? "nil")")
        return URL(string: postData.thumbnail ?? "")
    }
    
    private func isMajorNews(title: String, category: NewsItem.NewsCategory) -> Bool {
        let titleLower = title.lowercased()
        
        let keywords: Set<String>
        switch category {
        case .sports:
            keywords = [
                // Cricket-specific keywords
                "icc", "champions trophy", "world cup", "t20", "odi", "test match",
                "india", "pakistan", "australia", "england",
                "kohli", "babar", "rohit", "gill", "siraj",
                "wicket", "century", "batting", "bowling",
                // General cricket terms
                "cricket", "match", "series", "tournament",
                "runs", "score", "innings", "partnership",
                // Match outcomes
                "win", "defeat", "victory", "lost", "beat",
                // Rivalry terms
                "rivalry", "clash", "versus", "vs",
                // General sports terms as fallback
                "champion", "record", "team"
            ]
        case .elonMusk:
            keywords = ["launch", "tesla", "spacex", "starship", "twitter", "x", "cybertruck", "musk", "rocket", "mars", "satellite", "starlink"]
        case .entertainment:
            keywords = ["oscar", "box office", "marvel", "star wars", "record", "award", "movie", "film", "premiere", "director", "actor", "release"]
        case .ads:
            keywords = ["super bowl", "commercial", "campaign", "advertisement", "marketing", "brand", "viral", "agency", "creative"]
        case .politics:
            keywords = ["election", "president", "minister", "crisis", "war", "peace", "treaty", "vote", "government", "leader", "congress", "parliament"]
        }
        
        // Check if any keyword is present in the title
        return keywords.contains { keyword in
            titleLower.contains(keyword.lowercased())
        }
    }
    
    private func getKeywords(from title: String) -> [String] {
        return title.components(separatedBy: " ")
            .filter { $0.count > 3 }
            .prefix(3)
            .map { $0.lowercased() }
    }
    
    private func fetchMemesForCategory(_ category: NewsItem.NewsCategory, limit: Int, keywords: [String]) async throws -> [Meme] {
        guard let subreddits = memeSubreddits[category] else { return [] }
        
        // Fetch memes in parallel
        async let memesResults = withThrowingTaskGroup(of: [Meme].self) { group in
            for subreddit in subreddits {
                group.addTask {
                    do {
                        let encodedSubreddit = subreddit.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? subreddit
                        let url = URL(string: "\(self.baseURL)/r/\(encodedSubreddit)/hot.json?limit=10")!
                        
                        var request = URLRequest(url: url)
                        request.setValue("QuackNews/1.0", forHTTPHeaderField: "User-Agent")
                        request.timeoutInterval = 30
                        
                        let (data, response) = try await self.session.data(for: request)
                        
                        if let httpResponse = response as? HTTPURLResponse,
                           !(200...299).contains(httpResponse.statusCode) {
                            return []
                        }
                        
                        let listing = try JSONDecoder().decode(RedditListing.self, from: data)
                        
                        return listing.data.children.compactMap { post -> Meme? in
                            let postData = post.data
                            
                            // Skip NSFW, videos, and non-image content
                            guard !postData.over_18,
                                  !postData.is_video,
                                  postData.post_hint == "image",
                                  let imageURL = self.getBestImageURL(from: postData),
                                  self.isRelevantMeme(title: postData.title, keywords: keywords) else { 
                                return nil 
                            }
                            
                            return Meme(
                                imageURL: imageURL,
                                source: .reddit,
                                title: postData.title,
                                redditURL: URL(string: "\(self.baseURL)\(postData.permalink)")!
                            )
                        }
                    } catch {
                        return []
                    }
                }
                
                // Small delay between task creation
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 second delay
            }
            
            var results: [Meme] = []
            for try await memes in group {
                results.append(contentsOf: memes)
                if results.count >= limit { break }
            }
            return Array(results.prefix(limit))
        }
        
        return try await memesResults
    }
    
    private func isRelevantMeme(title: String, keywords: [String]) -> Bool {
        let titleLower = title.lowercased()
        
        // For cricket/sports memes, also check for common cricket-related terms
        let cricketTerms = ["india", "pakistan", "cricket", "icc", "match", "kohli", "babar"]
        
        return keywords.contains { titleLower.contains($0) } ||
               (titleLower.contains("cricket") && cricketTerms.contains { titleLower.contains($0) })
    }
    
    private func cleanupText(_ text: String) -> String {
        if text.isEmpty {
            return "Click to read more on Reddit..."
        }
        
        // Limit summary length to 250 characters
        let cleanText = text
            .replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanText.count > 250 {
            return String(cleanText.prefix(247)) + "..."
        }
        return cleanText
    }
} 