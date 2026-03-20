import PackagePlugin
import Foundation

@main
struct LintGatePlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let lintTargetNames: Set<String> = ["UnmissableTests", "IntegrationTests", "SnapshotTests"]
        guard lintTargetNames.contains(target.name) else {
            return []
        }

        let scriptURL = context.package.directoryURL.appendingPathComponent("Scripts/enforce-lint.sh")
        let outputDirURL = context.pluginWorkDirectoryURL.appendingPathComponent("lint-gate")
        let cacheDirURL = outputDirURL.appendingPathComponent("swiftlint-cache")
        let homeDirURL = outputDirURL.appendingPathComponent("home")

        return [
            .prebuildCommand(
                displayName: "Enforcing Unmissable lint policy",
                executable: URL(fileURLWithPath: "/bin/bash"),
                arguments: [scriptURL.path],
                environment: [
                    "LINT_GATE_PLUGIN_OUTPUT_DIR": outputDirURL.path,
                    "LINT_GATE_CACHE_DIR": cacheDirURL.path,
                    "LINT_GATE_HOME_DIR": homeDirURL.path,
                ],
                outputFilesDirectory: outputDirURL
            ),
        ]
    }
}
