import Foundation

enum AppError: Error, LocalizedError, Equatable {
    case missingAPIKey, invalidAPIKey, keychain, invalidModel, invalidInput
    case unauthorized, rateLimited, network, timedOut, unavailable
    case invalidResponse, incompleteResponse, refused, storage
    case invalidExtensionID
    case missingFrenchVoice

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Ключ доступа не настроен. Добавьте его в настройках."
        case .invalidAPIKey: "Проверьте ключ: он не должен содержать пробелы или переносы строк."
        case .keychain: "Не удалось получить доступ к Связке ключей. Проверьте разрешение macOS и повторите попытку."
        case .invalidModel: "Введите корректное название модели в настройках."
        case .invalidInput: "Введите вопрос о французском или выражение длиной до 4 000 символов."
        case .unauthorized: "Ключ не принят или нет доступа к модели. Проверьте настройки подключения."
        case .rateLimited: "Достигнут лимит запросов или оплаты. Проверьте лимиты у поставщика и попробуйте позже."
        case .network: "Нет соединения с сервисом. Проверьте подключение к интернету."
        case .timedOut: "Сервис не успел ответить. Попробуйте ещё раз."
        case .unavailable: "Сервис временно недоступен. Попробуйте позже."
        case .invalidResponse: "Не удалось прочитать разбор. Попробуйте ещё раз или проверьте модель в настройках."
        case .incompleteResponse: "Разбор получился неполным. Сократите запрос и попробуйте ещё раз."
        case .refused: "Сервис не смог разобрать этот запрос. Попробуйте другое выражение."
        case .storage: "Не удалось сохранить данные на этом Mac. Проверьте свободное место и повторите попытку."
        case .invalidExtensionID: "ID расширения должен содержать 32 латинские буквы от a до p. Его можно найти на странице расширений Chrome."
        case .missingFrenchVoice: "Французский голос недоступен. Загрузите голос для французского языка Франции в настройках универсального доступа macOS."
        }
    }

    static func message(for error: Error) -> String {
        (error as? AppError)?.errorDescription ?? "Не удалось выполнить действие. Попробуйте ещё раз."
    }
}
