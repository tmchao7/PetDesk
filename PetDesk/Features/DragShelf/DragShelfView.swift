import AppKit
import SwiftUI

/// 拖拽缓存托盘 UI：文件列表 + 拖出 / 分享 / 删除 / 清空 / 复制。
struct DragShelfView: View {
  @ObservedObject var environment: AppEnvironment

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // 顶部把手区（与 DragShelfPanel.dragHandleHeight 对应）：
      // 视觉提示 + 右侧关闭按钮。
      HStack {
        Spacer()
        Button {
          environment.shelfPanel?.dismissShelf()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("关闭托盘（⌘W）")
        .keyboardShortcut("w", modifiers: .command)
      }
      .frame(height: DragShelfPanel.dragHandleHeight)

      HStack {
        Label("暂存托盘", systemImage: "tray.full.fill")
          .font(.headline)
        Spacer()
        Button {
          copyAll()
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .help("复制全部文件")
        .disabled(environment.shelfItems.isEmpty)

        Button {
          environment.clearShelf()
        } label: {
          Image(systemName: "trash")
        }
        .help("清空托盘")
        .disabled(environment.shelfItems.isEmpty)
      }

      if environment.shelfItems.isEmpty {
        Spacer()
        VStack(spacing: 8) {
          Image(systemName: "tray.and.arrow.down")
            .font(.system(size: 32))
            .foregroundStyle(.secondary)
          Text("从 Finder 拖文件到这里暂存")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("可以拖入多个文件或整个文件夹")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        Spacer()
      } else {
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(environment.shelfItems, id: \.self) { path in
              shelfRow(path: path)
            }
          }
          .padding(.vertical, 2)
        }
      }

      HStack {
        Text("\(environment.shelfItems.count) 项")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("分享", systemImage: "square.and.arrow.up") {
          shareAll()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(environment.shelfItems.isEmpty)
      }
    }
    .padding(12)
    .frame(width: 300, height: 340)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    .onAppear {
      environment.auxiliaryWindowDidAppear()
    }
    .onDisappear {
      environment.auxiliaryWindowDidDisappear()
    }
  }

  private func shelfRow(path: String) -> some View {
    HStack(spacing: 8) {
      let icon = NSWorkspace.shared.icon(forFile: path)
      Image(nsImage: icon)
        .resizable()
        .frame(width: 24, height: 24)

      Text((path as NSString).lastPathComponent)
        .font(.system(size: 12))
        .lineLimit(1)

      Spacer()

      Button {
        environment.removeShelfItem(path)
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help("移除")
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    .onDrag {
      NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
    }
    .contextMenu {
      Button("复制路径") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
      }
    }
  }

  private func shareAll() {
    let urls = environment.shelfItems.map { URL(fileURLWithPath: $0) }
    let picker = NSSharingServicePicker(items: urls)
    if let window = NSApp.keyWindow {
      picker.show(
        relativeTo: NSRect(x: window.frame.midX, y: window.frame.minY + 40, width: 1, height: 1),
        of: window.contentView!, preferredEdge: .minY)
    }
  }

  private func copyAll() {
    let urls = environment.shelfItems.map { URL(fileURLWithPath: $0) }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects(urls as [NSURL])
  }
}
