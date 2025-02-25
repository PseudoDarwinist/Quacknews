import SwiftUI

struct CreateNewsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    @State private var category = NewsCategory.sports
    @State private var selectedImage: UIImage?
    @State private var imageURL: String?
    @State private var isImagePickerPresented = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section("News Details") {
                    TextField("Title", text: $title)
                    TextEditor(text: $summary)
                        .frame(height: 100)
                    
                    Picker("Category", selection: $category) {
                        ForEach(NewsCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                }
                
                Section("Image") {
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                    }
                    
                    Button(action: {
                        isImagePickerPresented = true
                    }) {
                        Label("Select Image", systemImage: "photo.fill")
                    }
                    
                    if let imageURL {
                        Text("Image URL: \(imageURL)")
                            .font(.caption)
                    }
                }
                
                if isUploading {
                    ProgressView("Saving...")
                }
                
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
                
                Button(action: {
                    Task {
                        await saveNews()
                    }
                }) {
                    Text("Save News")
                }
                .disabled(title.isEmpty || summary.isEmpty || selectedImage == nil || isUploading)
            }
            .navigationTitle("Create News")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isImagePickerPresented) {
                ImagePicker(image: $selectedImage)
            }
        }
    }
    
    private func saveNews() async {
        isUploading = true
        defer { isUploading = false }
        
        do {
            guard let image = selectedImage else { return }
            let imageURL = try await FirebaseManager.shared.uploadImage(image, path: "news")
            try await FirebaseManager.shared.createNews(
                title: title,
                summary: summary,
                imageURL: imageURL,
                category: category.rawValue
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
} 