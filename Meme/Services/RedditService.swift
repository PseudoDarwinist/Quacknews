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
        "sports+Cricket": NewsItem.NewsCategory.sports,        // Combined sports news
        "spacex+tesla": NewsItem.NewsCategory.elonMusk,      // Elon/Tesla/SpaceX news
        "movies+television": NewsItem.NewsCategory.entertainment,  // Entertainment news
        "advertising": NewsItem.NewsCategory.ads,        // Ad industry news
        "worldnews+news": NewsItem.NewsCategory.politics    // World politics
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
        logger.info("Starting to fetch news from Reddit")
        var allNews: [NewsItem] = []
        var lastError: Error?
        
        for (subreddit, category) in newsSubreddits {
            logger.debug("Fetching from subreddit: \(subreddit) for category: \(category.rawValue)")
            
            do {
                // URL encode the subreddit string
                let encodedSubreddit = subreddit.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? subreddit
                let url = URL(string: "\(baseURL)/r/\(encodedSubreddit)/hot.json?limit=3")!
                
                var request = URLRequest(url: url)
                request.setValue("QuackNews/1.0", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 30
                
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    logger.debug("Response status code: \(httpResponse.statusCode) for \(subreddit)")
                    
                    guard (200...299).contains(httpResponse.statusCode) else {
                        logger.error("HTTP error \(httpResponse.statusCode) for \(subreddit)")
                        continue
                    }
                }
                
                let listing = try JSONDecoder().decode(RedditListing.self, from: data)
                logger.debug("Successfully decoded \(listing.data.children.count) posts from \(subreddit)")
                
                if let news = try? await processNewsItems(listing.data.children, category: category) {
                    allNews.append(contentsOf: news)
                    logger.debug("Processed \(news.count) news items from \(subreddit)")
                }
            } catch {
                logger.error("Error fetching from \(subreddit): \(error.localizedDescription)")
                lastError = error
                continue // Skip this subreddit but continue with others
            }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        logger.info("Completed news fetch with \(allNews.count) total items")
        
        // Only throw if we have no news items at all
        if allNews.isEmpty, let error = lastError {
            throw error
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
        // Convert title to lowercase for case-insensitive matching
        let titleLower = title.lowercased()
        
        let keywords: Set<String>
        switch category {
        case .sports:
            keywords = ["match", "win", "final", "series", "cup", "tournament", "champion", "record", "victory", "team", "score", "india", "pakistan", "australia", "england"]
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
        
        var allMemes: [Meme] = []
        var errors: [Error] = []
        
        for subreddit in subreddits {
            do {
                let encodedSubreddit = subreddit.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? subreddit
                let url = URL(string: "\(baseURL)/r/\(encodedSubreddit)/hot.json?limit=10")!
                
                var request = URLRequest(url: url)
                request.setValue("QuackNews/1.0", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 30
                
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    guard (200...299).contains(httpResponse.statusCode) else {
                        logger.error("HTTP error \(httpResponse.statusCode) for meme subreddit \(subreddit)")
                        continue
                    }
                }
                
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
                
            } catch {
                logger.error("Error fetching memes from \(subreddit): \(error.localizedDescription)")
                errors.append(error)
                continue // Skip this subreddit but continue with others
            }
            
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        // Return whatever memes we found, even if some failed
        return Array(allMemes.prefix(limit))
    }
    
    private func isRelevantMeme(title: String, keywords: [String]) -> Bool {
        let titleLower = title.lowercased()
        return keywords.contains { titleLower.contains($0) }
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