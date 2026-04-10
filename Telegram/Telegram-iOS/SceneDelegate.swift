import UIKit

@objc(TelegramSceneDelegate)
class TelegramSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        if let appDelegate = UIApplication.shared.delegate as? UIApplicationDelegate,
           let existingWindow = appDelegate.window ?? nil {
            existingWindow.windowScene = windowScene
            self.window = existingWindow
        }
    }
}
