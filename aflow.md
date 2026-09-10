# Execution Flow & Architectural Sequence Map: Climate Storyteller

This document provides a **diagrammatic visual map** of execution flow, entry points, function call hierarchies, state propagation, and historical AI code changes in **Climate Storyteller**.

---

## 1. Complete System Architecture Overview

```mermaid
flowchart TB
    subgraph Boot ["1. Bootstrapping Layer"]
        A["main() [lib/main.dart]"]
        DI["DI Locator [lib/core/di/injection_container.dart]"]
    end

    subgraph CoreServices ["2. Singleton Service Layer"]
        LS["LanguageService\n(Localization & Stream)"]
        TS["ThemeService\n(Light/Dark & Stream)"]
        CRS["CustomRegionService\n(SharedPreferences)"]
        LGS["LgService\n(SSH / SFTP / Rig State)"]
        CDS["ClimateDataService\n(IPCC Data / KML Generation)"]
        NS["NarratorService\n(Gemini API & Flutter TTS)"]
        CAS["ClimateAlertService\n(Open-Meteo API Alerts)"]
    end

    subgraph UILayer ["3. User Interface Layer"]
        App["ClimateStorytellerApp"]
        Router["onGenerateRoute"]
        Onboarding["OnboardingScreen"]
        Shell["ShellScreen (IndexedStack & Drawer)"]

        subgraph NavigationTabs ["Tabs in ShellScreen"]
            Tab0["Tab 0: ExploreScreen\n(Map, Regions, Year Slider)"]
            Tab1["Tab 1: TimelineScreen\n(1900 -> 2026 -> 2100)"]
            Tab2["Tab 2: NarratorScreen\n(Gemini Prompt & TTS Wave)"]
            Tab3["Tab 3: StoryModeScreen\n(Automated Tour Chapters)"]
            Tab4["Tab 4: SettingsScreen\n(SSH Config & Rig Control)"]
        end

        subgraph ModalsScreens ["Sub-Screens & Modals"]
            RegionDetail["RegionDetailScreen"]
            AddRegion["AddRegionScreen"]
            AlertBanner["ClimateAlertBanner"]
        end
    end

    subgraph HardwareAPIs ["4. External Hardware & API Infrastructure"]
        LG1["Master Screen (LG1)\n/tmp/query.txt (FlyTo)"]
        LGScreens["Slave Screens (LG2..LGn)\n/var/www/html/kml/slave_X.kml"]
        GeminiAPI["Google Gemini 1.5 Flash API"]
        TTSEngine["Device TTS Engine"]
        WeatherAPI["Open-Meteo / NOAA / NASA GIBS"]
    end

    %% Boot Relationships
    A -->|1. Init Services| DI
    DI --> LS & TS & CRS & LGS & CDS & NS & CAS
    A -->|2. runApp()| App
    App --> Router
    Router -->|Initial Route| Onboarding
    Router -->|Main Flow| Shell

    %% UI Shell & Tabs
    Shell --> Tab0 & Tab1 & Tab2 & Tab3 & Tab4
    Tab0 --> RegionDetail & AddRegion & AlertBanner

    %% UI to Service Calls
    Tab0 -->|Select Region / Year| CDS
    Tab0 -->|Orbit / FlyTo Controls| LGS
    Tab1 -->|Select Era| CDS
    Tab2 -->|Generate Story| NS
    Tab3 -->|Next Chapter| NS & CDS
    Tab4 -->|Connect SSH| LGS
    AlertBanner -->|Fetch Live Weather| CAS

    %% Service to Hardware/API Connections
    CDS -->|Generate Overlay| LGS
    LGS -->|SSH command| LG1
    LGS -->|SFTP upload| LGScreens
    NS -->|HTTP POST| GeminiAPI
    NS -->|Audio Stream| TTSEngine
    CAS -->|HTTP GET| WeatherAPI
```

---

## 2. Bootstrapping & App Lifecycle Sequence

```mermaid
sequenceDiagram
    autonumber
    actor OS as Operating System
    participant Main as main() [lib/main.dart]
    participant DI as DI Locator
    participant Lang as LanguageService
    participant Theme as ThemeService
    participant CustomReg as CustomRegionService
    participant Flutter as Flutter Framework
    participant App as ClimateStorytellerApp

    OS->>Main: Launch Application
    Main->>Flutter: WidgetsFlutterBinding.ensureInitialized()
    Main->>DI: Read Singletons
    Main->>Lang: await DI.languageService.init()
    Lang-->>Main: Loaded stored language (e.g. 'en')
    Main->>Theme: await DI.themeService.init()
    Theme-->>Main: Loaded theme mode (Light/Dark)
    Main->>CustomReg: await DI.customRegionService.init()
    CustomReg-->>Main: Loaded custom user regions
    Main->>Flutter: SystemChrome.setPreferredOrientations([portraitUp])
    Main->>Flutter: runApp(const ClimateStorytellerApp())
    Flutter->>App: build(context)
    App->>Theme: Listen to DI.themeService.themeStream
    App->>Flutter: MaterialApp(initialRoute: AppRoutes.onboarding)
```

---

## 3. UI Navigation & Tab State Diagram

```mermaid
stateDiagram-v2
    [*] --> OnboardingScreen : App Launch

    OnboardingScreen --> ShellScreen : Tap "Get Started" / Skip

    state ShellScreen {
        [*] --> ExploreTab : Default Tab (0)

        state ExploreTab {
            [*] --> RegionMap
            RegionMap --> RegionDetailScreen : Tap Region Card
            RegionMap --> AddRegionScreen : Tap "+ Add Region"
            RegionMap --> ClimateYearSlider : Drag Year Slider
        }

        state TimelineTab {
            [*] --> EraSelection
            EraSelection --> PreIndustrial_1900 : Select 1900
            EraSelection --> PresentDay_2026 : Select 2026
            EraSelection --> Projected_2100 : Select 2100
        }

        state NarratorTab {
            [*] --> InputPrompt
            InputPrompt --> GeneratingStory : Tap "Generate Narration"
            GeneratingStory --> PlayingAudioTTS : Gemini Response Received
            PlayingAudioTTS --> InputPrompt : Audio Completed / Stopped
        }

        state StoryModeTab {
            [*] --> ChapterOverview
            ChapterOverview --> PlayingChapterTour : Tap "Play Tour"
            PlayingChapterTour --> ChapterOverview : Tour Ended
        }

        state SettingsTab {
            [*] --> SSHConfiguration
            SSHConfiguration --> TestingConnection : Tap "Connect to LG"
            TestingConnection --> Connected : Connection Successful
            TestingConnection --> Disconnected : Error / Timeout
            Connected --> ClearedKML : Tap "Clear KML"
        }
    }

    ShellScreen --> DrawerMenu : Tap Top-Right Menu (3 lines)
    DrawerMenu --> ShellScreen : Select Tab / Close Drawer
```

---

## 4. Function Call Chain Diagrams by Feature

### Feature Flow 1: Connecting to Liquid Galaxy Rig

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant SettingsUI as SettingsScreen [lib/features/explore/settings_screen.dart]
    participant SecureStorage as SecureStorageService
    participant DI as DI Locator
    participant LGService as LgService [lib/features/lg_connection/lg_service.dart]
    participant SSH as SSHClient (dartssh2)
    participant SFTP as SFTPClient
    participant LGRig as Liquid Galaxy Hardware

    User->>SettingsUI: Input IP, Port, Username, Password, Screen Count
    User->>SettingsUI: Tap "Connect to Liquid Galaxy"
    SettingsUI->>SecureStorage: saveLgCredentials(ip, port, user, pass, screenCount)
    SettingsUI->>DI: DI.lgService.connect(...)
    DI->>LGService: connect(ipAddress, port, username, password, screenCount)
    LGService->>SSH: Socket.connect(ipAddress, port)
    SSH-->>LGService: Socket connected
    LGService->>SSH: SSHClient(socket, username, onPassword: pass)
    SSH-->>LGService: Authenticated SSH Session
    LGService->>SSH: client.sftp()
    SSH-->>SFTP: SFTP session initialized
    LGService->>LGService: _startKeepaliveTimer() [Pings rig every 15s]
    LGService->>LGService: sendLogoOverlay() [Pushes logo KML to Left-Most screen]
    LGService->>SFTP: Upload `/var/www/html/kml/slave_X.kml`
    LGService->>SSH: execute("echo 'http://lg1:81/kml/slave_X.kml' > /var/www/html/kmls.txt")
    LGService->>LGService: updateState(isConnected: true)
    LGService-->>SettingsUI: StreamBuilder receives updated LGRigState (Green status)
```

---

### Feature Flow 2: Selecting a Region & Triggering 3D Visualizer

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant MapUI as ExploreScreen [lib/features/explore/explore_screen.dart]
    participant CDS as ClimateDataService [lib/features/climate_data/climate_data_service.dart]
    participant Overlays as LgOverlays [lib/features/lg_connection/lg_overlays.dart]
    participant LGService as LgService [lib/features/lg_connection/lg_service.dart]
    participant MasterLG as Master Screen (LG1)
    participant SlaveLG as Slave Screens (LG2..LGn)

    User->>MapUI: Tap Region Card (e.g. "Amazon Rainforest")
    MapUI->>CDS: visualizeRegionOnLG(region)

    par Fly Camera to Coordinates
        CDS->>LGService: flyTo(latitude, longitude, range, tilt: 35.0, heading: 15.0)
        LGService->>MasterLG: SSH execute("echo 'flytoview=...' > /tmp/query.txt")
    and Generate & Send 3D Extruded KML Overlay
        CDS->>Overlays: buildRegionKml(region, screenRole)
        Overlays-->>CDS: Returns KML XML string with 3D Polygons & Balloons
        CDS->>LGService: sendKmlToSlave(slaveNumber, kmlContent, kmlName)
        LGService->>SlaveLG: SFTP upload KML to `/var/www/html/kml/slave_X.kml`
        LGService->>MasterLG: SSH execute("echo 'http://lg1:81/kml/slave_X.kml' > /var/www/html/kmls.txt")
    end

    MapUI->>MapUI: Navigator.pushNamed(AppRoutes.regionDetail, arguments: region)
```

---

### Feature Flow 3: Climate Year Slider & Real-Time Data Propagation

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Slider as ClimateYearSlider [lib/features/explore/climate_year_slider.dart]
    participant CDS as ClimateDataService
    participant IPCC as IpccData [lib/features/climate_data/ipcc_data.dart]
    participant LGService as LgService
    participant Rig as Liquid Galaxy Right-Most Screen

    User->>Slider: Drag slider from 1900 to 2070
    Slider->>Slider: setState(() => _selectedYear = 2070)
    Slider->>CDS: visualizeYearOnLG(selectedYear: 2070, activeRegion)
    CDS->>IPCC: getIpccDataForYear(region, 2070)
    IPCC-->>CDS: Returns IpccData(tempAnomaly: +2.4°C, seaLevelRise: +0.42m, co2Ppm: 580)
    CDS->>LGService: sendYearOverlayToLG(year: 2070, data)
    LGService->>Rig: SFTP Upload Legend Balloon KML to Right-Most Screen
    LGService->>Rig: Refresh `/var/www/html/kmls.txt`
```

---

### Feature Flow 4: Gemini AI Story Generation & Synchronized TTS Playback

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant NarratorUI as NarratorScreen [lib/features/narrator/narrator_screen.dart]
    participant NS as NarratorService [lib/features/narrator/narrator_service.dart]
    participant Storage as SecureStorageService
    participant Gemini as Google Gemini REST API (gemini-1.5-flash)
    participant TTS as FlutterTts Engine
    participant LGService as LgService

    User->>NarratorUI: Select Region + Era + Style -> Tap "Generate AI Story"
    NarratorUI->>NS: generateNarration(region, era, style, customPrompt)
    NS->>Storage: getGeminiApiKey()
    Storage-->>NS: Returns API Key
    NS->>Gemini: POST https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent
    Gemini-->>NS: Returns JSON (Story text + Location coordinates array)
    NS-->>NarratorUI: Returns NarrationResult object
    
    User->>NarratorUI: Tap "Play Story Audio"
    NarratorUI->>NS: speak(narrationResult.storyText)
    NS->>TTS: setLanguage(localeCode), setSpeechRate(0.5), speak(text)

    loop Every spoken word segment
        TTS->>NS: setProgressHandler(startOffset, endOffset)
        NS-->>NarratorUI: progressStream.add(progressValue 0.0 -> 1.0)
        NarratorUI->>NarratorUI: Update Audio Wave animation UI
        
        opt Waypoint coordinate trigger reached
            NS->>LGService: flyTo(keyLocations[currentSegment])
            LGService->>LGService: Smoothly pan Liquid Galaxy camera to next storytelling focus point
        end
    end

    TTS-->>NS: completionHandler triggered
    NS-->>NarratorUI: Playback complete
```

---

### Feature Flow 5: Live Weather Alert Polling & Liquid Galaxy Notification

```mermaid
sequenceDiagram
    autonumber
    participant Banner as ClimateAlertBanner [lib/widgets/climate_alert_banner.dart]
    participant CAS as ClimateAlertService [lib/features/climate_data/climate_alert_service.dart]
    participant OpenMeteo as Open-Meteo Weather API
    participant LGService as LgService

    Banner->>CAS: fetchAlertsForRegion(latitude, longitude)
    CAS->>OpenMeteo: GET https://api.open-meteo.com/v1/forecast?latitude=...&longitude=...&current_weather=true
    OpenMeteo-->>CAS: Returns JSON (Temperature, Wind speed, Precipitation)
    CAS->>CAS: Evaluate alert thresholds (e.g. Wind > 60km/h or Temp > 40°C)
    CAS-->>Banner: Returns List<ClimateAlert>
    Banner->>Banner: Display animated alert bar on UI

    opt User Taps "Show Alert on LG"
        Banner->>LGService: sendAlertKmlToLG(alert)
        LGService->>LGService: Send flashing red warning polygon & stats balloon to Liquid Galaxy screen
    end
```

---

## 5. Detailed Function Call Graph (What Calls What)

```mermaid
graph TD
    subgraph MainEntry ["lib/main.dart"]
        M1["main()"] --> M2["WidgetsFlutterBinding.ensureInitialized()"]
        M1 --> M3["DI.languageService.init()"]
        M1 --> M4["DI.themeService.init()"]
        M1 --> M5["DI.customRegionService.init()"]
        M1 --> M6["runApp(ClimateStorytellerApp)"]
    end

    subgraph ExploreFlow ["lib/features/explore/"]
        E1["ExploreScreen.build()"] --> E2["_onSelectRegion(region)"]
        E1 --> E3["ClimateYearSlider.onChanged(year)"]
        E1 --> E4["LGMapControllerWidget (Orbit / Zoom)"]
        E1 --> E5["ClimateAlertBanner"]

        E2 --> CDS1["ClimateDataService.visualizeRegionOnLG()"]
        E3 --> CDS2["ClimateDataService.visualizeYearOnLG()"]
        E4 --> LG1["LgService.startOrbit() / stopOrbit() / flyTo()"]
        E5 --> CAS1["ClimateAlertService.fetchAlertsForRegion()"]
    end

    subgraph ClimateDataFlow ["lib/features/climate_data/"]
        CDS1 --> LG2["LgService.flyTo()"]
        CDS1 --> CDS3["ClimateDataService.generateRegionKml()"]
        CDS3 --> LG3["LgService.sendKmlToSlave()"]
        CDS2 --> IPCC1["IpccData.getIpccDataForYear()"]
        CDS2 --> LG4["LgService.sendYearOverlayToLG()"]
    end

    subgraph NarratorFlow ["lib/features/narrator/"]
        N1["NarratorScreen._generateStory()"] --> NS1["NarratorService.generateNarration()"]
        N1 --> NS2["NarratorService.speak()"]
        NS1 --> G1["HTTP POST Gemini API"]
        NS2 --> TTS1["FlutterTts.speak()"]
        NS2 --> LG5["LgService.flyTo() (Waypoint camera sync)"]
    end

    subgraph LgConnectionFlow ["lib/features/lg_connection/"]
        LG3 --> SSH1["SSHClient.execute()"]
        LG3 --> SFTP1["SFTPClient.open() -> write()"]
        LG4 --> SFTP1
        LG1 --> SSH1
    end
```

---

## 6. Historical AI Session & Commit Modification Map

```mermaid
timeline
    title Historical AI Commit & Code Evolution
    section Foundation & Setup
        Commit 24da522 : IPCC Datasets & Projections
        Commit 3669710 : Feature-First Architecture
        Commit 3d5df62 : App Theme & Route Constants
    section LG SSH Engine
        Commit f62e13c : KML Local Caching
        Commit 338db6d : Multi-Screen Rig Engine (3/5/7 screens)
        Commit 3a4530c : SFTP Upload & kmls.txt Sync
        Commit 5362a49 : 3D Extruded Polygons
    section AI & Interactive Features
        Commit 62d3fa2 : Gemini 1.5 Flash Integration
        Commit 9ff79a1 : Flutter TTS Speech Engine
        Commit 792e9ab : Virtual LG D-Pad Controller
        Commit e20db9a : Year Slider & Narration Audio Sync
    section Recent Session Additions
        Current Session : Live Open-Meteo Weather Alerts
                        : Custom Lat/Lng Region Creator
```

---

## 7. Master File & Function Directory

| File Path | Primary Class / Functions | Responsibilities |
| :--- | :--- | :--- |
| [`lib/main.dart`](file:///c:/climate_change_storyteller/lib/main.dart) | `main()`, `ClimateStorytellerApp` | Entry point, DI init, orientation lock, MaterialApp routing |
| [`lib/core/di/injection_container.dart`](file:///c:/climate_change_storyteller/lib/core/di/injection_container.dart) | `DI` | Service locator singleton instances |
| [`lib/features/lg_connection/lg_service.dart`](file:///c:/climate_change_storyteller/lib/features/lg_connection/lg_service.dart) | `LgService.connect()`, `flyTo()`, `sendKmlToSlave()` | SSH socket connection, SFTP file transfer, LG camera controls |
| [`lib/features/climate_data/climate_data_service.dart`](file:///c:/climate_change_storyteller/lib/features/climate_data/climate_data_service.dart) | `ClimateDataService.visualizeRegionOnLG()`, `visualizeYearOnLG()` | Regional climate aggregator & KML overlay generator |
| [`lib/features/narrator/narrator_service.dart`](file:///c:/climate_change_storyteller/lib/features/narrator/narrator_service.dart) | `NarratorService.generateNarration()`, `speak()` | Gemini API storytelling & Flutter TTS synchronized playback |
| [`lib/features/climate_data/climate_alert_service.dart`](file:///c:/climate_change_storyteller/lib/features/climate_data/climate_alert_service.dart) | `ClimateAlertService.fetchAlertsForRegion()` | Real-time Open-Meteo weather API polling & alert generation |
| [`lib/features/explore/explore_screen.dart`](file:///c:/climate_change_storyteller/lib/features/explore/explore_screen.dart) | `ExploreScreen`, `_onSelectRegion()` | Main map UI, region cards, climate timeline year slider |
| [`lib/features/explore/shell_screen.dart`](file:///c:/climate_change_storyteller/lib/features/explore/shell_screen.dart) | `ShellScreen`, `_AppNavigationDrawer` | Top bar, drawer navigation, 5-tab `IndexedStack` container |
