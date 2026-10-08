// Standardizes config-directory spellings for comparison without changing stored strings.

/// Compares config-directory paths the way users mean them, not byte for byte.
public enum ConfigPath {
    /// Returns `path` with a leading `~` expanded against `home`, `.` and empty components
    /// removed, `..` resolved, and no trailing slash. Pure string handling; never touches disk.
    public static func standardized(_ path: String, home: String) -> String {
        var expanded = path
        if expanded == "~" || expanded.hasPrefix("~/") {
            expanded = home + expanded.dropFirst()
        }
        var components: [Substring] = []
        for component in expanded.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                _ = components.popLast()
            default:
                components.append(component)
            }
        }
        let joined = components.joined(separator: "/")
        return expanded.hasPrefix("/") ? "/" + joined : joined
    }

    /// Returns the last path component of `path` after standardization.
    public static func lastComponent(of path: String, home: String) -> String {
        let standard = standardized(path, home: home)
        return standard.split(separator: "/").last.map(String.init) ?? standard
    }
}
