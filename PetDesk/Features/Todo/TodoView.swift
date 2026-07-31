import AppKit
import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct TodoView: View {
  @State private var items: [TodoItem] = []
  @State private var newItemTitle = ""
  @State private var store: TodoStore?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Label("今日待办", systemImage: "checklist")
          .font(.headline)
        Spacer()
        Text("\(incompleteCount) 项未完成")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(16)

      Divider()

      // Add new item
      HStack(spacing: 8) {
        TextField("添加待办事项...", text: $newItemTitle)
          .textFieldStyle(.roundedBorder)
          .onSubmit { addItem() }
        Button("添加", systemImage: "plus") { addItem() }
          .labelStyle(.iconOnly)
          .disabled(newItemTitle.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding(12)

      Divider()

      // Todo list
      if items.isEmpty {
        Spacer()
        Text("还没有待办事项")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
        Spacer()
      } else {
        List {
          ForEach($items) { $item in
            HStack(spacing: 10) {
              Button {
                item.isCompleted.toggle()
                persist()
              } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                  .font(.title3)
                  .foregroundStyle(item.isCompleted ? .green : .secondary)
              }
              .buttonStyle(.plain)

              Text(item.title)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .lineLimit(3)

              Spacer()

              Button {
                deleteItem(item)
              } label: {
                Image(systemName: "trash")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
              .opacity(0.6)
            }
            .padding(.vertical, 3)
          }
        }
        .listStyle(.plain)
      }
    }
    .frame(width: 340, height: 420)
    .task { await loadStore() }
    .onAppear {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
    }
    .onDisappear {
      NSApp.setActivationPolicy(.accessory)
    }
  }

  private var incompleteCount: Int {
    items.filter { !$0.isCompleted }.count
  }

  private func addItem() {
    let trimmed = newItemTitle.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    items.append(TodoItem(title: trimmed))
    newItemTitle = ""
    persist()
  }

  private func deleteItem(_ item: TodoItem) {
    items.removeAll { $0.id == item.id }
    persist()
  }

  private func persist() {
    guard let store else { return }
    Task { try? await store.save(items) }
  }

  private func loadStore() async {
    do {
      let store = try TodoStore()
      self.store = store
      items = await store.load()
    } catch {
      items = []
    }
  }
}
