import AppIntents
import LifeFlowCore

@available(iOS 17.0, *)
struct LifeFlowIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [LifeFlowSharedIntentPackage.self] }
}

@available(iOS 17.0, *)
struct LifeFlowProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CheckLifeFlowWidgetRegistrationIntent(),
                    phrases: ["\(.applicationName) の操作を診断"],
                    shortTitle: "操作診断", systemImageName: "waveform.path")
    }
}
