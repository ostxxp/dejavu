import SwiftUI

struct ClipboardResultView: View {
    let onClose: () -> Void
    let onHover: (Bool) -> Void
    let onResize: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        @Bindable var model = app.clipboardModel
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DéjàVu").font(.system(.headline, design: .serif))
                Text("Разбор скопированного").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Закрыть разбор скопированного")
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let text = model.candidate {
                        Text("Скопирован французский текст").font(.headline)
                        Text("\(text.count) символов").foregroundStyle(.secondary)
                        Text(String(text.prefix(240)) + (text.count > 240 ? "…" : ""))
                            .lineLimit(5).privacySensitive()
                        if !model.isLoading {
                            Text("Нажатие «Разобрать» отправит этот текст в OpenAI.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if model.isLoading { HStack { ProgressView().controlSize(.small); Text("Разбираем…") } }
                    if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                    if let result = model.result {
                        if model.fromCache { Text("Недавний ответ · без нового запроса").font(.caption).foregroundStyle(.secondary) }
                        AnalysisView(analysis: result, source: .clipboard, compact: !model.showsDetails)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if model.result != nil {
                    Button(model.showsDetails ? "Свернуть" : "Подробнее") { model.showsDetails.toggle() }
                } else if !model.isLoading {
                    Button("Разобрать") { model.analyze() }.buttonStyle(.borderedProminent)
                    Button("Игнорировать", action: onClose)
                } else { Button("Отменить", action: onClose) }
                Spacer()
                if model.errorMessage != nil {
                    Button("Настройки") { onClose(); app.openSettingsWindow?() }
                }
            }.controlSize(.small).padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onHover(perform: onHover)
        .onChange(of: model.showsDetails) { _, _ in onResize() }
    }
}
