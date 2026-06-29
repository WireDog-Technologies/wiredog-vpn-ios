import SwiftUI

enum LogType {
    case application
    case service

    var title: String {
        switch self {
        case .application: return "Application Logs"
        case .service: return "Service Logs"
        }
    }
}

struct LogViewerView: View {
    let logType: LogType
    @State private var logContent: String = "Loading..."
    @State private var showCopiedFeedback = false
    @State private var showShareSheet = false
    @Environment(\.presentationMode) var presentationMode

    private let logService = LogService.shared
    private let terminalBackground = Color(red: 0.039, green: 0.055, blue: 0.078) // #0A0E14

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                        }
                        .foregroundColor(.vpnPrimary)
                    }

                    Spacer()

                    // Action buttons
                    HStack(spacing: 16) {
                        Button(action: {
                            copyLogs()
                            showCopiedFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopiedFeedback = false
                            }
                        }) {
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(showCopiedFeedback ? .vpnGreen : .vpnPrimary)
                        }
                        .padding(8)

                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .foregroundColor(.vpnPrimary)
                        }
                        .padding(8)

                        Button(action: refreshLogs) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16))
                                .foregroundColor(.vpnPrimary)
                        }
                        .padding(8)
                    }
                }
                .padding(16)

                Text(logType.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // Terminal-style log display
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logContent.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { index, line in
                                Text(String(line))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(colorForLogLevel(String(line)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            // Invisible anchor for auto-scroll
                            Color.clear
                                .frame(height: 1)
                                .id("logBottom")
                        }
                        .padding(12)
                    }
                    .background(terminalBackground)
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .onChange(of: logContent) { _ in
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }

                Spacer(minLength: 16)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            refreshLogs()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [logContent])
        }
    }

    private func refreshLogs() {
        switch logType {
        case .application:
            logContent = logService.readAppLogs()
        case .service:
            logContent = logService.readServiceLogs()
        }
    }

    private func copyLogs() {
        UIPasteboard.general.string = logContent
    }

    private func colorForLogLevel(_ line: String) -> Color {
        if line.contains("[ERROR]") {
            return .vpnRedMedium
        } else if line.contains("[WARNING]") {
            return .vpnYellow
        } else if line.contains("[DEBUG]") {
            return .vpnTextSecondary
        }
        return .vpnTextPrimary
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
