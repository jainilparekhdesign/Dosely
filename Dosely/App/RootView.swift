import LocalAuthentication
import SwiftData
import SwiftUI

struct RootView: View {
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @AppStorage(Prefs.appLock) private var appLock = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var locked = UserDefaults.standard.bool(forKey: Prefs.appLock)

    var body: some View {
        ZStack {
            if onboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
            if locked && appLock && onboarded {
                LockView { locked = false }
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && appLock { locked = true }
        }
    }
}

struct MainTabView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "checklist", value: AppTab.today) {
                TodayView()
            }
            Tab("Medicines", systemImage: "pills", value: AppTab.medications) {
                MedicationsView()
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .sheet(isPresented: $router.showScan) {
            ScanFlowView()
        }
        .sheet(isPresented: $router.showAddMedication) {
            NavigationStack {
                MedicationEditorView(medication: nil)
            }
        }
        #if DEBUG
        .sheet(item: Binding(get: { DebugSupport.value(after: "-debugScreen").map(DebugScreen.init) }, set: { _ in })) { screen in
            DebugScreenView(screen: screen.name)
        }
        #endif
    }
}

struct LockView: View {
    var onUnlock: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Dosely is locked").font(.title2.bold())
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            Button("Unlock", action: authenticate).buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { authenticate() }
    }

    private func authenticate() {
        let context = LAContext()
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            onUnlock()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your medicine information") { success, e in
            DispatchQueue.main.async {
                if success { onUnlock() } else { error = e?.localizedDescription }
            }
        }
    }
}

/// Resolves which profile is being viewed (self or a caregiver sub-profile).
struct ActiveProfile {
    static func resolve(_ profiles: [Profile], id: String) -> Profile? {
        profiles.first { $0.id.uuidString == id } ?? profiles.first(where: \.isPrimary) ?? profiles.first
    }
}

/// Toolbar menu for switching between profiles.
struct ProfileSwitcher: View {
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @AppStorage(Prefs.activeProfileID) private var activeID = ""

    var body: some View {
        let active = ActiveProfile.resolve(profiles, id: activeID)
        if profiles.count > 1 {
            Menu {
                ForEach(profiles) { p in
                    Button {
                        activeID = p.id.uuidString
                    } label: {
                        if p.id == active?.id { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                    }
                }
            } label: {
                ProfileAvatar(profile: active, size: 30)
            }
            .accessibilityLabel("Switch profile, currently \(active?.name ?? "")")
        }
    }
}

struct ProfileAvatar: View {
    let profile: Profile?
    var size: CGFloat = 36

    var body: some View {
        Text(profile?.initials ?? "?")
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: profile?.colorHex ?? "#008F8F"), in: Circle())
    }
}
