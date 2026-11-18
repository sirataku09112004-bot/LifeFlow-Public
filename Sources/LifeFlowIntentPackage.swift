import AppIntents
import LifeFlowCore

@available(iOS 17.0, *)
struct LifeFlowIntentPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [LifeFlowSharedIntentPackage.self] }
}
