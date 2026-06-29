import SwiftUI
import WebKit

struct SVGView: UIViewRepresentable {
    let svgName: String
    let servers: [Server]
    let selectedServerId: String?
    let onServerTapped: (String) -> Void

    // Zoom configuration — matches Android's 2.5x
    private let zoomLevel: CGFloat = 2.5
    private let animationDuration: Int = 400

    func makeCoordinator() -> Coordinator {
        Coordinator(onServerTapped: onServerTapped)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        contentController.add(context.coordinator, name: "serverMarkerTapped")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = UIColor.clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false

        context.coordinator.webView = webView

        loadSVGWithMarkers(webView: webView)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Match by city (same as Android: selectedServer?.city == server.city)
        // so any server in the same city highlights the correct marker.
        let js: String
        if let serverId = selectedServerId,
           let server = servers.first(where: { $0.id == serverId }),
           let city = server.city,
           let position = ServerMapPosition.position(forCity: city) {
            let safeCity = city.replacingOccurrences(of: "'", with: "\\'")
            js = "zoomToPoint(\(position.x), \(position.y), \(zoomLevel), \(animationDuration)); setSelectedMarker('\(safeCity)');"
        } else {
            js = "resetView(\(animationDuration)); setSelectedMarker(null);"
        }

        // Run immediately if page is loaded; otherwise queue for after didFinish
        context.coordinator.evaluateOrQueue(js)
    }

    private func loadSVGWithMarkers(webView: WKWebView) {
        guard let svgURL = Bundle.main.url(forResource: svgName, withExtension: "svg"),
              let svgContent = try? String(contentsOf: svgURL, encoding: .utf8) else {
            return
        }

        let markersHTML = generateMarkersHTML()
        let modifiedSVG = injectMarkersIntoSVG(svgContent: svgContent, markersHTML: markersHTML)

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    background: transparent;
                    overflow: hidden;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    width: 100vw;
                    height: 100vh;
                }
                #map-container {
                    width: 100%;
                    height: 100%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                svg {
                    background: transparent;
                    width: 100%;
                    height: 100%;
                }

                /* Server marker styles */
                .server-marker {
                    cursor: pointer;
                    pointer-events: all;
                }
                .server-marker .outer-ring {
                    fill: rgba(74, 144, 226, 0.3);
                    animation: pulse 2s ease-in-out infinite;
                    transform-origin: center;
                    transform-box: fill-box;
                }
                .server-marker .inner-dot {
                    fill: #4A90E2;
                }
                .server-marker.selected .outer-ring {
                    fill: rgba(46, 204, 113, 0.4);
                }
                .server-marker.selected .inner-dot {
                    fill: #2ECC71;
                }

                @keyframes pulse {
                    0%, 100% { opacity: 0.6; r: 20; }
                    50%       { opacity: 1;   r: 28; }
                }
            </style>
        </head>
        <body>
            <div id="map-container">
                \(modifiedSVG)
            </div>
            <script>
                const svg = document.querySelector('svg');
                const originalViewBox = { x: 0, y: 0, width: 2000, height: 1200 };
                let currentViewBox = { ...originalViewBox };
                let animationId = null;

                function easeOutCubic(t) {
                    return 1 - Math.pow(1 - t, 3);
                }

                function animateViewBox(targetX, targetY, targetWidth, targetHeight, duration) {
                    if (animationId) cancelAnimationFrame(animationId);

                    const startViewBox = { ...currentViewBox };
                    const startTime = performance.now();

                    function animate(currentTime) {
                        const elapsed = currentTime - startTime;
                        const progress = Math.min(elapsed / duration, 1);
                        const t = easeOutCubic(progress);

                        currentViewBox.x      = startViewBox.x      + (targetX      - startViewBox.x)      * t;
                        currentViewBox.y      = startViewBox.y      + (targetY      - startViewBox.y)      * t;
                        currentViewBox.width  = startViewBox.width  + (targetWidth  - startViewBox.width)  * t;
                        currentViewBox.height = startViewBox.height + (targetHeight - startViewBox.height) * t;

                        svg.setAttribute('viewBox',
                            `${currentViewBox.x} ${currentViewBox.y} ${currentViewBox.width} ${currentViewBox.height}`);

                        if (progress < 1) {
                            animationId = requestAnimationFrame(animate);
                        } else {
                            animationId = null;
                        }
                    }

                    animationId = requestAnimationFrame(animate);
                }

                function zoomToPoint(x, y, zoom, duration) {
                    const newWidth  = originalViewBox.width  / zoom;
                    const newHeight = originalViewBox.height / zoom;
                    const newX = x - newWidth  / 2;
                    const newY = y - newHeight / 2;

                    const clampedX = Math.max(0, Math.min(newX, originalViewBox.width  - newWidth));
                    const clampedY = Math.max(0, Math.min(newY, originalViewBox.height - newHeight));

                    animateViewBox(clampedX, clampedY, newWidth, newHeight, duration);
                }

                function resetView(duration) {
                    animateViewBox(originalViewBox.x, originalViewBox.y,
                                   originalViewBox.width, originalViewBox.height, duration);
                }

                // Match by city name so all servers in the same city highlight correctly
                function setSelectedMarker(city) {
                    document.querySelectorAll('.server-marker').forEach(m => m.classList.remove('selected'));
                    if (city) {
                        document.querySelectorAll('.server-marker').forEach(m => {
                            if (m.dataset.city === city) m.classList.add('selected');
                        });
                    }
                }

                document.querySelectorAll('.server-marker').forEach(marker => {
                    marker.addEventListener('click', function(e) {
                        e.stopPropagation();
                        window.webkit.messageHandlers.serverMarkerTapped.postMessage(this.dataset.serverId);
                    });
                });
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: svgURL.deletingLastPathComponent())
    }

    /// Generate one marker per unique city (matching Android's distinctBy { it.city }).
    private func generateMarkersHTML() -> String {
        var markers = ""
        var seenCities = Set<String>()

        for server in servers {
            guard let city = server.city,
                  !seenCities.contains(city),
                  let position = ServerMapPosition.position(forCity: city) else { continue }
            seenCities.insert(city)

            markers += """
            <g id="marker-\(server.id)"
               class="server-marker"
               data-server-id="\(server.id)"
               data-city="\(city)"
               transform="translate(\(position.x), \(position.y))">
                <circle class="outer-ring" cx="0" cy="0" r="20"/>
                <circle class="inner-dot" cx="0" cy="0" r="8"/>
            </g>
            """
        }
        return markers
    }

    private func injectMarkersIntoSVG(svgContent: String, markersHTML: String) -> String {
        let markerGroup = """
        <g id="server-markers" style="pointer-events: all;">
            \(markersHTML)
        </g>
        """
        return svgContent.replacingOccurrences(of: "</svg>", with: "\(markerGroup)</svg>")
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onServerTapped: (String) -> Void
        weak var webView: WKWebView?
        private var isPageLoaded = false
        private var pendingJS: String?

        init(onServerTapped: @escaping (String) -> Void) {
            self.onServerTapped = onServerTapped
        }

        /// Run JS immediately if the page is loaded; otherwise queue for after load.
        func evaluateOrQueue(_ js: String) {
            if isPageLoaded {
                webView?.evaluateJavaScript(js, completionHandler: nil)
            } else {
                pendingJS = js
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            if let js = pendingJS {
                webView.evaluateJavaScript(js, completionHandler: nil)
                pendingJS = nil
            }
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "serverMarkerTapped",
               let serverId = message.body as? String {
                DispatchQueue.main.async {
                    self.onServerTapped(serverId)
                }
            }
        }
    }
}
