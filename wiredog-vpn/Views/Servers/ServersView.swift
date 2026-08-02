import SwiftUI

// Identifiable wrapper used for .sheet(item:) presentation
private struct SheetGroup: Identifiable {
    let id: String // state name
    let servers: [Server]
}

struct ServersView: View {
    @ObservedObject var vpnManager: VPNManager
    @State private var searchText = ""
    @State private var mapHeight: CGFloat = 0
    @State private var sheetHeight: CGFloat = 0
    @State private var expandedState: String? = nil
    @State private var sheetGroup: SheetGroup? = nil

    private static let bottomGradientHeight: CGFloat = 100
    private static let topMapPadding: CGFloat = 60

    var filteredServers: [Server] {
        if searchText.isEmpty {
            return vpnManager.availableServers
        }
        return vpnManager.availableServers.filter {
            $0.countryName.localizedCaseInsensitiveContains(searchText) ||
            ($0.city?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            $0.countryCode.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Servers grouped by state. Favorites groups first, then alphabetical.
    /// Within each group, servers sorted by city then id (matching Android).
    var groupedServers: [(state: String, servers: [Server])] {
        let grouped = Dictionary(grouping: filteredServers) { $0.countryName }
        return grouped
            .map { key, values -> (state: String, servers: [Server]) in
                let sorted = values.sorted {
                    let c0 = $0.city ?? ""
                    let c1 = $1.city ?? ""
                    return c0 == c1 ? $0.id < $1.id : c0 < c1
                }
                return (state: key, servers: sorted)
            }
            .sorted {
                let lFav = $0.servers.contains { $0.isFavorite }
                let rFav = $1.servers.contains { $0.isFavorite }
                if lFav != rFav { return lFav }
                return $0.state < $1.state
            }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // Map background with star pattern - anchored to top
                ZStack(alignment: .top) {
                    Color.vpnBackground

                    StarPatternView()
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        SVGView(
                            svgName: "map",
                            servers: vpnManager.availableServers,
                            selectedServerId: vpnManager.selectedServer?.id,
                            connectionState: vpnManager.connectionState,
                            isSwitchingServer: vpnManager.isSwitchingServer,
                            onServerTapped: { serverId in
                                vpnManager.selectServerFromMap(serverId)
                            }
                        )
                        .frame(width: proxy.size.width, height: mapHeight)
                        .shadow(color: Color(red: 0.7, green: 0.13, blue: 0.17).opacity(0.25), radius: 10, x: 0, y: 8)
                    }
                    .padding(.top, Self.topMapPadding)
                }
                .ignoresSafeArea()

                // Scrollable Sheet Content
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .bottom) {
                        Spacer()
                            .frame(height: mapHeight)
                            .background(trackSheetHeight())

                        LinearGradient(
                            gradient: Gradient(colors: [.clear, Color.vpnBackground]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: proxy.size.width, height: Self.bottomGradientHeight)
                    }

                    VStack(spacing: 12) {
                        // Drag Handle
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.vpnTextSecondary.opacity(0.5))
                            .frame(width: 40, height: 4)
                            .padding(.top, 8)

                        // Search Bar
                        SearchBarView(searchText: $searchText)
                            .padding(.horizontal, 16)
                            .onChange(of: searchText) { newValue in
                                let sanitized = String(newValue.filter { !$0.isNewline && !($0.asciiValue.map({ $0 < 0x20 }) ?? false) }.prefix(100))
                                if sanitized != newValue { searchText = sanitized }
                            }

                        // Locations Section Header
                        HStack {
                            Text("LOCATIONS (\(filteredServers.count))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        // Server list
                        VStack(spacing: 8) {
                            ForEach(groupedServers, id: \.state) { group in
                                if group.servers.count == 1 {
                                    // Single server — render as flat card directly
                                    let server = group.servers[0]
                                    ServerRowView(
                                        server: server,
                                        isSelected: vpnManager.selectedServer?.id == server.id,
                                        action: { vpnManager.selectServer(server) },
                                        onToggleFavorite: { vpnManager.toggleFavorite(server) }
                                    )
                                    .id("\(server.id)-\(server.isFavorite)")
                                } else {
                                    // Multiple servers — StateCard header
                                    VStack(spacing: 0) {
                                        Button(action: {
                                            if group.servers.count > 3 {
                                                sheetGroup = SheetGroup(id: group.state, servers: group.servers)
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedState = expandedState == group.state ? nil : group.state
                                                }
                                            }
                                        }) {
                                            HStack(spacing: 12) {
                                                Text("🇺🇸")
                                                    .font(.system(size: 24))

                                                Text(group.state)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.vpnTextPrimary)

                                                Spacer()

                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.vpnTextSecondary)
                                                    .rotationEffect(
                                                        group.servers.count <= 3 && expandedState == group.state
                                                            ? .degrees(90) : .degrees(0)
                                                    )
                                                    .animation(.easeInOut(duration: 0.2), value: expandedState)
                                            }
                                            .padding(12)
                                            .background(Color.vpnCardBackground)
                                            .cornerRadius(8)
                                        }

                                        // Inline expand for ≤3 servers
                                        if group.servers.count <= 3 && expandedState == group.state {
                                            VStack(spacing: 4) {
                                                ForEach(group.servers) { server in
                                                    ServerSubItemView(
                                                        server: server,
                                                        isSelected: vpnManager.selectedServer?.id == server.id,
                                                        action: { vpnManager.selectServer(server) },
                                                        onToggleFavorite: { vpnManager.toggleFavorite(server) }
                                                    )
                                                    .id("\(server.id)-\(server.isFavorite)")
                                                }
                                            }
                                            .padding(.top, 4)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .animation(.easeInOut(duration: 0.2), value: expandedState)

                        // Bottom padding for tab bar
                        Spacer().frame(height: 80)
                    }
                    .background(Color.vpnBackground.padding(.bottom, -(proxy.size.height * 2)))
                }
                .frame(width: proxy.size.width)
            }
            .background(Color.vpnSecondaryBackground)
            .onAppear {
                mapHeight = proxy.size.height * 0.67

                // Auto-expand selected server's state (only if ≤3 servers in that group)
                if let selectedState = vpnManager.selectedServer?.countryName,
                   let group = groupedServers.first(where: { $0.state == selectedState }),
                   group.servers.count <= 3 {
                    expandedState = selectedState
                }
            }
            .onChange(of: proxy.size.height) { height in
                mapHeight = height * 0.67
            }
            .sheet(item: $sheetGroup) { group in
                StateServersSheetView(
                    stateName: group.id,
                    vpnManager: vpnManager,
                    onServerSelected: { server in
                        vpnManager.selectServer(server)
                        sheetGroup = nil
                    }
                )
            }
        }
    }

    private func trackSheetHeight() -> some View {
        GeometryReader { inner in
            Color.clear
                .preference(
                    key: ViewHeightPreferenceKey.self,
                    value: inner.size.height
                )
        }
        .onPreferenceChange(ViewHeightPreferenceKey.self) { viewHeight in
            sheetHeight = viewHeight
        }
    }
}

// MARK: - Server Sub Item (indented row for inline-expanded groups)

private struct ServerSubItemView: View {
    let server: Server
    let isSelected: Bool
    let action: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.city ?? server.countryName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.vpnTextPrimary)

                        Text(server.id)
                            .font(.system(size: 11))
                            .foregroundColor(.vpnTextSecondary)
                    }

                    Spacer()

                    LoadIndicatorView(load: server.load, size: .small)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(server.latencyMs > 0 ? "\(server.latencyMs)" : "--")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(latencyColor(server.latencyMs))
                        Text("ms")
                            .font(.system(size: 9))
                            .foregroundColor(.vpnTextSecondary)
                    }
                    .frame(width: 34)
                }
            }

            Button(action: onToggleFavorite) {
                Image(systemName: server.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(server.isFavorite ? .vpnYellow : .vpnTextTertiary)
                    .frame(width: 18)
            }
        }
        .padding(10)
        .padding(.leading, 16)
        .background(isSelected ? Color.vpnSecondaryBackground : Color.vpnCardBackground)
        .cornerRadius(8)
    }
}

// MARK: - State Servers Bottom Sheet (for groups with >3 servers)

private struct StateServersSheetView: View {
    let stateName: String
    @ObservedObject var vpnManager: VPNManager
    let onServerSelected: (Server) -> Void

    var servers: [Server] {
        vpnManager.availableServers
            .filter { $0.countryName == stateName }
            .sorted {
                let c0 = $0.city ?? ""
                let c1 = $1.city ?? ""
                return c0 == c1 ? $0.id < $1.id : c0 < c1
            }
    }

    @ViewBuilder
    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.vpnTextSecondary.opacity(0.5))
                    .frame(width: 40, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(stateName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)
                Text("\(servers.count) servers")
                    .font(.system(size: 14))
                    .foregroundColor(.vpnTextSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(servers) { server in
                        ServerSubItemView(
                            server: server,
                            isSelected: vpnManager.selectedServer?.id == server.id,
                            action: { onServerSelected(server) },
                            onToggleFavorite: { vpnManager.toggleFavorite(server) }
                        )
                        .id("\(server.id)-\(server.isFavorite)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Color.vpnBackground.ignoresSafeArea())
    }

    var body: some View {
        if #available(iOS 16, *) {
            sheetContent
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        } else {
            sheetContent
        }
    }
}

// MARK: - Supporting Views

private struct ViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct StarPatternView: View {
    var body: some View {
        Canvas { context, size in
            let starSize: CGFloat = 6
            let spacing: CGFloat = 30
            let rows = Int(UIScreen.main.bounds.height / spacing) + 2
            let cols = Int(UIScreen.main.bounds.width / spacing) + 2
            let starColor = Color.white.opacity(0.025)

            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * spacing
                    let y = CGFloat(row) * spacing
                    let starPath = createStar(center: CGPoint(x: x, y: y), size: starSize)
                    context.fill(starPath, with: .color(starColor))
                }
            }
        }
    }

    private func createStar(center: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        let innerRadius = size / 2.4
        let outerRadius = size

        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ServersView(vpnManager: VPNManager())
}
