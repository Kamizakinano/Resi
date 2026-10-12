import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.homePath) {
                HomeView()
                    .navigationDestination(for: PurchaseRoute.self) { PurchaseDetailView(id: $0.id) }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack(path: $router.calendarPath) {
                CalendarView()
                    .navigationDestination(for: PurchaseRoute.self) { PurchaseDetailView(id: $0.id) }
            }
            .tabItem { Label("Calendario", systemImage: "calendar") }
            .tag(AppTab.calendar)

            NavigationStack(path: $router.searchPath) {
                SearchView()
                    .navigationDestination(for: PurchaseRoute.self) { PurchaseDetailView(id: $0.id) }
            }
            .tabItem { Label("Acquisti", systemImage: "magnifyingglass") }
            .tag(AppTab.search)

            NavigationStack {
                StatsView()
            }
            .tabItem { Label("Statistiche", systemImage: "chart.bar") }
            .tag(AppTab.stats)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Impostazioni", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .sheet(isPresented: $router.showAdd) {
            AddPurchaseView()
        }
    }
}
