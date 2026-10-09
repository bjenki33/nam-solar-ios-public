// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SolarCore",
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [.library(name: "SolarCore", targets: ["SolarCore"])],
    targets: [
        .target(name: "SolarCore", path: ".", sources: ["SolarCore.swift", "SolarBatteryPower.swift", "SolarHistoryPreparation.swift", "SolarChartModel.swift", "SolarDeviceHistory.swift", "SolarChartRendering.swift", "SolarEnergyModel.swift", "SolarEnergyStore.swift", "SolarSOCStatistics.swift"]),
        .testTarget(name: "SolarCoreTests", dependencies: ["SolarCore"], path: ".", sources: ["SolarCoreTests.swift", "SolarBatteryPowerTests.swift", "SolarHistoryPreparationTests.swift", "SolarChartModelTests.swift", "SolarDeviceHistoryTests.swift", "SolarEnergyTests.swift", "SolarHistoryRegressionTests.swift"])
    ],
    swiftLanguageModes: [.v5]
)
