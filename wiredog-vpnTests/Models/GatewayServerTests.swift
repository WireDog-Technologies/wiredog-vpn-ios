import Testing
import Foundation
@testable import wiredog_vpn

struct GatewayServerTests {

    private func decodeServers(_ json: String) throws -> [APIServer] {
        try JSONDecoder().decode([APIServer].self, from: json.data(using: .utf8)!)
    }

    private let chicagoJSON = """
    { "id": "IL-CHI-TEST", "state": "Illinois", "stateCode": "IL", "city": "Chicago",
      "latitude": 41.8, "longitude": -87.6, "isRecommended": false, "latency": 20, "load": 5, "host": "chi.example.com" }
    """

    private let gatewayJSON = """
    { "id": "IL-CHI-TEST", "state": "Illinois", "stateCode": "IL", "city": "Chicago",
      "latitude": 41.8, "longitude": -87.6, "isRecommended": false, "latency": 20, "load": 5, "host": "chi.example.com",
      "gatewayId": 11, "gatewayName": "Lone Star Gateway", "isDedicated": true }
    """

    // MARK: - Decoding

    @Test func apiServer_withoutGatewayFields_decodesAsBefore() throws {
        let servers = try decodeServers("[\(chicagoJSON)]")

        #expect(servers[0].gatewayId == nil)
        #expect(servers[0].gatewayName == nil)
    }

    @Test func apiServer_decodesGatewayFields() throws {
        let servers = try decodeServers("[\(gatewayJSON)]")

        #expect(servers[0].gatewayId == 11)
        #expect(servers[0].gatewayName == "Lone Star Gateway")
    }

    // MARK: - Server model

    @Test func normalServer_keepsItsApiIdAndIsNotDedicated() throws {
        let api = try decodeServers("[\(chicagoJSON)]")[0]
        let server = Server.from(apiServer: api)

        #expect(server.id == "IL-CHI-TEST")
        #expect(server.connectServerId == "IL-CHI-TEST")
        #expect(server.isDedicated == false)
        #expect(server.gatewayName == nil)
    }

    @Test func gatewayServer_hasAUniqueIdButConnectsToTheRealNode() throws {
        let api = try decodeServers("[\(gatewayJSON)]")[0]
        let server = Server.from(apiServer: api)

        #expect(server.id == "IL-CHI-TEST_gw11")
        #expect(server.connectServerId == "IL-CHI-TEST")
        #expect(server.gatewayId == 11)
        #expect(server.gatewayName == "Lone Star Gateway")
        #expect(server.isDedicated)
    }

    @Test func sharedNodeAndItsGateway_areDistinctEntries() throws {
        let list = try decodeServers("[\(chicagoJSON), \(gatewayJSON)]").map { Server.from(apiServer: $0) }

        #expect(list.count == 2)
        #expect(list[0].id != list[1].id)
        #expect(list[0].connectServerId == list[1].connectServerId)
        #expect(Set(list.map(\.id)).count == 2)
    }

    @Test func twoGatewaysOnOneNode_areDistinctEntries() throws {
        let second = gatewayJSON.replacingOccurrences(of: "\"gatewayId\": 11", with: "\"gatewayId\": 12")
            .replacingOccurrences(of: "Lone Star Gateway", with: "Lone Star West")
        let list = try decodeServers("[\(gatewayJSON), \(second)]").map { Server.from(apiServer: $0) }

        #expect(list[0].id != list[1].id)
        #expect(list.map(\.gatewayId) == [11, 12])
    }

    @Test func existingServerInitializerCalls_stillCompile_withGatewayDefaults() {
        let server = MockData.servers[0]

        #expect(server.gatewayId == nil)
        #expect(server.apiServerId == nil)
        #expect(server.connectServerId == server.id)
    }

    // MARK: - Connect request

    @Test func connectRequest_includesDedicatedIpIdOnlyWhenPicked() throws {
        let withGateway = try JSONEncoder().encode(ConnectRequest(serverId: "IL-CHI-TEST", dedicatedIpId: 11))
        let without = try JSONEncoder().encode(ConnectRequest(serverId: "IL-CHI-TEST"))

        let withJSON = try JSONSerialization.jsonObject(with: withGateway) as? [String: Any]
        let withoutJSON = try JSONSerialization.jsonObject(with: without) as? [String: Any]

        #expect(withJSON?["dedicatedIpId"] as? Int == 11)
        #expect(withJSON?["serverId"] as? String == "IL-CHI-TEST")
        #expect(withoutJSON?["dedicatedIpId"] == nil)
    }

    // MARK: - Endpoint

    @Test func serversEndpoint_optsInToGateways() {
        #expect(APIEndpoint.servers.path == "/vpn/servers")
        #expect(APIEndpoint.servers.queryItems == [URLQueryItem(name: "gateways", value: "1")])
    }
}
