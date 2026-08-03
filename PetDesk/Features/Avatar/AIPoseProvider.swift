import CoreGraphics
import Foundation

/// AI 姿态生成提供者协议：从用户头像生成多行动画精灵图。
///
/// 当前默认使用本地程序化方案（`SpriteSheetGenerator`）；
/// 后续可接入 GPT Image 2（RunComfy/OpenAI）、Stable Diffusion + ControlNet
/// 等在线或本地 AI 生成器，实现更丰富的真实姿态（躺平、跑步、伸手等）。
public protocol AIPoseProvider: Sendable {
  /// 是否支持基于参考图的角色一致性生成。
  var supportsReferenceImage: Bool { get }

  /// 从参考图生成完整精灵图。
  /// - Parameter referenceImage: 用户导入并裁切后的头像。
  /// - Returns: 精灵图 CGImage；失败返回 nil（调用方回退程序化方案）。
  func generateSpritesheet(from referenceImage: CGImage) async throws -> CGImage?
}
