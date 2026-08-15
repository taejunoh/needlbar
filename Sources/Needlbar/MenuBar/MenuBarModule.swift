import NeedlbarCore

public struct MenuBarModule: Equatable, Sendable {
    public let id: MenuModuleID
    public let title: String
    public let provider: ProviderID?

    public init(id: MenuModuleID, title: String, provider: ProviderID?) {
        self.id = id
        self.title = title
        self.provider = provider
    }

    public static let overview = MenuBarModule(id: .overview, title: "AI", provider: nil)
    public static let claude = MenuBarModule(id: .claude, title: "Claude", provider: .claude)
    public static let codex = MenuBarModule(id: .codex, title: "Codex", provider: .codex)
    public static let cursor = MenuBarModule(id: .cursor, title: "Cursor", provider: .cursor)

    public static let all = [overview, claude, codex, cursor]
}
