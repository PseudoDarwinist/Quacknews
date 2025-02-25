import SwiftUI
import PhotosUI
import OSLog

private let logger = Logger(subsystem: "com.quacknews.app", category: "AdminUploadView")

struct AdminUploadView: View {
    enum UploadType: String, CaseIterable {
        case news = "News"
        case meme = "Meme"
    }
    
    @State private var selectedUploadType: UploadType = .news
    @State private var title = ""
    @State private var summary = ""
    @State private var selectedCategory = NewsItem.NewsCategory.sports
    @State private var selectedImage: UIImage?
    @State private var isImagePickerPresented = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var existingNewsItems: [NewsItem] = []
    @State private var selectedNewsItem: NewsItem?
    @State private var isLoadingNews = false
    
    // Use the exact category names from the enum
    private let categories = NewsItem.NewsCategory.allCases.map { $0.rawValue }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector at the top
                Picker("Upload Type", selection: $selectedUploadType) {
                    ForEach(UploadType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                Form {
                    if selectedUploadType == .news {
                        // NEWS UPLOAD FORM
                        Section("Create News") {
                            TextField("Title", text: $title)
                            
                            TextEditor(text: $summary)
                                .frame(height: 100)
                            
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(NewsItem.NewsCategory.allCases, id: \.self) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            
                            Button("Select Image") {
                                isImagePickerPresented = true
                            }
                            
                            if let selectedImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 200)
                            }
                            
                            if isUploading {
                                ProgressView("Uploading...")
                            }
                            
                            if let errorMessage {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                            }
                            
                            if let successMessage {
                                Text(successMessage)
                                    .foregroundColor(.green)
                            }
                            
                            Button("Create News") {
                                Task {
                                    await createNews()
                                }
                            }
                            .disabled(title.isEmpty || summary.isEmpty || selectedImage == nil || isUploading)
                        }
                    } else {
                        // MEME UPLOAD FORM
                        Section("Create Meme") {
                            TextField("Title (Optional)", text: $title)
                            
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(NewsItem.NewsCategory.allCases, id: \.self) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            .onChange(of: selectedCategory) { _ in
                                if selectedUploadType == .meme {
                                    loadNewsForCategory()
                                }
                            }
                            
                            if isLoadingNews {
                                ProgressView("Loading news items...")
                            } else if !existingNewsItems.isEmpty {
                                let filteredCount = filteredNewsItems.count
                                Text("This meme will be added to \(filteredCount) \(selectedCategory.rawValue) news items")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No \(selectedCategory.rawValue) news items found. Upload a news item first.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Button("Select Image") {
                                isImagePickerPresented = true
                            }
                            
                            if let selectedImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 200)
                            }
                            
                            if isUploading {
                                ProgressView("Uploading...")
                            }
                            
                            if let errorMessage {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                            }
                            
                            if let successMessage {
                                Text(successMessage)
                                    .foregroundColor(.green)
                            }
                            
                            Button("Upload Meme") {
                                Task {
                                    await uploadMeme()
                                }
                            }
                            .disabled(selectedImage == nil || isUploading)
                        }
                    }
                    
                    Section("Debug Info") {
                        Text("Selected category: \(selectedCategory.rawValue)")
                        
                        Button("List All Categories") {
                            logger.debug("Available categories: \(categories.joined(separator: ", "))")
                            
                            // Also log the enum cases directly
                            let enumCases = NewsItem.NewsCategory.allCases.map { $0.rawValue }
                            logger.debug("Enum cases: \(enumCases.joined(separator: ", "))")
                        }
                    }
                }
            }
            .navigationTitle("Admin")
            .sheet(isPresented: $isImagePickerPresented) {
                ImagePicker(image: $selectedImage)
            }
            .onAppear {
                if selectedUploadType == .meme {
                    loadNewsForCategory()
                }
            }
            .onChange(of: selectedUploadType) { _ in
                // Clear form when switching tabs
                title = ""
                summary = ""
                errorMessage = nil
                successMessage = nil
                
                if selectedUploadType == .meme {
                    loadNewsForCategory()
                }
            }
        }
    }
    
    private var filteredNewsItems: [NewsItem] {
        existingNewsItems.filter { $0.category == selectedCategory }
    }
    
    private func loadNewsForCategory() {
        Task {
            isLoadingNews = true
            do {
                existingNewsItems = try await FirebaseManager.shared.fetchNews()
            } catch {
                logger.error("Failed to load news items: \(error.localizedDescription)")
                errorMessage = "Failed to load news items: \(error.localizedDescription)"
            }
            isLoadingNews = false
        }
    }
    
    private func createNews() async {
        isUploading = true
        errorMessage = nil
        successMessage = nil
        
        do {
            guard let image = selectedImage else { return }
            
            logger.info("Creating news with title: \(title), category: \(selectedCategory.rawValue)")
            
            // Upload image
            let imageURL = try await FirebaseManager.shared.uploadImage(image, path: "news")
            
            // Create news with meme
            try await FirebaseManager.shared.createNews(
                title: title,
                summary: summary,
                imageURL: imageURL,
                category: selectedCategory.rawValue
            )
            
            // Reset form
            title = ""
            summary = ""
            selectedImage = nil
            successMessage = "News created successfully!"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            logger.error("Failed to create news: \(error.localizedDescription)")
        }
        
        isUploading = false
    }
    
    private func uploadMeme() async {
        isUploading = true
        errorMessage = nil
        successMessage = nil
        
        do {
            guard let image = selectedImage else { return }
            
            logger.info("Creating meme for category: \(selectedCategory.rawValue)")
            
            // Upload image
            let imageURL = try await FirebaseManager.shared.uploadImage(image, path: "memes")
            
            // Create meme and associate with news items
            try await FirebaseManager.shared.createMeme(
                title: title.isEmpty ? nil : title,
                imageURL: imageURL,
                category: selectedCategory.rawValue
            )
            
            // Reset form
            title = ""
            selectedImage = nil
            successMessage = "Meme uploaded and associated with \(selectedCategory.rawValue) news items!"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            logger.error("Failed to upload meme: \(error.localizedDescription)")
        }
        
        isUploading = false
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
} 
