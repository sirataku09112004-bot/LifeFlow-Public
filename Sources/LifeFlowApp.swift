import SwiftUI

@main @MainActor struct LifeFlowApp: App {
    @StateObject private var store = FlowStore()
    @Environment(\.scenePhase) private var phase
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var body: some Scene {
        WindowGroup {
            TabView {
                FlowHome().tabItem { Label("ToDo", systemImage: "checklist") }
                FlowGoalsView().tabItem { Label("年間目標", systemImage: "target") }
            }.environmentObject(store)
                .tint(FlowTheme.action)
                .preferredColorScheme(.light)
                .onChange(of: phase) { if $0 == .active { opened() } }
                .onAppear { if phase == .active { opened() } }
                .onReceive(timer) { now in
                    if phase == .active && store.ready {
                        store.reminders.markOpened(now: now, clock: store.clock, tasks: store.data.tasks)
                        store.roll()
                    }
                }
        }
    }

    private func opened() {
        guard store.ready else { return }
        store.reminders.markOpened(now: Date(), clock: store.clock, tasks: store.data.tasks)
        store.roll()
        store.reminders.update(store.data.tasks)
    }
}
struct FlowHome: View {
    @EnvironmentObject var store: FlowStore
    @State private var favoritesOnly = false
    @State private var now = Date()
    @State private var showingHelp = false
    @State private var showingSearch = false
    @State private var categoryFilter: FlowCategoryFilter = .all
    @State private var showingProgress = false
    @State private var showingNotifications = false
    @State private var showingCategoryButtons = false
    @State private var editing: FlowTask?
    @State private var deleting: FlowTask?
    @State private var exporter = false
    @State private var importer = false
    @State private var document: BackupDocument?
    @State private var pending: Data?
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var taskList: FlowTaskList {
        FlowTaskList(tasks: store.data.tasks, query: "", category: categoryFilter, now: now, clock: store.clock)
    }
    var categories: [String] {
        let registered = store.data.registeredCategories
        let existing = FlowCategories.names(store.data.tasks.map(\.category) + store.data.history.map(\.category) + ["習慣"])
        return registered + existing.filter { !registered.contains($0) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("カテゴリ", selection: $categoryFilter) {
                        Text("すべて").tag(FlowCategoryFilter.all)
                        Text("未分類").tag(FlowCategoryFilter.uncategorized)
                        ForEach(categories, id: \.self) { Text($0).tag(FlowCategoryFilter.named($0)) }
                    }.pickerStyle(.menu)
                }.listRowBackground(FlowTheme.pale)
                if categoryFilter == .named("習慣") || store.data.tasks.contains(where: { $0.habitGoal != nil }) {
                    NavigationLink {
                        FlowHabitList()
                    } label: {
                        Label("習慣の記録", systemImage: "circle.grid.2x2")
                    }.listRowBackground(FlowTheme.pale)
                }
                if let label = store.undo.label {
                    Button { store.undoLast() } label: {
                        Label("直前の\(label)を取り消す", systemImage: "arrow.uturn.backward")
                    }.listRowBackground(FlowTheme.pale)
                }
                if favoritesOnly {
                    Section("お気に入り") {
                        if taskList.favorites.isEmpty { Text("お気に入りはありません").foregroundStyle(.secondary) }
                        ForEach(taskList.favorites) { taskRow($0) }
                    }
                } else {
                    Section("今日のToDo") {
                        if taskList.today.isEmpty { Text("今日の未完了ToDoはありません").foregroundStyle(.secondary) }
                        ForEach(taskList.today) { taskRow($0) }
                    }
                    let later = taskList.all.filter { $0.day > store.clock.today(now) }
                    if !later.isEmpty {
                        Section("今後の予定") {
                            ForEach(later) { taskRow($0) }
                        }
                    }
                }
            }
            .flowScreen()
            .navigationTitle(store.clock.label(store.clock.today(now)))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: categories) { names in
                if case .named(let name) = categoryFilter, !names.contains(name) { categoryFilter = .all }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingHelp = true } label: {
                        Image(systemName: "questionmark.circle").accessibilityLabel("使い方")
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { favoritesOnly.toggle() } label: {
                        Image(systemName: favoritesOnly ? "star.fill" : "star").foregroundStyle(FlowTheme.star)
                            .accessibilityLabel(favoritesOnly ? "すべてのToDoを表示" : "お気に入りを表示")
                    }
                    Menu {
                        Button("振り返り・履歴") { showingProgress = true }
                        Button("ToDoを検索") { showingSearch = true }
                        Button("通知設定") { showingNotifications = true }
                        Button("カテゴリを管理") { showingCategoryButtons = true }
                        Divider()
                        Button("JSONバックアップを書き出す") {
                            do { document = BackupDocument(bytes: try FlowStore.encode(store.data)); exporter = true }
                            catch { store.error = error.localizedDescription }
                        }.disabled(!store.ready)
                        Button("JSONバックアップから復元") { importer = true }
                    } label: { Image(systemName: "gearshape").accessibilityLabel("設定") }
                    Button { editing = FlowTask(title: "", day: store.clock.today(), category: selectedCategory, habitGoal: selectedCategory == "習慣" ? 3 : nil) } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(FlowTheme.accent)
                            .accessibilityLabel("ToDoを追加")
                    }.disabled(!store.ready)
                }
            }
            .sheet(isPresented: $showingHelp) { FlowHelp() }
            .sheet(isPresented: $showingSearch) { FlowTaskSearch() }
            .sheet(item: $editing) { task in TaskEditor(task: task).environmentObject(store) }
            .sheet(isPresented: $showingProgress) { FlowProgressView().environmentObject(store) }
            .sheet(isPresented: $showingNotifications) { FlowNotificationSettings(reminders: store.reminders).environmentObject(store) }
            .sheet(isPresented: $showingCategoryButtons) { FlowCategoryManager(names: store.data.registeredCategories).environmentObject(store) }
            .fileExporter(isPresented: $exporter, document: document, contentType: .json, defaultFilename: "LifeFlow-backup") { result in
                if case .failure(let e) = result { store.error = e.localizedDescription }
            }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 20 * 1024 * 1024 { throw FlowError.invalidBackup }
                    let bytes = try Data(contentsOf: url); _ = try FlowStore.decode(bytes); pending = bytes
                } catch { store.error = error.localizedDescription }
            }
            .alert("バックアップで全データを置き換えますか？", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("復元", role: .destructive) {
                    if let bytes = pending { do { try store.restore(bytes) } catch { store.error = error.localizedDescription } }
                    pending = nil
                }
                Button("キャンセル", role: .cancel) { pending = nil }
            } message: { Text("現在のToDo・履歴・年間目標・習慣記録をバックアップの内容で置き換えます。") }
            .alert("削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("削除", role: .destructive) { if let task = deleting { store.resolve(task, .deleted) }; deleting = nil }
                Button("キャンセル", role: .cancel) { deleting = nil }
            } message: { Text("削除したタスクのタイトルは履歴に残ります。繰り返しも停止します。") }
            .alert("確認", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
            .onReceive(timer) { now = $0 }
            .onAppear { now = Date() }
        }
    }
    private var selectedCategory: String? {
        if case .named(let name) = categoryFilter { return name }
        return nil
    }
    func taskRow(_ task: FlowTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { store.star(task) } label: { Image(systemName: task.favorite ? "star.fill" : "star")
                    .foregroundStyle(task.favorite ? FlowTheme.star : FlowTheme.ink)
                    .frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("お気に入り切替")
                Button { editing = task } label: {
                    VStack(alignment: .leading) {
                        Text(task.title).font(.headline).fixedSize(horizontal: false, vertical: true).foregroundStyle(task.originDay == nil ? FlowTheme.ink : Color.red)
                        Text(store.clock.label(task.day)).font(.caption).foregroundStyle(.secondary)
                        if let priority = task.priority, priority != .normal {
                            Label("優先度：\(priority.label)", systemImage: priority == .high ? "flag.fill" : "arrow.down")
                                .font(.caption).foregroundStyle(priority == .high ? Color.orange : Color.secondary)
                        }
                        if let rule = task.repeatRule, task.habitGoal == nil { Label(rule.label, systemImage: "repeat").font(.caption).foregroundStyle(.secondary) }
                        if let category = FlowCategories.normalized(task.category) { Label(category, systemImage: "folder").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !task.note.isEmpty { Text(task.note).font(.caption) }
            if !task.checklist.isEmpty {
                DisclosureGroup("サブタスク：\(task.completedSubtasks)/\(task.checklist.count)完了") {
                    ForEach(task.checklist) { item in
                        Button { store.toggleSubtask(taskID: task.id, subtaskID: item.id) } label: {
                            HStack(alignment: .top) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(item.isDone ? Color.green : Color.secondary)
                                Text(item.title).strikethrough(item.isDone).foregroundStyle(Color.primary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityLabel("\(item.title)、\(item.isDone ? "完了、未完了に戻す" : "未完了、完了にする")")
                    }
                }.font(.subheadline)
            }
            if let origin = task.originDay { Text("\(store.clock.label(origin)) から繰り越し").font(.caption).foregroundStyle(.red) }
            HStack(spacing: 16) {
                Button { store.resolve(task, .completed) } label: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(FlowTheme.action)
                        .frame(minWidth: 44, minHeight: 44).accessibilityLabel("達成")
                }.disabled(task.habitGoal != nil && task.day > store.clock.today(now))
                Button { store.resolve(task, .failed) } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(.red)
                        .frame(minWidth: 44, minHeight: 44).accessibilityLabel("失敗")
                }.disabled(task.habitGoal != nil && task.day > store.clock.today(now))
                Spacer()
                Button(role: .destructive) { deleting = task } label: {
                    Image(systemName: "trash").frame(minWidth: 44, minHeight: 44).accessibilityLabel("削除")
                }
            }.font(.title3)
        }
        .padding(.vertical, 4)
        .buttonStyle(.borderless)
        .listRowBackground(FlowTheme.card)
        .disabled(!store.ready)
    }
}
struct TaskEditor: View {
    @EnvironmentObject var store: FlowStore
    @Environment(\.dismiss) var dismiss
    @State var task: FlowTask
    @State private var hasEditedInput = false
    @State private var automaticDates = true
    @State private var lastAutoKey: String?
    @State private var details = false
    @State private var addingCategory = false
    @State private var categoryDraft = ""
    @State private var saveError: String?
    @State private var manuallySetDate = false
    @FocusState private var titleFocused: Bool
    var recognized: FlowInputResult? {
        hasEditedInput && automaticDates ? store.clock.parseInput(title: task.title, note: task.note, now: Date()) : nil
    }
    var savedTitle: String { (recognized?.title ?? task.title).trimmingCharacters(in: .whitespacesAndNewlines) }
    var savedNote: String { (recognized?.note ?? task.note).trimmingCharacters(in: .whitespacesAndNewlines) }
    func inferDueDate() {
        hasEditedInput = true
        let parsed = automaticDates ? store.clock.parseInput(title: task.title, note: task.note, now: Date()) : nil
        let key = parsed.map { "\($0.fromNote)-\($0.expression)-\($0.date.timeIntervalSince1970)" }
        if !manuallySetDate, key != lastAutoKey, let parsed = parsed { task.day = parsed.date }
        lastAutoKey = key
    }
    private var isNew: Bool { !store.data.tasks.contains { $0.id == task.id } }
    private var categories: [String] {
        let registered = store.data.registeredCategories
        let other = FlowCategories.names(store.data.tasks.map(\.category) + [task.category])
        return registered + other.filter { !registered.contains($0) }
    }
    private var canSave: Bool {
        store.ready && !savedTitle.isEmpty && savedTitle.count <= 1000 && savedNote.count <= 20000 &&
        !task.checklist.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.title.count > 200 }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タスク名", text: $task.title)
                        .submitLabel(.done).focused($titleFocused)
                        .onSubmit(save)
                    Menu {
                        Button("未分類") { task.category = nil; task.habitGoal = nil }
                        Button("習慣") { task.category = "習慣"; task.habitGoal = task.habitGoal ?? 3 }
                        ForEach(categories.filter { $0 != "習慣" }, id: \.self) { name in
                            Button(name) { task.category = name; task.habitGoal = nil }
                        }
                        Button("新しいカテゴリを入力") { addingCategory = true }
                    } label: {
                        Label(task.category ?? "カテゴリを選択", systemImage: "folder")
                            .multilineTextAlignment(.leading)
                    }
                    if let parsed = recognized, !manuallySetDate {
                        Label(store.clock.label(parsed.date), systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("詳細設定", isExpanded: $details) { detailFields }
                if let saveError { Text(saveError).foregroundStyle(.red) }
            }
            .flowScreen()
            .onChange(of: task.title) { _ in inferDueDate() }
            .onChange(of: task.note) { _ in inferDueDate() }
            .onChange(of: automaticDates) { _ in inferDueDate() }
            .onAppear { if isNew { titleFocused = true } }
            .alert("新しいカテゴリ", isPresented: $addingCategory) {
                TextField("名前（40文字以内）", text: $categoryDraft)
                Button("選択") {
                    if let name = FlowCategories.normalized(categoryDraft), name.count <= 40 {
                        task.category = name
                        task.habitGoal = name == "習慣" ? task.habitGoal ?? 3 : nil
                    }
                    categoryDraft = ""
                }
                Button("キャンセル", role: .cancel) { categoryDraft = "" }
            }
            .navigationTitle(isNew ? "ToDoを追加" : "ToDoを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!canSave) }
            }
        }
    }
    private var detailFields: some View {
        Group {
            TextField("メモ", text: $task.note, axis: .vertical)
            Toggle("文章の日付を使う", isOn: $automaticDates)
            DatePicker("予定日", selection: Binding(get: { task.day }, set: {
                task.day = $0
                manuallySetDate = true
            }), displayedComponents: .date)
            Picker("優先度", selection: Binding(get: { task.priority ?? .normal }, set: { task.priority = $0 == .normal ? nil : $0 })) {
                ForEach(FlowPriority.allCases) { Text($0.label).tag($0) }
            }
            Toggle("お気に入り", isOn: $task.favorite)
            Toggle("このToDoを通知する", isOn: Binding(get: { task.muteReminder != true }, set: { task.muteReminder = $0 ? nil : true }))
            if task.habitGoal != nil {
                Stepper("週の目標：\(task.habitGoal ?? 3)回", value: Binding(get: { task.habitGoal ?? 3 }, set: { task.habitGoal = $0 }), in: 1...7)
            } else {
                Picker("繰り返し", selection: $task.repeatRule) {
                    Text("なし").tag(Optional<FlowRepeat>.none)
                    ForEach(FlowRepeat.allCases) { Text($0.label).tag(Optional($0)) }
                }
            }
            FlowChecklistEditor(items: $task.checklist)
        }
    }
    private func save() {
        guard canSave else { return }
        var candidate = task
        let previous = store.data.tasks.first { $0.id == candidate.id }
        if automaticDates, previous?.title != candidate.title || previous?.note != candidate.note,
           let parsed = store.clock.parseInput(title: candidate.title, note: candidate.note, now: Date()) {
            let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            candidate.title = title
            candidate.note = parsed.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !manuallySetDate { candidate.day = parsed.date }
        } else {
            candidate.title = savedTitle
            candidate.note = savedNote
        }
        candidate.category = FlowCategories.normalized(candidate.category)
        candidate.checklist = candidate.checklist.map {
            var clean = $0
            clean.title = clean.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean
        }
        candidate.day = store.clock.day(candidate.day)
        if previous?.repeatRule != candidate.repeatRule || previous?.day != candidate.day {
            candidate.repeatAnchorDay = candidate.repeatRule.map { _ in store.clock.calendar.component(.day, from: candidate.day) }
            candidate.repeatAnchorWeekday = candidate.repeatRule.map { _ in store.clock.calendar.component(.weekday, from: candidate.day) }
        }
        if store.save(candidate) { dismiss() }
        else { saveError = store.error }
    }
}
