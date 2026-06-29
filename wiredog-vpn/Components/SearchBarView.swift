import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.vpnTextSecondary)

            TextField("Enter locations", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(.vpnTextPrimary)

            Spacer()

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.vpnTextSecondary)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(12)
        .background(Color.vpnCardBackground)
        .cornerRadius(8)
    }
}

#Preview {
    VStack(spacing: 16) {
        SearchBarView(searchText: .constant(""))
        SearchBarView(searchText: .constant("nether"))
    }
    .padding()
    .background(Color.vpnBackground)
}
