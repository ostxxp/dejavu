import SwiftUI

struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var errorMessage: String?
    private let titles = ["Французский рядом", "Подключение ИИ", "Вы выбираете, когда учиться"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("DéjàVu").font(.system(.largeTitle, design: .serif))
                Spacer()
                Button("Пропустить") { finish(settings: false) }.keyboardShortcut(.cancelAction)
            }
            Text(titles[page]).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Group {
                switch page {
                case 0:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Понимайте французские выражения, сохраняйте полезное и пробуйте короткие разговоры.")
                        Label("Выражение или вопрос — на главной", systemImage: "text.bubble")
                        Label("Быстрый помощник в любом приложении — ⌘⇧F", systemImage: "command")
                        Label("Ваши фразы — в общем словаре на этом Mac", systemImage: "bookmark")
                    }
                case 1:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Для разбора нужен ваш ключ OpenAI. Добавьте его в разделе «Настройки → Ключ доступа», затем нажмите «Проверить подключение».")
                        Label("Ключ хранится в Связке ключей macOS", systemImage: "lock.shield")
                        Text("Для запросов нужен доступ к API в вашем аккаунте OpenAI. Проверка подключения отправляет короткий запрос в выбранную модель.")
                            .foregroundStyle(.secondary)
                        Text("Можно открыть приложение без ключа и настроить подключение позже.")
                    }
                default:
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Разбор скопированного — включается отдельно", systemImage: "doc.on.clipboard")
                        Label("Chrome — отдельное расширение с локальным подключением", systemImage: "globe")
                        Label("Мини-диалоги — по вашему расписанию или вручную", systemImage: "bubble.left.and.bubble.right")
                        Label("Микрофон — только после нажатия кнопки", systemImage: "mic")
                        Text("Все дополнительные функции необязательны. Этот экран не включает их и не запрашивает разрешений. Перед отправкой в ИИ проверяйте выбранный текст.")
                            .foregroundStyle(.secondary)
                    }
                }
            }.frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
                .id(page).transition(.opacity)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            HStack {
                Text("\(page + 1) из 3").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if page > 0 { Button("Назад") { move(-1) } }
                if page < 2 {
                    Button("Далее") { move(1) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("Открыть приложение") { finish(settings: false) }
                    Button("Настроить ИИ") { finish(settings: true) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }.padding(32).frame(width: 570).background(.background)
    }
    private func move(_ delta: Int) { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { page += delta } }
    private func finish(settings: Bool) {
        do {
            try app.settings.completeWelcome()
            app.showWelcome = false
            if settings { app.section = .settings }
        } catch { errorMessage = AppError.message(for: error) }
    }
}
