// swift-tools-version: 5.9
import PackageDescription

// Pont Capacitor et cœur iOS du SDK (ios/Sources/BoostNetworkPlugin/Core, copié par sdk/scripts/sync.mjs)
// dans une seule cible : même module qu'avec CocoaPods.
let package = Package(
    name: "BoostyourappCapacitor",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "BoostyourappCapacitor",
            targets: ["BoostNetworkPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "BoostNetworkPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/BoostNetworkPlugin",
            resources: [.copy("PrivacyInfo.xcprivacy")])
    ]
)
