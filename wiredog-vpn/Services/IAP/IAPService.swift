import StoreKit

@MainActor
final class IAPService: ObservableObject {
    static let shared = IAPService()

    static let productIDs: Set<String> = [
        "com.wiredog.vpn.1month",
        "com.wiredog.vpn.12months"
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading: Bool = false
    @Published var purchaseError: String? = nil

    private var transactionListenerTask: Task<Void, Never>?

    enum PurchaseResult {
        case success
        case cancelled
        case pending
        case failed(String)
    }

    private func iapLog(_ message: String, level: LogService.LogLevel = .info) {
        print("[IAPService] \(message)")
        LogService.shared.logApp("[IAPService] \(message)", level: level)
    }

    private init() {
        transactionListenerTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                iapLog("Transaction.updates — received update")
                if case .verified(let tx) = result {
                    iapLog("Transaction.updates — verified tx id=\(tx.id), productID=\(tx.productID)", level: .debug)
                    try? await self.validateAndRefresh(transactionID: tx.id, productID: tx.productID, jws: result.jwsRepresentation)
                    await tx.finish()
                    iapLog("Transaction.updates — finished tx id=\(tx.id)", level: .debug)
                } else {
                    iapLog("Transaction.updates — unverified transaction, skipping")
                }
            }
        }
    }

    func fetchProducts() async {
        LogService.shared.logApp("[IAPService] fetchProducts — requesting products", level: .info)
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            LogService.shared.logApp("[IAPService] fetchProducts — received \(fetched.count) product(s)", level: .info)
            LogService.shared.logApp("[IAPService] fetchProducts — products: \(fetched.map { "\($0.id) (\($0.displayPrice))" })", level: .debug)
            if fetched.isEmpty {
                LogService.shared.logApp("[IAPService] fetchProducts — WARNING: no products returned. Check that product IDs are registered in App Store Connect and the app is signed with the correct provisioning profile.", level: .warning)
            }
            products = fetched
        } catch {
            purchaseError = "Unable to load subscription options."
            LogService.shared.logApp("[IAPService] fetchProducts error: \(error) | \((error as NSError).code) | \((error as NSError).domain)", level: .error)
        }
    }

    func purchase(_ product: Product) async -> PurchaseResult {
        LogService.shared.logApp("[IAPService] purchase — starting", level: .info)
        LogService.shared.logApp("[IAPService] purchase — productID: \(product.id), price: \(product.displayPrice)", level: .debug)
        do {
            let result = try await product.purchase()
            LogService.shared.logApp("[IAPService] purchase — StoreKit result: \(result)", level: .debug)
            switch result {
            case .success(let verification):
                let jws = verification.jwsRepresentation
                switch verification {
                case .verified(let tx):
                    let env: String
                    if #available(iOS 16.0, *) { env = "\(tx.environment)" } else { env = "unknown" }
                    iapLog("purchase — transaction verified: id=\(tx.id), productID=\(tx.productID), environment=\(env)", level: .debug)
                    do {
                        try await validateAndRefresh(transactionID: tx.id, productID: tx.productID, jws: jws)
                        await tx.finish()
                        LogService.shared.logApp("[IAPService] purchase — success, transaction finished", level: .info)
                        return .success
                    } catch {
                        // Don't finish — StoreKit will retry on next launch
                        LogService.shared.logApp("[IAPService] purchase — backend validation failed: \(error)", level: .error)
                        purchaseError = error.localizedDescription
                        return .failed(error.localizedDescription)
                    }
                case .unverified(_, let verificationError):
                    LogService.shared.logApp("[IAPService] purchase — transaction unverified: \(verificationError)", level: .error)
                    purchaseError = "Purchase could not be verified."
                    return .failed("Purchase could not be verified.")
                }
            case .userCancelled:
                LogService.shared.logApp("[IAPService] purchase — user cancelled", level: .info)
                return .cancelled
            case .pending:
                LogService.shared.logApp("[IAPService] purchase — pending approval", level: .info)
                return .pending
            @unknown default:
                LogService.shared.logApp("[IAPService] purchase — unknown result", level: .warning)
                return .failed("Unknown purchase result.")
            }
        } catch {
            let nsError = error as NSError
            LogService.shared.logApp("[IAPService] purchase — StoreKit threw: \(error.localizedDescription) | domain=\(nsError.domain) code=\(nsError.code) | userInfo=\(nsError.userInfo)", level: .error)
            purchaseError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async -> Bool {
        LogService.shared.logApp("[IAPService] restorePurchases — checking currentEntitlements", level: .info)
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result {
                LogService.shared.logApp("[IAPService] restorePurchases — found entitlement: productID=\(tx.productID), revocationDate=\(String(describing: tx.revocationDate))", level: .debug)
                if Self.productIDs.contains(tx.productID), tx.revocationDate == nil {
                    try? await validateAndRefresh(transactionID: tx.id, productID: tx.productID, jws: result.jwsRepresentation)
                    found = true
                }
            } else if case .unverified(_, let err) = result {
                LogService.shared.logApp("[IAPService] restorePurchases — unverified entitlement: \(err)", level: .warning)
            }
        }
        LogService.shared.logApp("[IAPService] restorePurchases — result: found=\(found)", level: .info)
        return found
    }

    private func validateAndRefresh(transactionID: UInt64, productID: String, jws: String) async throws {
        iapLog("validateAndRefresh — sending to backend", level: .info)
        iapLog("validateAndRefresh — transactionID=\(transactionID), productID=\(productID), jwsLength=\(jws.count)", level: .debug)
        let body = ValidateIAPRequest(transactionId: String(transactionID), productId: productID, jwsRepresentation: jws)
        let response: ValidateIAPResponse = try await APIClient.shared.request(
            endpoint: .validateIAP,
            body: body
        )
        iapLog("validateAndRefresh — backend response: success=\(response.success), message=\(response.message ?? "nil")")
        guard response.success else {
            throw IAPError.backendRejected(response.message ?? "Validation failed.")
        }
        try await AuthService.shared.fetchUserProfile()
    }
}

enum IAPError: LocalizedError {
    case backendRejected(String)

    var errorDescription: String? {
        switch self {
        case .backendRejected(let msg): return msg
        }
    }
}
