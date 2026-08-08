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
                // App target files are intentionally compiled by PetDeskAppCheck,
                // not by the dependency-free PetDeskCore target.
                "App",
                "Features/PetRender",
                "Features/PetWindow",
                "Features/Settings",
                "AppIcon.icns",
                // Included feature directories may still contain app-only files;
                // keep their AppKit/SwiftUI counterparts out of Core explicitly.
                "Features/Todo/TodoView.swift",
                "Features/UsageStats/StatsView.swift",
                "Features/Avatar/AnimatedAvatarView.swift",
                "Features/Avatar/AnimationFrameStore.swift",
                "Features/Avatar/AvatarPreviewImageFactory.swift",
                "Features/DragShelf/DragShelfPanel.swift",
                "Features/DragShelf/DragShelfView.swift",
                "Features/DragShelf/ShelfRowView.swift",
                "Features/DragShelf/ShelfSelection.swift",
                "Features/PetRender/PetLayerRenderer.swift",
                "Features/PetRender/PetLayerRendererRepresentable.swift",
            ],
            sources: [
                "Features/Avatar",
                "Features/DragShelf",
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
                "AppIcon.icns",
                "Features/Avatar/AvatarCropper.swift",
                "Features/Avatar/AvatarDisplayMode.swift",
                "Features/Avatar/AvatarImageLoader.swift",
                "Features/Avatar/AvatarImportPolicy.swift",
                "Features/Avatar/AvatarRepository.swift",
                "Features/Avatar/AIPoseProvider.swift",
                "Features/Avatar/EyeBandLocator.swift",
                "Features/Avatar/GPTImage2Provider.swift",
                "Features/Avatar/PoseCellProcessor.swift",
                "Features/Avatar/SpriteSheetGenerator.swift",
                "Features/Avatar/SpriteSheetSpec.swift",
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
                "Features/DragShelf/DragShelfStore.swift",
            ],
            sources: [
                "App",
                "Features/PetRender",
                "Features/PetWindow",
                "Features/Settings",
                "Features/Todo/TodoView.swift",
                "Features/UsageStats/StatsView.swift",
                "Features/Avatar/AnimatedAvatarView.swift",
                "Features/Avatar/AnimationFrameStore.swift",
                "Features/Avatar/AvatarPreviewImageFactory.swift",
                "Features/DragShelf/DragShelfPanel.swift",
                "Features/DragShelf/DragShelfView.swift",
                "Features/DragShelf/ShelfRowView.swift",
                "Features/DragShelf/ShelfSelection.swift",
                "Features/PetRender/PetLayerRenderer.swift",
                "Features/PetRender/PetLayerRendererRepresentable.swift",
            ]
        ),
    ]
)
