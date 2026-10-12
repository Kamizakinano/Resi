import Foundation
import StoreKit
import Observation

@MainActor
@Observable
final class PremiumManager {
    static let shared = PremiumManager()

    static let productIDs = ["com.returnmate.premium.monthly", "com.returnmate.premium.yearly"]

    /// Le app installate con sideload non possono acquistare tramite App Store:
    /// in questa build le funzioni Premium sono sbloccate per poterle provare.
    static let sideloadUnlock = true

    var products: [Product] = []
    var purchasedIDs: Set<String> = []
    var loadError: String?
    var isLoading = false

    var isPremium: Bool { Self.sideloadUnlock || !purchasedIDs.isEmpty }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            if products.isEmpty {
                loadError = "Gli abbonamenti non sono disponibili in questa installazione: l'app deve essere distribuita tramite App Store."
            }
        } catch {
            loadError = "Impossibile contattare l'App Store: \(error.localizedDescription)"
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { ids.insert(t.productID) }
        }
        purchasedIDs = ids
    }

    func purchase(_ product: Product) async -> String? {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    await refreshEntitlements()
                    return nil
                }
                return "Transazione non verificata."
            case .userCancelled: return nil
            case .pending: return "Acquisto in attesa di approvazione."
            @unknown default: return nil
            }
        } catch {
            return error.localizedDescription
        }
    }

    func restore() async -> String? {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
