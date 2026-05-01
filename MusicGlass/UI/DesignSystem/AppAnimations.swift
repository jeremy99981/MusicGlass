import SwiftUI

enum AppAnimations {
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let quick = Animation.spring(response: 0.24, dampingFraction: 0.9)
}
