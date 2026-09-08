import AppKit
import SwiftUI

struct BrowserBridgeSettings: View {
    @Environment(AppEnvironment.self) private var app
    @State private var extensionID = ""
    @State private var code = ""
    @State private var message: String?

    var body: some View {
        Section("Расширение Chrome") {
            LabeledContent("Подключение", value: app.browserBridge.status)
            LabeledContent("Адрес на этом Mac", value: "http://127.0.0.1:17389")
            TextField("ID расширения Chrome", text: $extensionID).autocorrectionDisabled()
            Text("Укажите ID со страницы расширений Chrome. Подключаться сможет только это расширение. До его установки оставьте подключение выключенным.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(app.settings.bridgeEnabled ? "Повторить подключение" : "Подключить расширение") {
                    code = ""; message = nil
                    app.browserBridge.configure(enabled: true, extensionID: extensionID)
                }
                Button("Отключить") {
                    code = ""; message = nil
                    app.browserBridge.configure(enabled: false, extensionID: app.settings.bridgeExtensionID)
                }.disabled(!app.settings.bridgeEnabled)
            }
            if app.browserBridge.isRunning {
                Button("Показать код подключения") {
                    do { code = try app.browserBridge.pairingCode(); message = nil }
                    catch { message = AppError.message(for: error) }
                }
                if !code.isEmpty {
                    Text(code).font(.system(.caption, design: .monospaced)).textSelection(.enabled).privacySensitive()
                    HStack {
                        Button("Скопировать код") {
                            let board = NSPasteboard.general
                            board.clearContents()
                            board.setString(code, forType: .string)
                            board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                            message = "Код скопирован. Вставьте его только в расширение DéjàVu."
                        }
                        Button("Скрыть код") { code = "" }
                    }
                }
                Button("Заменить код подключения") {
                    code = ""
                    do { try app.browserBridge.rotate(); message = "Прежний код больше не действует. Подключите расширение заново." }
                    catch { message = AppError.message(for: error) }
                }
            }
            Text("Подключение доступно только на этом Mac. Код разрешает расширению запрашивать ИИ-разбор и сохранять полученные выражения, а также читать сохранённые фразы и их перевод для функции «Мы уже встречались». Заметки не передаются. Ключ OpenAI в браузер не передаётся. Не публикуйте код и не вставляйте его на сайтах.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = app.browserBridge.errorMessage { Text(error).foregroundStyle(.red) }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { extensionID = app.settings.bridgeExtensionID }
        .onDisappear { code = "" }
        .onChange(of: app.browserBridge.isRunning) { _, running in if !running { code = "" } }
    }
}
