import Foundation
import Combine

@MainActor
final class PlayerProgressTracker: ObservableObject {
    @Published var progress: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    static let shared = PlayerProgressTracker()
    
    private init() {}
    
    func update(progress: TimeInterval, duration: TimeInterval) {
        if self.progress != progress {
            self.progress = progress
        }
        if self.duration != duration {
            self.duration = duration
        }
    }
}
