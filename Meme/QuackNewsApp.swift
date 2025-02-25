import SwiftUI
import FirebaseCore

// Make AppDelegate conform to ObservableObject
class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct QuackNewsApp: App {
    // Use UIApplicationDelegateAdapterWithSpaces
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        WindowGroup {
            HomeFeedView()
        }
    }
} 