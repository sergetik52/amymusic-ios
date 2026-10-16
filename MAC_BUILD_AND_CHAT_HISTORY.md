# AmyMusic iOS 26 (Swift 6 + Liquid Glass) — Полная история чата, Архитектура и Инструкция по сборке на Mac

Этот файл содержит **всю историю нашей разработки, полный архитектурный разбор оригинального проекта AmyMusic, описание всех переписанных Swift-файлов и пошаговую инструкцию для сборки на macOS в Xcode 26**. Папка `ios/` полностью автономна — достаточно перенести её (или запушить через Git) на ваш Mac.

---

## 1. Быстрый старт на Mac (за 1 минуту)

### Вариант А: Автоматический скрипт (Рекомендуется)
Откройте **Терминал (Terminal)** на Mac, перейдите в папку `ios` и запустите скрипт:

```bash
cd /путь/к/amymusic/ios
chmod +x setup_and_open_mac.sh
./setup_and_open_mac.sh
```
Скрипт сам проверит наличие `xcodegen`, сгенерирует `AmyMusic.xcodeproj` со всеми таргетами (`AmyMusic` + расширение `AmyMusicWidget` для Dynamic Island) и откроет проект в **Xcode 26**.

### Вариант Б: Вручную через Терминал
```bash
cd /путь/к/amymusic/ios
brew install xcodegen
xcodegen generate
open AmyMusic.xcodeproj
```

### Настройка подписи (Signing) перед запуском на реальном iPhone
1. В левой панели Xcode выберите корневой проект **AmyMusic**.
2. Перейдите на вкладку **Signing & Capabilities**.
3. Для таргета **AmyMusic** (и **AmyMusicWidget**) поставьте галочку **Automatically manage signing** и выберите ваш **Team** (ваш Apple ID).
4. При необходимости измените `Bundle Identifier` (например, `com.yourname.amymusic` и `com.yourname.amymusic.widget`).
5. Выберите сверху симулятор **iPhone 17 Pro (iOS 26.0)** или подключённый iPhone и нажмите **`⌘ + R` (Run)**.

---

## 2. Сводка изученной архитектуры AmyMusic и переноса на Swift (iOS 26)

### 2.1. Мобильная эргономика и дизайн (1-в-1 с `MobileLayout.jsx`, `MobileMiniPlayer.jsx` и `main.css`)
* **Две раздельные парящие стеклянные панели снизу (`.mobile-floating-controls`)**:
  1. **`PhoneLiquidGlassMiniPlayer` (`Views/RootTabView.swift`)**:
     * Высота `64pt`, радиус скругления `20pt`, внутренние отступы `6pt 8pt 6pt 6pt`.
     * Слева: обложка `52×52pt` со скруглением `14pt`, заголовок `14pt Bold` (`#FFFFFF`), артист `12pt` (`#A1A1AA`).
     * Справа: круглая белая кнопка Play/Pause `48×48pt` с чёрной иконкой (`#0B0B0D`) и пружинящим откликом `scale(0.92)`.
     * **Жесты**: горизонтальный свайп влево/вправо (`deltaX >= 52pt`) переключает трек (`previous()` / `next()`), свайп вверх или тап открывает полноэкранный плеер.
     * Поддерживает 3 стиля из настроек: `Liquid Glass`, `Волновой` (72 детерминированные полосы волны) и `Классический` (с быстрыми кнопками караоке и эквалайзера).
  2. **`PhoneFloatingNavDock` (`Views/RootTabView.swift`)**:
     * Отступ `10pt` под мини-плеером, высота `64pt`, скругление `26pt`.
     * **Ровно 3 вкладки только с иконками (без текста)**: «Моя волна», «Чарты», «Коллекция».
     * Активная иконка окрашена в `#A855F7`, под ней плавно перемещается капсула (`#36363C <-> #48484F` `matchedGeometryEffect`) с диагональным бликом (`sheenOffset`).
  3. **Автоскрытие при открытии клавиатуры (`.is-keyboard-open`)**:
     * При фокусе на поиске и появлении экранной клавиатуры iPhone обе нижние панели плавно уезжают вниз.

* **Встроенный поиск внутри шапки «Моей волны» (`.mobile-wave-search-slot`)**:
  * В `Views/HomeWaveView.swift` (`PhoneHomeHeroWithEmbeddedSearch`) строка поиска встроена в верхнюю часть `280pt` Hero-баннера (`top: 8pt`) рядом с круглой кнопкой профиля (`44×44pt`).
  * При вводе запроса прямо под строкой поиска раскрываются горизонтальные чипы фильтров (`Все`, `Треки`, `Плейлисты`, `Альбомы`, `Артисты`) и выпадающий список результатов высотой до `390pt` (`~52vh`).

* **Пропорции Hero-баннера (`.home-hero`)**:
  * Высота `280pt`, отступ сверху `112pt`; слева квадратная обложка `124×124pt` (`cornerRadius: 18pt`) с быстрой кнопкой перехода в полноэкранный **3D ДНК-визуализатор**, по центру (`height: 124pt`, `margin-left: 16pt`) двухстрочный заголовок `Моя\nволна` + кнопка `НАСТРОИТЬ` (`WaveSeedModalView`), справа — белая кнопка Play `56×56pt`.

* **Горизонтальные снэп-пейджеры по 5 треков**:
  * В «Коллекции» (`Views/CollectionView.swift`) и в профиле артиста (`Views/ArtistAndAlbumView.swift`) списки треков сгруппированы в страницы по 5 треков с горизонтальным скроллом `scrollTargetBehavior(.viewAligned)`.

---

### 2.2. Аудио-движок, DSP и системные API Apple (`Audio/`)
* **Двойной движок `AVPlayer` и Crossfade (1–12 сек) (`Audio/AudioPlayerManager.swift`)**:
  * Использует массив из двух `AVPlayer` (`activeEngineIdx = 0 | 1`) с нативной поддержкой HLS (`.m3u8`) и Progressive MP3/AAC потоков.
  * За `crossfadeSeconds` (по умолчанию 4 сек) до окончания трека запускает второй `AVPlayer` и плавно сводит громкость первого к `0`, а второго к `1`.
  * Фоново предзагружает потоковые ссылки для следующих 4 треков очереди (`prefetchUpcomingTracks()`).
* **10-полосный эквалайзер (`AVAudioUnitEQ`)**:
  * Частоты: `60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000 Hz`, диапазон `[-12 dB, +12 dB]`.
  * Все 9 пресетов из оригинала: `Сброс`, `Усиление баса`, `Вокал / Речь`, `Рок`, `Поп`, `Электроника`, `Акустика`, `Джаз`, `Высокие частоты`.
* **Извлечение палитры обложки (`Theme/LiquidGlassTheme.swift` -> `PaletteExtractor`)**:
  * Точный порт `extractPaletteFromImage`: рисует обложку в `48×48` `CGContext`, отбрасывает прозрачные и слишком тёмные/светлые пиксели, квантует RGB с шагом `24` и ранжирует кластеры по формуле `sqrt(count) * (0.62 + colorfulness * 1.75) * (0.45 + midBrightness * 0.9)`, формируя 4 цвета (`base`, `line`, `bright`, `shadow`).
* **Системная интеграция iOS 26**:
  * `MPNowPlayingInfoCenter` и `MPRemoteCommandCenter` — экран блокировки, Пункт управления, AirPods, Apple Watch, CarPlay (включая перемотку и кнопку лайка).
  * `ActivityKit` (`Audio/AmyMusicLiveActivity.swift` и `AmyMusicWidget/AmyMusicWidgetLiveActivity.swift`) — **Dynamic Island & Live Activity** (нативный аналог вашего десктопного `GameOverlay.jsx`).
  * `AVRoutePickerView` — нативная кнопка выбора AirPlay 2 / Bluetooth аудиоустройств в полном плеере.

---

### 2.3. Сетевые сервисы и алгоритмы волны (`Services/`)
1. **`Services/SoundCloudService.swift`**:
   * Работает напрямую с `https://api-v2.soundcloud.com` (Client ID `yNSW5UvBmb1A5j7qPUtIMuB9Itx3jsOC` с возможностью смены в Настройках -> Интеграции).
   * Нормализация метаданных: очистка `[Official Audio]`, `(Lyrics)`, `[HD]`, разбиение `Artist - Title` и `feat.` / `×` на массив `ArtistRef`.
   * Выбор потока под качество `192 / 256 / 320 / 1411 kbps 💎` и автоматический обход 30-секундных Go+ сниппетов (поиск полной версии трека).
   * **Алгоритм 1 — Personal Wave (`getPersonalWaveTracks`)**: веса артистов и жанров с учётом свежести (`recency`), параллельная загрузка `/tracks/{id}/related` и поисковых выборок, фильтрация дизлайков и диверсификация (`diversifyWaveTracks`).
   * **Алгоритм 2 — 5D TrackDNA (`getTrackWaveTracks`)**: оценка по 5 измерениям (Genre Family до +50, Mood Palette до +30, Energy Class до +25, Popularity Band до +20, логарифм прослушиваний до +18).
2. **`Services/YandexMusicService.swift`**:
   * Загрузка **Топ-100 Чарта** (`/landing3/chart`) с позицией, дельтой (`up`, `down`, `new`, `same`), числом слушателей (`🎧`) и `derivedColors`.
   * Станции **Ротора** (`/rotor/station/.../tracks`).
   * **Импорт плейлистов и альбомов по ссылке** (`importPlaylistFromUrl`) с живым прогресс-баром и резолвом аудиопотоков через SoundCloud.
3. **`Services/LyricsService.swift`**:
   * Параллельный поиск текстов в **LRCLib**, **NetEase Cloud Music** и **Genius** (включая парсинг аннотаций `/api/referents`).
   * Пословная интерполяция таймингов для караоке-режима **Braccato / По словам**, 4 визуальных стиля (`Размытие`, `Масштаб`, `Обычный`, `Braccato`), 4 размера шрифта и индивидуальный сдвиг тайминга (`-2000 мс ... +2000 мс`).

---

## 3. Полное дерево файлов проекта `ios/`

```text
ios/
├── MAC_BUILD_AND_CHAT_HISTORY.md       # Этот документ (история чата + инструкция для Mac)
├── setup_and_open_mac.sh               # Скрипт авто-генерации .xcodeproj и запуска Xcode 26
├── project.yml                         # Спецификация XcodeGen для iOS 26.0
├── Package.swift                       # Манифест Swift 6 Package
├── design-preview/                     # Сохранённые визуальные рендеры и интерактивный HTML-макет
│   ├── amymusic_ios26_interactive_preview.html
│   ├── amymusic_wave_tab.jpg
│   └── amymusic_full_player.jpg
├── AmyMusic/
│   ├── AmyMusicApp.swift               # Точка входа @main
│   ├── Info.plist                      # Конфигурация фонового аудио и Live Activities
│   ├── Models/
│   │   └── Models.swift                # Все структуры данных, пресеты эквалайзера и тем
│   ├── Theme/
│   │   └── LiquidGlassTheme.swift      # Модификаторы iOS 26 Liquid Glass, PaletteExtractor, FluidMesh и 3D ДНК
│   ├── Services/
│   │   ├── SoundCloudService.swift     # SoundCloud v2 API, Personal Wave и 5D TrackDNA
│   │   ├── YandexMusicService.swift    # Яндекс Музыка Топ-100, Ротор и импорт плейлистов
│   │   └── LyricsService.swift         # LRCLib, NetEase, Genius + LRC парсер
│   ├── Audio/
│   │   ├── AudioPlayerManager.swift    # 2x AVPlayer Crossfade, 10-band EQ, очередь и MPNowPlaying
│   │   └── AmyMusicLiveActivity.swift  # Dynamic Island контроллер и плавающее мини-караоке
│   └── Views/
│       ├── RootTabView.swift           # Парящий мини-плеер (64pt) + 3-иконочный док (64pt)
│       ├── HomeWaveView.swift          # Моя волна, встроенный поиск в 280pt Hero, 3D ДНК экран
│       ├── TrendsChartsView.swift      # Чарты Топ-100 с золотым/серебряным/бронзовым свечением
│       ├── CollectionView.swift        # Коллекция, снэп-пейджер по 5 треков, импорт плейлистов
│       ├── ArtistAndAlbumView.swift    # Профиль артиста и экран альбома/плейлиста
│       ├── FullPlayerOverlayView.swift # Полный плеер, караоке (4 стиля), очередь и эквалайзер
│       └── SettingsAndProfileView.swift# Настройки, кроппер аватара, 6 тем, кеш и интеграции
└── AmyMusicWidget/
    └── AmyMusicWidgetLiveActivity.swift# Таргет виджета Dynamic Island и экрана блокировки iOS 26
```
