import SwiftUI

@main
struct PS3QDDApp: App {
    @StateObject private var model = DecryptQueue()

    init() {
        // Headless batch use: PS3QDD --decrypt <input.iso> <keys> <output-dir>.
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--decrypt" {
            exit(CLI.run(arguments: arguments))
        }
    }

    var body: some Scene {
        WindowGroup("PS3 Quick Disc Decryptor") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentMinSize)
    }
}
