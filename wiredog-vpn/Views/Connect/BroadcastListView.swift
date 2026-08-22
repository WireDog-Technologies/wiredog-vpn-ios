import SwiftUI
import UIKit

struct BroadcastListView: View {
    @ObservedObject var broadcastService: BroadcastService

    private var messages: [BroadcastMessage] {
        broadcastService.activeMessages()
    }

    var body: some View {
        NavigationView {
            ScrollView {
                if messages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 36))
                            .foregroundColor(.vpnTextSecondary)
                        Text("No announcements right now")
                            .font(.system(size: 15))
                            .foregroundColor(.vpnTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    VStack(spacing: 8) {
                        ForEach(messages) { message in
                            BroadcastRowView(
                                message: message,
                                isRead: broadcastService.readIds.contains(message.id),
                                onTap: { broadcastService.markRead([message.id]) },
                                onLongPress: { broadcastService.markUnread(message.id) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color.vpnBackground.ignoresSafeArea())
            .navigationTitle("Announcements")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BroadcastRowView: View {
    let message: BroadcastMessage
    let isRead: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    // A Button's own tap gesture still fires on the same finger-up that completes a
    // simultaneousGesture long press, which would instantly re-mark a just-unread message
    // as read. Suppress the tap briefly after a successful long press to prevent that.
    @State private var suppressTap = false

    private var severityColor: Color {
        switch message.severity {
        case .info: return .vpnPrimary
        case .maintenance: return .vpnYellow
        case .incident: return .vpnRed
        }
    }

    private var severityIcon: String {
        switch message.severity {
        case .info: return "info.circle.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .incident: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        Button(action: {
            guard !suppressTap else { return }
            onTap()
        }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: severityIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isRead ? .vpnTextTertiary : severityColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.title)
                        .font(.system(size: 15, weight: isRead ? .regular : .bold))
                        .foregroundColor(isRead ? .vpnTextSecondary : .vpnTextPrimary)

                    Text(message.body)
                        .font(.system(size: 13))
                        .foregroundColor(.vpnTextSecondary)

                    Text(message.startAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundColor(.vpnTextTertiary)
                }

                Spacer()

                if !isRead {
                    Circle()
                        .fill(Color.vpnRed)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(12)
            .background(isRead ? Color.vpnCardBackground : severityColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isRead ? Color.clear : severityColor.opacity(0.5), lineWidth: 1)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                guard isRead else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onLongPress()
                suppressTap = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    suppressTap = false
                }
            }
        )
        .animation(.easeInOut(duration: 0.25), value: isRead)
    }
}
