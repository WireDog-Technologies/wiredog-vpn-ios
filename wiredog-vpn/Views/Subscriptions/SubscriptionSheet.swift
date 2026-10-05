import SwiftUI
import StoreKit

struct SubscriptionSheet: View {
    let onSuccess: () -> Void

    @State private var showAppStorePlans: Bool = false
    @State private var isRequestingCheckout: Bool = false
    @Environment(\.dismiss) private var dismiss

    /// Opens checkout with a one-time handoff code so the already-logged-in user lands
    /// straight on checkout for their existing account instead of the public signup funnel.
    /// Falls back to the static get-started URL if the code request fails (e.g. offline),
    /// so a network hiccup never dead-ends the funnel entirely.
    private func startCheckout() async {
        guard !isRequestingCheckout else { return }
        MilestoneService.shared.record(.paywallCheckoutTapped)
        isRequestingCheckout = true
        defer { isRequestingCheckout = false }

        do {
            let url = try await AuthService.shared.checkoutHandoffURL()
            await UIApplication.shared.open(url)
        } catch {
            LogService.shared.logApp("[Checkout] Handoff token request failed: \(error.localizedDescription)", level: .warning)
            await UIApplication.shared.open(Config.getStartedURL)
        }
    }

    var body: some View {
        ZStack {
            Color.vpnBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Dismiss button
                        HStack {
                            Spacer()
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.vpnTextSecondary)
                                    .padding(10)
                                    .background(Color.vpnCardBackground)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        // Logo
                        Image("Wiredog Vectorized")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 250)
                            .padding(.top, 10)
                            .padding(.bottom, 20)

                        // Title
                        VStack(spacing: 4) {
                            HStack(spacing: 0) {
                                Text("Save ")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.vpnTextPrimary)
                                Text("50%")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.clear)
                                    .overlay(
                                        LinearGradient(
                                            colors: [Color.vpnRedBright, Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .mask(Text("50%").font(.system(size: 28, weight: .bold)))
                                    )
                                Text(" with")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.vpnTextPrimary)
                            }
                            Text("our 2-year plan")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.vpnTextPrimary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        // Subscription card
                        VStack(spacing: 12) {
                            Text("$4.99/month")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.clear)
                                .overlay(
                                    LinearGradient(
                                        colors: [Color.vpnRedBright, Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .mask(Text("$4.99/month").font(.system(size: 20, weight: .bold)))
                                )

                            HStack(spacing: 6) {
                                Text("$239.76")
                                    .strikethrough()
                                    .font(.system(size: 13))
                                    .foregroundColor(.vpnTextSecondary)
                                Text("$119.88 for 24 months")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.vpnTextPrimary)
                            }

                            GradientActionButton(
                                title: "Start Subscription",
                                isLoading: isRequestingCheckout,
                                isDisabled: isRequestingCheckout
                            ) {
                                Task { await startCheckout() }
                            }

                            Button {
                                MilestoneService.shared.record(.paywallBetterPlansTapped)
                                UIApplication.shared.open(Config.pricingURL)
                            } label: {
                                Text("See Better Plans")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.vpnTextPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.vpnBorderColor, lineWidth: 1))
                            }
                        }
                        .padding(20)
                        .background(Color.vpnCardBackground)
                        .cornerRadius(12)
                        .padding(.horizontal, 20)

                        // 30-day money back guarantee
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.vpnRedMedium)
                            Text("30-Day Money Back Guarantee")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 16)
                    }
                }

                // Anchored to bottom
                Button {
                    MilestoneService.shared.record(.paywallAppStoreOpened)
                    showAppStorePlans = true
                } label: {
                    Text("Get App Store Plans")
                        .font(.system(size: 14))
                        .foregroundColor(.vpnTextSecondary)
                        .underline()
                }
                .padding(.vertical, 20)
            }
        }
        .sheet(isPresented: $showAppStorePlans) {
            AppStorePlansSheet {
                dismiss()
                onSuccess()
            }
        }
    }
}

// MARK: - App Store Plans Sheet

struct AppStorePlansSheet: View {
    @ObservedObject private var iapService = IAPService.shared
    let onSuccess: () -> Void

    @State private var selectedProductID: String? = nil
    @State private var isPurchasing: Bool = false
    @State private var showError: Bool = false
    @State private var showPrivacyInfo: Bool = false

    @Environment(\.dismiss) private var dismiss

    var selectedProduct: Product? {
        iapService.products.first { $0.id == selectedProductID }
    }

    var body: some View {
        ZStack {
            Color.vpnBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Dismiss button
                        HStack {
                            Spacer()
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.vpnTextSecondary)
                                    .padding(10)
                                    .background(Color.vpnCardBackground)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        // Logo
                        Image("Wiredog Vectorized")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 250)
                            .padding(.top, 10)
                            .padding(.bottom, 16)

                        // Title
                        Text("App Store Plans")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.vpnTextPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)

                        // Plan cards
                        VStack(spacing: 10) {
                            if iapService.isLoading {
                                ProgressView()
                                    .tint(.vpnTextSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            } else if iapService.products.isEmpty {
                                Text("Subscription options unavailable.\nPlease try again later.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.vpnTextSecondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(iapService.products.sorted { p1, p2 in p1.id.contains("12months") }, id: \.id) { product in
                                    PlanCard(
                                        product: product,
                                        isSelected: selectedProductID == product.id
                                    ) {
                                        selectedProductID = product.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        Spacer()
                    }
                }

                Spacer(minLength: 0)

                // Bottom buttons
                VStack(spacing: 12) {
                    Button {
                        showPrivacyInfo = true
                    } label: {
                        Text("Subscriptions and privacy info")
                            .font(.system(size: 11))
                            .foregroundColor(.vpnTextSecondary.opacity(0.7))
                            .underline()
                    }

                    Text("Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period.")
                        .font(.system(size: 11))
                        .foregroundColor(.vpnTextSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                    GradientActionButton(
                        title: "Start Subscription",
                        isLoading: isPurchasing,
                        isDisabled: selectedProduct == nil || isPurchasing
                    ) {
                        if let product = selectedProduct {
                            Task { await handlePurchase(product) }
                        }
                    }

                    Button {
                        MilestoneService.shared.record(.iapAllPlansTapped)
                        UIApplication.shared.open(Config.pricingURL)
                    } label: {
                        Text("See All Plans")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.vpnTextPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.vpnBorderColor, lineWidth: 1))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Return to our plans")
                            .font(.system(size: 15))
                            .foregroundColor(.clear)
                            .overlay(
                                LinearGradient(
                                    colors: [Color.vpnRedBright, Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .mask(Text("Return to our plans").font(.system(size: 15)))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .task {
            await iapService.fetchProducts()
            if selectedProductID == nil {
                selectedProductID = iapService.products.first(where: { $0.id.contains("12months") })?.id ?? iapService.products.first?.id
            }
        }
        .onChange(of: iapService.products) { products in
            if selectedProductID == nil {
                selectedProductID = products.first(where: { $0.id.contains("12months") })?.id ?? products.first?.id
            }
        }
        .sheet(isPresented: $showPrivacyInfo) {
            PrivacyInfoSheet()
        }
        .alert("Purchase Failed", isPresented: $showError) {
            Button("OK") { iapService.purchaseError = nil }
        } message: {
            Text(iapService.purchaseError ?? "An unknown error occurred.")
        }
        .onChange(of: iapService.purchaseError) { error in
            if error != nil { showError = true }
        }
    }

    private func handlePurchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        MilestoneService.shared.record(.iapPurchaseStarted)
        let result = await iapService.purchase(product)
        switch result {
        case .success:
            dismiss()
            onSuccess()
        case .pending:
            iapService.purchaseError = "Your purchase is awaiting approval."
        case .cancelled, .failed:
            break
        }
    }

}

// MARK: - Plan Card

private struct PlanCard: View {
    let product: Product
    let isSelected: Bool
    let onTap: () -> Void

    var planName: String {
        product.id.contains("12months") ? "1-year plan" : "Monthly plan"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Selection indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.vpnRedMedium : Color.clear)
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(isSelected ? Color.vpnRedMedium : Color.vpnBorderColor, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                if product.id.contains("12months") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(planName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.vpnTextPrimary)
                        (Text("$119.88 ").strikethrough().foregroundColor(.vpnTextSecondary)
                            + Text("$83.90 for 12 months").foregroundColor(.vpnTextSecondary))
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                    Text("$6.99/mo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.vpnRedMedium)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(planName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.vpnTextPrimary)
                        Text("Same flat rate each month")
                            .font(.system(size: 13))
                            .foregroundColor(.vpnTextSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("$9.99/mo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.clear)
                        .overlay(
                            LinearGradient(
                                colors: [Color.vpnRedBright, Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .mask(Text("$9.99/mo").font(.system(size: 13, weight: .semibold)))
                        )
                }
            }
            .padding(16)
            .background(Color.vpnCardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.vpnRedMedium : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Privacy Info Sheet

struct PrivacyInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.vpnBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.vpnTextSecondary)
                            .padding(10)
                            .background(Color.vpnCardBackground)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Text("Privacy Info")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)
                    .padding(.top, 24)
                    .padding(.bottom, 32)

                VStack(spacing: 16) {
                    Button {
                        UIApplication.shared.open(Config.privacyPolicyURL)
                    } label: {
                        HStack(spacing: 12) {
                            Text("Privacy Policy")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.vpnTextPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                        }
                        .padding(16)
                        .background(Color.vpnCardBackground)
                        .cornerRadius(12)
                    }

                    Button {
                        UIApplication.shared.open(Config.termsOfServiceURL)
                    } label: {
                        HStack(spacing: 12) {
                            Text("Terms of Service")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.vpnTextPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                        }
                        .padding(16)
                        .background(Color.vpnCardBackground)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.bottom, 20)
        }
        .modifier(PrivacySheetModifier())
    }
}

struct PrivacySheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.fraction(0.5)])
        } else {
            content
        }
    }
}
