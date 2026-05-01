import SwiftUI

struct TestView: View {
    var body: some View {
        HStack {
            Button(action: {}) {
                Image(systemName: "star")
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(Color.red, in: Circle())
            
            Spacer()
        }
        .frame(width: 300, height: 100)
    }
}
