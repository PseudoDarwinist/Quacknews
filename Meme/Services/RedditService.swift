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
        "Cricket+CricketBanter+sports+IndianCricketTeam+PakCricket": NewsItem.NewsCategory.sports,  // Expanded cricket sources
        "spacex+tesla+elonmusk+teslainvestorsclub+SpaceXLounge": NewsItem.NewsCategory.elonMusk,      // More Elon/Tesla/SpaceX sources
        "movies+television+bollywood+BollywoodGossip+entertainment": NewsItem.NewsCategory.entertainment,  // Added Bollywood
        "advertising+adporn+socialmedia+DigitalMarketing": NewsItem.NewsCategory.ads,        // Expanded ad industry
        "worldnews+news+politics+IndiaNews+PakistanNews": NewsItem.NewsCategory.politics    // Added regional news
    ]
    
    // Meme subreddits with high engagement
    private let memeSubreddits = [
        NewsItem.NewsCategory.sports: [
            "CricketShitpost",         // Primary cricket memes
            "cricketitaly",            // More cricket memes
            "CricketMemes",            // Additional cricket memes
            "sportsshitpost",          // General sports memes
            "sportsmemes",             // More sports humor
            "cricketfunny"             // Cricket humor
        ],
        NewsItem.NewsCategory.elonMusk: [
            "SpaceXMasterrace", 
            "elonmemes", 
            "EnoughMuskSpam",          // Critical memes about Elon
            "wallstreetbets"           // Often has Tesla/Elon memes
        ],
        NewsItem.NewsCategory.entertainment: [
            "moviememes", 
            "PrequelMemes", 
            "BollywoodMemes",          // Bollywood specific memes
            "bollywoodrealism",        // Funny Bollywood scenes
            "DankIndianMemes",         // Indian entertainment memes
            "terriblefacebookmemes"    // So bad they're good
        ],
        NewsItem.NewsCategory.ads: [
            "CommercialMemes", 
            "SuperbOwl",               // Super Bowl ads
            "FellowKids",              // Cringy ad attempts
            "CorporateFacepalm"        // Bad corporate messaging
        ],
        NewsItem.NewsCategory.politics: [
            "PoliticalMemes", 
            "worldpoliticsmemes",
            "IndianDankMemes",         // Indian political memes
            "PoliticalHumor",          // US-focused political humor
            "PropagandaPosters"        // Historical and modern propaganda
        ]
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
                // Cricket-specific controversial/trending keywords
                "controversy", "dispute", "argument", "fight", "clash", "tension",
                "rivalry", "india vs pakistan", "ashes", "sledging", "cheating",
                "drs", "umpire decision", "icc", "champions trophy", "world cup",
                // Player controversies
                "kohli", "babar", "dhoni", "warner", "smith", "stokes",
                // Match drama
                "last ball", "thriller", "upset", "underdog", "comeback",
                "record", "historic", "banned", "suspended", "fined",
                // General cricket terms with controversy potential
                "cricket", "match fixing", "betting", "scandal", "allegations"
            ]
        case .elonMusk:
            keywords = [
                "controversy", "twitter", "x", "takeover", "fired", "lawsuit",
                "tesla crash", "autopilot", "stock", "plunge", "surge", 
                "spacex explosion", "starship", "mars", "neuralink", "brain chip",
                "ai", "artificial intelligence", "warning", "threat", "doge", 
                "cryptocurrency", "sec", "investigation", "boring company",
                "hyperloop", "failed", "delayed", "promise", "delivery"
            ]
        case .entertainment:
            keywords = [
                "controversy", "scandal", "divorce", "affair", "leaked", "backlash",
                "criticized", "box office bomb", "flop", "disaster", "oscar snub",
                "racist", "sexist", "inappropriate", "canceled", "recast",
                "remake", "reboot", "sequel", "prequel", "franchise",
                "marvel", "dc", "disney", "netflix", "streaming war",
                "record breaking", "highest grossing", "banned", "censored",
                "bollywood", "hollywood", "viral", "trending"
            ]
        case .ads:
            keywords = [
                "controversy", "offensive", "backlash", "pulled", "banned",
                "super bowl", "viral", "campaign", "backfired", "tone deaf",
                "insensitive", "boycott", "protest", "criticism", "apology",
                "expensive", "record", "celebrity", "endorsement", "dropped",
                "social media", "reaction", "trending", "meme", "parody"
            ]
        case .politics:
            keywords = [
                "controversy", "scandal", "corruption", "protest", "riot",
                "election", "fraud", "vote", "democracy", "authoritarian",
                "dictator", "president", "prime minister", "resign", "impeach",
                "investigation", "leaked", "documents", "classified", "secret",
                "war", "conflict", "tension", "sanctions", "nuclear",
                "climate", "crisis", "emergency", "disaster", "policy",
                "supreme court", "ruling", "overturned", "constitutional",
                "rights", "freedom", "censorship", "banned", "illegal"
            ]
        }
        
        // Check if any keyword is present in the title
        for keyword in keywords {
            if titleLower.contains(keyword.lowercased()) {
                return true
            }
        }
        
        // Additional check for trending indicators
        let trendingIndicators = ["breaking", "just in", "trending", "viral", "exclusive", "shocking", "controversial"]
        for indicator in trendingIndicators {
            if titleLower.contains(indicator) {
                return true
            }
        }
        
        return false
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
        
        // Check for humor indicators in the title
        let humorIndicators = [
            "funny", "hilarious", "lol", "rofl", "lmao", "meme", "joke", 
            "humor", "comedy", "parody", "satire", "troll", "epic fail",
            "when you", "that moment when", "be like", "meanwhile", "plot twist"
        ]
        
        // Category-specific humor terms
        let cricketHumor = [
            "india", "pakistan", "cricket", "icc", "match", "kohli", "babar",
            "dhoni", "rohit", "wicket", "bowled", "run out", "catch", "dropped",
            "rain", "drs", "umpire", "review", "sledging", "celebration"
        ]
        
        let elonHumor = [
            "elon", "musk", "tesla", "spacex", "twitter", "x", "doge", 
            "mars", "rocket", "cybertruck", "neuralink", "boring"
        ]
        
        let entertainmentHumor = [
            "movie", "actor", "actress", "director", "hollywood", "bollywood",
            "oscar", "award", "red carpet", "celebrity", "star", "flop", "hit",
            "marvel", "dc", "disney", "netflix", "amazon", "streaming"
        ]
        
        // Check if title contains any humor indicators
        let hasHumorIndicator = humorIndicators.contains { titleLower.contains($0) }
        
        // Check if title contains any of the original keywords
        let hasKeyword = keywords.contains { keyword in 
            titleLower.contains(keyword.lowercased())
        }
        
        // Check for category-specific humor terms
        let hasCricketHumor = titleLower.contains("cricket") && cricketHumor.contains { titleLower.contains($0) }
        let hasElonHumor = (titleLower.contains("elon") || titleLower.contains("musk")) && elonHumor.contains { titleLower.contains($0) }
        let hasEntertainmentHumor = (titleLower.contains("movie") || titleLower.contains("film")) && entertainmentHumor.contains { titleLower.contains($0) }
        
        // Prioritize memes that have both humor indicators and relevant keywords
        return (hasHumorIndicator && hasKeyword) || 
               hasCricketHumor || 
               hasElonHumor || 
               hasEntertainmentHumor ||
               hasKeyword
    }
    
    private func cleanupText(_ text: String) -> String {
        if text.isEmpty {
            return "Tap to read more..."
        }
        
        // Start with the original text
        var cleanText = text
        
        // Remove markdown links [text](url)
        cleanText = cleanText.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        
        // Remove URLs
        cleanText = cleanText.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        
        // Remove Reddit formatting artifacts
        cleanText = cleanText.replacingOccurrences(of: "&amp;", with: "&")
        cleanText = cleanText.replacingOccurrences(of: "&lt;", with: "<")
        cleanText = cleanText.replacingOccurrences(of: "&gt;", with: ">")
        cleanText = cleanText.replacingOccurrences(of: "&nbsp;", with: " ")
        
        // Remove markdown headers (# Header)
        cleanText = cleanText.replacingOccurrences(of: #"^#+\s+"#, with: "", options: .regularExpression)
        cleanText = cleanText.replacingOccurrences(of: #"\n#+\s+"#, with: " ", options: .regularExpression)
        
        // Remove markdown bold/italic
        cleanText = cleanText.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        cleanText = cleanText.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
        cleanText = cleanText.replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
        cleanText = cleanText.replacingOccurrences(of: #"_([^_]+)_"#, with: "$1", options: .regularExpression)
        
        // Remove markdown quotes
        cleanText = cleanText.replacingOccurrences(of: #"^>\s+"#, with: "", options: .regularExpression)
        cleanText = cleanText.replacingOccurrences(of: #"\n>\s+"#, with: " ", options: .regularExpression)
        
        // Remove markdown lists
        cleanText = cleanText.replacingOccurrences(of: #"\n\s*[-*+]\s+"#, with: " ", options: .regularExpression)
        cleanText = cleanText.replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
        
        // Remove numbered lists
        cleanText = cleanText.replacingOccurrences(of: #"\n\s*\d+\.\s+"#, with: " ", options: .regularExpression)
        cleanText = cleanText.replacingOccurrences(of: #"^\s*\d+\.\s+"#, with: "", options: .regularExpression)
        
        // Remove code blocks
        cleanText = cleanText.replacingOccurrences(of: #"```[^`]*```"#, with: "", options: .regularExpression)
        cleanText = cleanText.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        
        // Remove multiple newlines and replace with a single space
        cleanText = cleanText.replacingOccurrences(of: #"\n+"#, with: " ", options: .regularExpression)
        
        // Remove multiple spaces
        cleanText = cleanText.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        
        // Remove leading/trailing whitespace
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If text is still too long, create a more engaging summary
        if cleanText.count > 150 {
            // Try to find a good breakpoint (end of sentence or phrase)
            let possibleBreakpoints = [". ", "! ", "? ", "; ", ": "]
            var bestBreakpoint = 150
            
            for breakpoint in possibleBreakpoints {
                if let range = cleanText.range(of: breakpoint, options: [], range: cleanText.startIndex..<cleanText.index(cleanText.startIndex, offsetBy: min(200, cleanText.count))), 
                   range.upperBound.utf16Offset(in: cleanText) > 100 && range.upperBound.utf16Offset(in: cleanText) < 200 {
                    bestBreakpoint = range.upperBound.utf16Offset(in: cleanText)
                    break
                }
            }
            
            let endIndex = cleanText.index(cleanText.startIndex, offsetBy: min(bestBreakpoint, cleanText.count))
            return String(cleanText[..<endIndex])
        }
        
        return cleanText
    }
} 