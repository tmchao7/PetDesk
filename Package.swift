// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PetDeskCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PetDeskCore", targets: ["PetDeskCore"]),
        .executable(name: "PetDeskCoreChecks", targets: ["PetDeskCoreChecks"]),
        .executable(name: "PetDeskAppCheck", targets: ["PetDeskAppCheck"]),
    ],
    targets: [
        .target(
            name: "PetDeskCore",
            path: "PetDesk",
            exclude: [
                "App",
                "Features/PetRender",
                "Features/PetWindow",
                "Features/Settings",
                "Features/Todo/TodoView.swift",
                "Features/UsageStats/StatsView.swift",
            ],
            sources: [
                "Features/Avatar",
                "Features/Focus",
                "Features/Notification",
                "Features/PetDomain",
                "Features/SystemLoad",
                "Features/Todo",
                "Features/UsageStats",
                "Features/UserActivity",
                "Shared",
            ]
        ),
        .executableTarget(
            name: "PetDeskCoreChecks",
            dependencies: ["PetDeskCore"],
            path: "Checks"
        ),
        .executableTarget(
            name: "PetDeskAppCheck",
            dependencies: ["PetDeskCore"],
            path: "PetDesk",
            exclude: [
                "Features/Avatar",
                "Features/Focus",
                "Features/Notification",
                "Features/PetDomain",
                "Features/SystemLoad",
                "Features/Todo/TodoItem.swift",
                "Features/Todo/TodoStore.swift",
                "Features/UsageStats/DayStats.swift",
                "Features/UsageStats/UsageStatsStore.swift",
                "Features/UserActivity",
                "Shared",
            ],
            sources: [
                "App",
                "Features/PetRender",
                "Features/PetWindow",
                "Features/Settings",
                "Features/Todo/TodoView.swift",
                "Features/UsageStats/StatsView.swift",
            ]
        ),
    ]
)
