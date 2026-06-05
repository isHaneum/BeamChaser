import SwiftUI
struct TestAlignment: View {
    var body: some View {
        VStack {
            Text("0.00")
                .font(.system(size: 88, weight: .bold, design: .monospaced))
                .overlay(alignment: .lastTextBaseline) {
                    // Try to attach it
                }
        }
    }
}
