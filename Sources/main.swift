// ASL - Apple Silicon Linux
// A native Swift CLI for managing Linux containers on macOS using Apple Container

import Foundation
import ArgumentParser

// MARK: - Configuration

struct ASLConfig: Codable {
    var defaultDistro: String = "ubuntu"
    var distros: [String: DistroInfo] = [:]
    
    struct DistroInfo: Codable {
        let path: String
        let name: String
        let created: Date
    }
}

// MARK: - File Manager Extensions

extension FileManager {
    var aslDirectory: URL {
        homeDirectoryForCurrentUser.appendingPathComponent(".asl")
    }
    
    var containersDirectory: URL {
        aslDirectory.appendingPathComponent("containers")
    }
    
    var imagesDirectory: URL {
        aslDirectory.appendingPathComponent("images")
    }
    
    var configFile: URL {
        aslDirectory.appendingPathComponent("config.json")
    }
}

// MARK: - Configuration Manager

class ConfigManager {
    static let shared = ConfigManager()
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    func initialize() throws {
        try fileManager.createDirectory(at: fileManager.aslDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: fileManager.containersDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: fileManager.imagesDirectory, withIntermediateDirectories: true)
        
        if !fileManager.fileExists(atPath: fileManager.configFile.path) {
            let config = ASLConfig()
            try save(config: config)
        }
    }
    
    func loadConfig() throws -> ASLConfig {
        let data = try Data(contentsOf: fileManager.configFile)
        return try decoder.decode(ASLConfig.self, from: data)
    }
    
    func save(config: ASLConfig) throws {
        let data = try encoder.encode(config)
        try data.write(to: fileManager.configFile)
    }
}

// MARK: - Terminal Colors

enum TerminalColor: String {
    case red = "\u{001B}[0;31m"
    case green = "\u{001B}[0;32m"
    case yellow = "\u{001B}[1;33m"
    case blue = "\u{001B}[0;34m"
    case reset = "\u{001B}[0m"
    
    func wrap(_ text: String) -> String {
        return rawValue + text + TerminalColor.reset.rawValue
    }
}

// MARK: - Distribution Manager

enum Distribution: String, CaseIterable, ExpressibleByArgument {
    case ubuntu = "ubuntu"
    case ubuntu2404 = "ubuntu-24.04"
    case debian = "debian"
    case alpine = "alpine"
    case fedora = "fedora"
    
    var displayName: String {
        switch self {
        case .ubuntu: return "Ubuntu 22.04"
        case .ubuntu2404: return "Ubuntu 24.04"
        case .debian: return "Debian 12"
        case .alpine: return "Alpine 3.19"
        case .fedora: return "Fedora 39"
        }
    }
    
    var downloadURL: String {
        // We'll use container pull instead of downloading tarballs
        switch self {
        case .ubuntu:
            return "docker.io/library/ubuntu:22.04"
        case .ubuntu2404:
            return "docker.io/library/ubuntu:24.04"
        case .debian:
            return "docker.io/library/debian:12"
        case .alpine:
            return "docker.io/library/alpine:3.19"
        case .fedora:
            return "docker.io/library/fedora:39"
        }
    }
    
    var archiveExtension: String {
        switch self {
        case .alpine:
            return ".tar.gz"
        default:
            return ".tar.xz"
        }
    }
}

class DistroManager {
    private let fileManager = FileManager.default
    private let configManager = ConfigManager.shared
    
    func installDistro(_ distro: Distribution, force: Bool = false) throws {
        let imageName = "asl-\(distro.rawValue):latest"
        
        var config = try configManager.loadConfig()
        
        if config.distros[distro.rawValue] != nil && !force {
            print(TerminalColor.yellow.wrap("⚠️  Distribution \(distro.rawValue) is already installed"))
            print("Use --force to reinstall")
            return
        }
        
        print(TerminalColor.blue.wrap("📦 Installing \(distro.displayName)..."))
        print(TerminalColor.blue.wrap("🌐 This will pull and run \(distro.downloadURL) to create the image"))
        print(TerminalColor.yellow.wrap("⏳ First run may take a minute to download the image..."))
        
        // Use container run with --build-only to pull/build the image without running
        // Actually, we'll just pull by trying to create and immediately remove a container
        let pullTask = Process()
        pullTask.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
        pullTask.arguments = [
            "run",
            "--rm",
            "--name", "asl-install-\(distro.rawValue)",
            distro.downloadURL,
            "echo", "Image pulled successfully"
        ]
        
        // Show output to user
        pullTask.standardOutput = FileHandle.standardOutput
        pullTask.standardError = FileHandle.standardError
        
        try pullTask.run()
        pullTask.waitUntilExit()
        
        guard pullTask.terminationStatus == 0 else {
            throw NSError(domain: "ASL", code: 10, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to pull image. Make sure container system is running: container system start"])
        }
        
        // Tag it with our naming convention
        print("🏷️  Tagging image as \(imageName)...")
        let tagTask = Process()
        tagTask.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
        tagTask.arguments = ["image", "tag", distro.downloadURL, imageName]
        try tagTask.run()
        tagTask.waitUntilExit()
        
        // Update config
        config.distros[distro.rawValue] = ASLConfig.DistroInfo(
            path: imageName,
            name: imageName,
            created: Date()
        )
        try configManager.save(config: config)
        
        print(TerminalColor.green.wrap("✓ \(distro.displayName) installed successfully"))
        print(TerminalColor.yellow.wrap("💡 Run 'asl \(distro.rawValue)' to enter the distribution"))
    }
    
    func listDistros() throws {
        let config = try configManager.loadConfig()
        
        if config.distros.isEmpty {
            print(TerminalColor.yellow.wrap("No distributions installed."))
            print("Install one with: asl install <distro>")
            return
        }
        
        print(TerminalColor.blue.wrap("Installed distributions:"))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        for (name, info) in config.distros.sorted(by: { $0.key < $1.key }) {
            let dateStr = dateFormatter.string(from: info.created)
            print("  • \(name) (installed: \(dateStr))")
        }
    }
    
    func uninstallDistro(_ distro: Distribution) throws {
        let imageName = "asl-\(distro.rawValue):latest"
        
        // Check if image exists
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
        checkTask.arguments = ["image", "list"]
        
        let pipe = Pipe()
        checkTask.standardOutput = pipe
        try checkTask.run()
        checkTask.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        guard output.contains(imageName) else {
            throw NSError(domain: "ASL", code: 3, 
                         userInfo: [NSLocalizedDescriptionKey: "Distribution '\(distro.rawValue)' is not installed"])
        }
        
        print("Are you sure you want to uninstall \(distro.rawValue)? (y/N): ", terminator: "")
        let response = readLine()?.lowercased()
        
        guard response == "y" || response == "yes" else {
            print("Cancelled")
            return
        }
        
        print(TerminalColor.yellow.wrap("🗑️  Uninstalling \(distro.rawValue)..."))
        
        let removeTask = Process()
        removeTask.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
        removeTask.arguments = ["image", "rm", imageName]
        try removeTask.run()
        removeTask.waitUntilExit()
        
        var config = try configManager.loadConfig()
        config.distros.removeValue(forKey: distro.rawValue)
        try configManager.save(config: config)
        
        print(TerminalColor.green.wrap("✓ \(distro.rawValue) uninstalled"))
    }
    
    func enterDistro(_ distro: Distribution) throws {
        let imageName = "asl-\(distro.rawValue):latest"
        
        print(TerminalColor.green.wrap("🚀 Entering \(distro.displayName)..."))
        print(TerminalColor.yellow.wrap("💡 Tip: Your macOS home directory is available at /host"))
        
        // Use exec to replace current process - this is the only way to properly handle TTY
        let containerPath = "/usr/local/bin/container"
        let args = [
            "container",  // argv[0]
            "run",
            "--rm",
            "--interactive",
            "--tty",
            "--volume", "\(fileManager.homeDirectoryForCurrentUser.path):/host",
            "--workdir", "/root",
            "--env", "TERM=\(ProcessInfo.processInfo.environment["TERM"] ?? "xterm-256color")",
            imageName,
            "/bin/bash", "-l"
        ]
        
        // Convert Swift strings to C strings
        let cArgs = args.map { strdup($0) } + [nil]
        
        // exec replaces the current process
        execv(containerPath, cArgs)
        
        // If we get here, exec failed
        let error = String(cString: strerror(errno))
        throw NSError(domain: "ASL", code: 11, 
                     userInfo: [NSLocalizedDescriptionKey: "Failed to exec container: \(error)"])
    }
    
    func selectDistroInteractively() throws {
        let config = try configManager.loadConfig()
        
        guard !config.distros.isEmpty else {
            print(TerminalColor.yellow.wrap("No distributions installed."))
            print("Install one with: asl install <distro>")
            return
        }
        
        let sortedDistros = config.distros.keys.sorted()
        
        if sortedDistros.count == 1 {
            guard let distro = Distribution(rawValue: sortedDistros[0]) else {
                throw NSError(domain: "ASL", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid distribution"])
            }
            try enterDistro(distro)
            return
        }
        
        print(TerminalColor.blue.wrap("Select a distribution:"))
        for (index, name) in sortedDistros.enumerated() {
            print("  \(index + 1)) \(name)")
        }
        
        print("Enter number: ", terminator: "")
        guard let input = readLine(),
              let selection = Int(input),
              selection > 0,
              selection <= sortedDistros.count else {
            throw NSError(domain: "ASL", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid selection"])
        }
        
        let selectedName = sortedDistros[selection - 1]
        guard let distro = Distribution(rawValue: selectedName) else {
            throw NSError(domain: "ASL", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid distribution"])
        }
        
        try enterDistro(distro)
    }
}

// MARK: - CLI Commands

struct ASL: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "asl",
        abstract: "Apple Silicon Linux - Native Linux containers for macOS",
        version: "1.0.0",
        subcommands: [Install.self, List.self, Uninstall.self, Enter.self],
        defaultSubcommand: Enter.self
    )
}

extension ASL {
    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install a Linux distribution"
        )
        
        @Argument(help: "Distribution to install (ubuntu, debian, alpine, fedora)")
        var distribution: Distribution = .ubuntu
        
        @Flag(name: .long, help: "Force reinstall if already installed")
        var force = false
        
        func run() throws {
            try ConfigManager.shared.initialize()
            let manager = DistroManager()
            try manager.installDistro(distribution, force: force)
        }
    }
    
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List installed distributions"
        )
        
        func run() throws {
            try ConfigManager.shared.initialize()
            let manager = DistroManager()
            try manager.listDistros()
        }
    }
    
    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Uninstall a distribution"
        )
        
        @Argument(help: "Distribution to uninstall")
        var distribution: Distribution
        
        func run() throws {
            try ConfigManager.shared.initialize()
            let manager = DistroManager()
            try manager.uninstallDistro(distribution)
        }
    }
    
    struct Enter: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Enter a distribution (interactive if no distro specified)"
        )
        
        @Argument(help: "Distribution to enter")
        var distribution: Distribution?
        
        func run() throws {
            try ConfigManager.shared.initialize()
            let manager = DistroManager()
            
            if let distro = distribution {
                try manager.enterDistro(distro)
            } else {
                try manager.selectDistroInteractively()
            }
        }
    }
}

// MARK: - Entry Point

ASL.main()
