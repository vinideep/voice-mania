import Foundation

extension ModeManager {
    func migratedModeConfigurationData(for configKey: String) -> Data? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: configKey) {
            return data
        }

        guard let legacyData = defaults.data(forKey: LegacyModeDataKey.configurations) else {
            return nil
        }

        defaults.set(legacyData, forKey: configKey)
        return legacyData
    }

    func migrateLoadedModeConfigurationsIfNeeded() {
        var didChange = false

        for index in configurations.indices {
            var config = configurations[index]
            var changedConfig = false

            if config.selectedTranscriptionModelName == nil {
                config.selectedTranscriptionModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel")
                changedConfig = true
            }

            if config.selectedTranscriptionModelName == "ggml-large-v3-turbo-q5_0",
               !isWhisperLargeV3TurboQ5Downloaded(),
               isParakeetV3Downloaded() {
                config.selectedTranscriptionModelName = "parakeet-tdt-0.6b-v3"
                changedConfig = true
            }

            if config.selectedLanguage == nil {
                config.selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
                changedConfig = true
            }

            if config.selectedAIProvider == nil {
                config.selectedAIProvider = UserDefaults.standard.string(forKey: "selectedAIProvider")
                changedConfig = true
            }

            if config.selectedAIModel == nil,
               let provider = config.selectedAIProvider {
                config.selectedAIModel = UserDefaults.standard.string(forKey: "\(provider)SelectedModel")
                changedConfig = true
            }

            if config.isAIEnhancementEnabled && config.selectedPrompt == nil {
                config.selectedPrompt = UserDefaults.standard.string(forKey: "selectedPromptId")
                changedConfig = true
            }

            if changedConfig {
                configurations[index] = config
                didChange = true
            }
        }

        if UserDefaults.standard.string(forKey: "CurrentTranscriptionModel") == "ggml-large-v3-turbo-q5_0",
           !isWhisperLargeV3TurboQ5Downloaded(),
           isParakeetV3Downloaded() {
            UserDefaults.standard.set("parakeet-tdt-0.6b-v3", forKey: "CurrentTranscriptionModel")
        }

        if didChange {
            saveConfigurations()
        }

        migrateLegacyShortcutStorageIfNeeded()
    }

    private func migrateLegacyShortcutStorageIfNeeded() {
        let defaults = UserDefaults.standard

        for config in configurations {
            let oldShortcutKey = "\(LegacyModeDataKey.shortcutPrefix)\(config.id.uuidString)"
            let newShortcutKey = ShortcutAction.mode(config.id).userDefaultsKey

            if defaults.object(forKey: newShortcutKey) == nil,
               let oldShortcutData = defaults.data(forKey: oldShortcutKey) {
                defaults.set(oldShortcutData, forKey: newShortcutKey)
            }

            let oldClearedKey = "\(oldShortcutKey)_cleared"
            let newClearedKey = "\(newShortcutKey)_cleared"
            if defaults.object(forKey: newClearedKey) == nil,
               defaults.object(forKey: oldClearedKey) != nil {
                defaults.set(defaults.bool(forKey: oldClearedKey), forKey: newClearedKey)
            }
        }
    }

    private func isWhisperLargeV3TurboQ5Downloaded() -> Bool {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }
        let targetFile = appSupport
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
            .appendingPathComponent("WhisperModels", isDirectory: true)
            .appendingPathComponent("ggml-large-v3-turbo-q5_0.bin")
        return fileManager.fileExists(atPath: targetFile.path)
    }

    private func isParakeetV3Downloaded() -> Bool {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }
        let targetDir = appSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)

        let requiredFiles = [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecisionv3.mlmodelc",
            "parakeet_vocab.json"
        ]

        return requiredFiles.allSatisfy {
            fileManager.fileExists(atPath: targetDir.appendingPathComponent($0).path)
        }
    }
}

private enum LegacyModeDataKey {
    static let configurations = "powerModeConfigurationsV2"
    static let shortcutPrefix = "Shortcut_powerMode_"
}
