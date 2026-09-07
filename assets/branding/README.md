# Иконка DéjàVu

`dejavu-icon.png` — исходный сгенерированный растр, общий для приложения и расширения. Создан встроенным инструментом imagegen; локальные ключи и API приложения для генерации не использовались.

Промпт:

> Use case: logo-brand. Generate one polished production app icon for DéjàVu, a warm and charming French learning macOS app and Chrome extension. Square 1024x1024 composition. A friendly sculptural cream speech bubble shaped like a soft rounded lowercase d / looping conversation, with two tiny expressive dark eyes and a subtle curved smile; one small floating sparkle. Rich muted lavender rounded-square tile, subtle tactile clay/soft enamel dimensional shading, luminous cream foreground, refined simple silhouette, premium macOS icon craft, legible even at 16px. Center the symbol large, generous but not excessive safe margin. Transparent outside the rounded-square tile, no external drop shadow, no text, no letters, no watermark, no presentation mockup. This exact single icon will be resized for both app and extension.

Производные размеры сделаны штатным `sips` без изменения рисунка. `iconutil` упаковывает macOS-иконку (16–1024 px) в `macos/DejavuApp/Resources/AppIcon.icns`. PNG 16, 32, 48 и 128 px находятся в `chrome-extension/icons/`; manifest использует их для расширения и кнопки панели инструментов.
