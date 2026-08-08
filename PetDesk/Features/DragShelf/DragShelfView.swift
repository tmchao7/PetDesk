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
              ShelfRowRepresentable(
                path: path,
                mode: environment.shelfDragOutMode,
                onRemove: { environment.removeShelfItem(path) }
              )
              .frame(height: 34)
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

      // 拖出方式：复制 / 移动。
      // 微信/QQ/邮件等外部 app 只接受复制（系统机制）；移动对 Finder 生效。
      Picker("拖出方式", selection: $environment.shelfDragOutMode) {
        Text("复制").tag(ShelfDragOutMode.copy)
        Text("移动").tag(ShelfDragOutMode.move)
      }
      .pickerStyle(.segmented)
      .controlSize(.small)
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

  private func shareAll() {
    let urls = environment.shelfItems.map { URL(fileURLWithPath: $0) }
    let picker = NSSharingServicePicker(items: urls)
    guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
    picker.show(
      relativeTo: NSRect(x: window.frame.midX, y: window.frame.minY + 40, width: 1, height: 1),
      of: contentView,
      preferredEdge: .minY)
  }

  private func copyAll() {
    let urls = environment.shelfItems.map { URL(fileURLWithPath: $0) }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects(urls as [NSURL])
  }
}
