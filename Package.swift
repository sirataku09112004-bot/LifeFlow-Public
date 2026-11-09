// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LifeFlowCore", products: [.library(name: "LifeFlowCore", targets: ["LifeFlowCore"])], targets: [.target(name: "LifeFlowCore", path: "Sources/Core"), .testTarget(name: "LifeFlowCoreTests", dependencies: ["LifeFlowCore"], path: "Tests")])

