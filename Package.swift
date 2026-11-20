// swift-tools-version:5.9
//
// SDK iOS du réseau d'échange de bannières BoostYourApp, pour Swift Package Manager.
// À la racine du dépôt public (https://github.com/tals-enterprise/boostyourapp-sdk) : Xcode › Add Package
// avec l'URL du dépôt, produit BoostNetwork. Les versions sont les tags du dépôt (0.1.0, 0.2.0…).
// Les tests (logique, contrat de l'API) tournent aussi sur macOS : `swift test` à la racine.
import PackageDescription

let package = Package(
    name: "BoostNetwork",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "BoostNetwork", targets: ["BoostNetwork"])
    ],
    targets: [
        .target(
            name: "BoostNetwork",
            path: "ios/Sources/BoostNetwork",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "BoostNetworkTests",
            dependencies: ["BoostNetwork"],
            path: "ios/Tests/BoostNetworkTests"
        )
    ]
)
