// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "CatButlerCore",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "CatButlerCore", targets: ["CatButlerCore"])
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.0"),
  ],
  targets: [
    .target(
      name: "CatButlerCore",
      dependencies: [
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "CatButlerCoreTests",
      dependencies: [
        "CatButlerCore",
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
  ]
)
