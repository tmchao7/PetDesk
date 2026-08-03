import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// AI 姿态生成失败原因（调用方静默回退程序化生成）。
public enum AIPoseError: Error, Sendable, Equatable {
  case invalidResponse
  case httpStatus(Int)
  case decodingFailed
  case invalidReferenceImage
}

/// 需要单独生成规范姿势的动画行（其余行从最近的姿势单元派生微变换）。
public enum AIPose: String, Sendable, CaseIterable {
  case idle
  case running
  case sleeping
  case happy

  /// 编辑请求的姿势描述（身份锁 + 品红背景约束，风格参考 Codex Pet skill）。
  var prompt: String {
    let identity =
      "Create one full-body chibi sprite of the exact character from the reference image. "
      + "Preserve the face, hair, outfit, colors, and identity exactly. "
      + "EXAGGERATED chibi proportions: head about 60 percent of the total figure height; "
      + "body and legs tiny and stubby. Pixel-art-adjacent mascot style, thick dark 1-2 px "
      + "outline, flat cel shading, limited palette. The whole character must fit inside a "
      + "near-square bounding box, centered with small margins. Background: solid flat magenta "
      + "#FF00FF covering the entire background outside the character; the character itself must "
      + "not use magenta. No text, no shadows, no gradients, no scenery, no motion lines."
    switch self {
    case .idle:
      return identity
        + " Pose: standing relaxed, arms at the sides, calm neutral expression, gently breathing."
    case .running:
      return identity
        + " Pose: mid-stride running toward the right, arms and legs moving, energetic but the full body clearly visible."
    case .sleeping:
      return identity
        + " Pose: lying flat on the back, sleeping peacefully, eyes closed, limbs relaxed."
    case .happy:
      return identity + " Pose: happily reaching one hand forward and up in a wave, bright smile."
    }
  }
}

/// OpenAI 兼容的图像编辑服务配置。
///
/// 环境变量（全部可选，未配置 API Key 时 AI 提供者不可用，保持程序化生成）：
/// - `PETDESK_AI_POSE_API_KEY`：Bearer API Key（必填才启用）。
/// - `PETDESK_AI_POSE_BASE_URL`：OpenAI 兼容端点，默认 `https://api.openai.com/v1`；
///   可指向 RunComfy 等兼容服务。
/// - `PETDESK_AI_POSE_MODEL`：默认 `gpt-image-2`。
/// - `PETDESK_AI_POSE_SIZE`：默认 `1024x1024`。
/// - `PETDESK_AI_POSE_TIMEOUT`：秒，默认 300。
/// - `PETDESK_AI_POSE_EXTRA_POSES`：`1`/`true` 时额外生成跑步/躺平/伸手姿势（多次调用）。
public struct GPTImage2Config: Sendable {
  public var apiKey: String
  public var baseURL: URL
  public var model: String
  public var size: String
  public var timeout: TimeInterval
  public var extraPosesEnabled: Bool

  public init(
    apiKey: String,
    baseURL: URL,
    model: String = "gpt-image-2",
    size: String = "1024x1024",
    timeout: TimeInterval = 300,
    extraPosesEnabled: Bool = false
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.model = model
    self.size = size
    self.timeout = timeout
    self.extraPosesEnabled = extraPosesEnabled
  }

  public static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> GPTImage2Config? {
    // RunComfy CLI 传输尚未实现；显式选择时保持不可用并回退程序化方案。
    if environment["PETDESK_AI_POSE_TRANSPORT"] == "runcomfy" { return nil }
    guard let apiKey = environment["PETDESK_AI_POSE_API_KEY"], !apiKey.isEmpty else { return nil }

    let baseURL: URL
    if let raw = environment["PETDESK_AI_POSE_BASE_URL"], !raw.isEmpty, let url = URL(string: raw) {
      baseURL = url
    } else if let defaultURL = URL(string: "https://api.openai.com/v1") {
      baseURL = defaultURL
    } else {
      return nil
    }
    let model = environment["PETDESK_AI_POSE_MODEL"] ?? "gpt-image-2"
    let size = environment["PETDESK_AI_POSE_SIZE"] ?? "1024x1024"
    let timeout =
      environment["PETDESK_AI_POSE_TIMEOUT"].flatMap { TimeInterval($0) } ?? 300
    let extraPoses = ["1", "true", "yes"].contains(
      environment["PETDESK_AI_POSE_EXTRA_POSES"]?.lowercased() ?? ""
    )
    return GPTImage2Config(
      apiKey: apiKey,
      baseURL: baseURL,
      model: model,
      size: size,
      timeout: timeout,
      extraPosesEnabled: extraPoses
    )
  }
}

/// GPT Image 2 姿态提供者：通过 OpenAI 兼容的 `POST /images/edits` 编辑端点，
/// 基于用户头像生成规范姿势图，抠图成 192×208 单元，再交给程序化管线组装 8×8 精灵图。
/// 任何一步失败都会抛错，由调用方回退本地生成。
public struct GPTImage2Provider: AIPoseProvider {
  public let config: GPTImage2Config
  private let session: URLSession

  public init(config: GPTImage2Config, session: URLSession = .shared) {
    self.config = config
    self.session = session
  }

  public var supportsReferenceImage: Bool { true }

  /// 从进程环境读取配置；未配置 API Key 或选择了未实现的 CLI 传输时返回 nil。
  public static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> GPTImage2Provider? {
    GPTImage2Config.fromEnvironment(environment).map { GPTImage2Provider(config: $0) }
  }

  public func generateSpritesheet(from referenceImage: CGImage) async throws -> CGImage? {
    let poses: [AIPose] = config.extraPosesEnabled ? [.idle, .running, .sleeping, .happy] : [.idle]
    var rowCells: [AnimationRow: CGImage] = [:]
    for pose in poses {
      guard
        let generated = try await requestPose(pose, referenceImage: referenceImage),
        let cell = PoseCellProcessor.makeCell(from: generated)
      else {
        throw AIPoseError.invalidResponse
      }
      for row in AnimationRow.allCases where poseForRow(row) == pose {
        rowCells[row] = cell
      }
    }
    // 单姿势模式：其余行从 idle 单元派生（与 Codex Pet 参考管线一致）。
    if !config.extraPosesEnabled, let idleCell = rowCells[.idle] {
      for row in AnimationRow.allCases where rowCells[row] == nil {
        rowCells[row] = idleCell
      }
    }
    guard rowCells.count == AnimationRow.allCases.count else {
      throw AIPoseError.invalidResponse
    }
    return SpriteSheetGenerator.generate(fromRowCells: rowCells)
  }

  private func poseForRow(_ row: AnimationRow) -> AIPose {
    switch row {
    case .idle, .working, .drinking, .surprised: .idle
    case .walking, .running: .running
    case .sleeping: .sleeping
    case .happy: .happy
    }
  }

  private func requestPose(_ pose: AIPose, referenceImage: CGImage) async throws -> CGImage? {
    let url = config.baseURL.appendingPathComponent("images/edits")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = config.timeout
    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
    let boundary = "PetDesk-\(UUID().uuidString)"
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type"
    )
    guard let pngData = Self.pngData(from: referenceImage) else {
      throw AIPoseError.invalidReferenceImage
    }

    var body = Data()
    body.appendMultipartField(name: "model", value: config.model, boundary: boundary)
    body.appendMultipartField(name: "prompt", value: pose.prompt, boundary: boundary)
    body.appendMultipartField(name: "size", value: config.size, boundary: boundary)
    body.appendMultipartField(name: "response_format", value: "b64_json", boundary: boundary)
    body.appendMultipartFile(
      name: "image",
      filename: "reference.png",
      mimeType: "image/png",
      data: pngData,
      boundary: boundary
    )
    body.append(Data("--\(boundary)--\r\n".utf8))
    request.httpBody = body

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw AIPoseError.invalidResponse }
    guard http.statusCode == 200 else { throw AIPoseError.httpStatus(http.statusCode) }

    let payload: ImagesResponse
    do {
      payload = try JSONDecoder().decode(ImagesResponse.self, from: data)
    } catch {
      throw AIPoseError.decodingFailed
    }
    guard
      let b64 = payload.data.first?.b64JSON,
      let imageData = Data(base64Encoded: b64),
      let source = CGImageSourceCreateWithData(imageData as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw AIPoseError.decodingFailed
    }
    // 校验返回尺寸：抠底/色键阈值按 ~1024px 调参，过小的图会模糊。
    guard image.width >= 256, image.height >= 256 else {
      throw AIPoseError.decodingFailed
    }
    return image
  }

  private static func pngData(from image: CGImage) -> Data? {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }

  private struct ImagesResponse: Decodable {
    struct Image: Decodable {
      let b64JSON: String

      enum CodingKeys: String, CodingKey {
        case b64JSON = "b64_json"
      }
    }

    let data: [Image]
  }
}

extension Data {
  fileprivate mutating func appendMultipartField(name: String, value: String, boundary: String) {
    append(
      Data(
        ("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
          + "\(value)\r\n").utf8
      )
    )
  }

  fileprivate mutating func appendMultipartFile(
    name: String,
    filename: String,
    mimeType: String,
    data: Data,
    boundary: String
  ) {
    append(
      Data(
        ("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
          + "Content-Type: \(mimeType)\r\n\r\n").utf8
      )
    )
    append(data)
    append(Data("\r\n".utf8))
  }
}
