import Foundation
import OSLog

public enum AppLog {
  public static let subsystem = "io.github.tmchao7.PetDesk"
  public static let app = Logger(subsystem: subsystem, category: "app")
  public static let window = Logger(subsystem: subsystem, category: "window")
  public static let focus = Logger(subsystem: subsystem, category: "focus")
  public static let avatar = Logger(subsystem: subsystem, category: "avatar")
}
