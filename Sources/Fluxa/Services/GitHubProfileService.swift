import Foundation
import Observation

// MARK: - GitHub Public Models

struct GitHubProfile: Decodable, Sendable {
    let login: String
    let name: String?
    let bio: String?
    let avatarURL: URL
    let htmlURL: URL
    let followers: Int
    let publicRepos: Int
    let location: String?

    private enum CodingKeys: String, CodingKey {
        case login
        case name
        case bio
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
        case followers
        case publicRepos = "public_repos"
        case location
    }
}

struct GitHubRepository: Decodable, Sendable {
    let name: String
    let description: String?
    let htmlURL: URL
    let stargazersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let language: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case htmlURL = "html_url"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
        case language
    }
}

// MARK: - GitHubProfileService

/// Loads the public developer and repository details shown on Fluxa's About page.
///
/// No GitHub token is used or needed. Requests happen only when the user opens About, are cached for
/// the lifetime of the app, and fail softly so the static identity and external links always remain
/// usable offline.
@Observable
@MainActor
final class GitHubProfileService {

    static let profilePageURL = URL(string: "https://github.com/zEhmsy")!
    static let repositoryPageURL = URL(string: "https://github.com/zEhmsy/fluxa")!

    private(set) var profile: GitHubProfile?
    private(set) var repository: GitHubRepository?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var loadedAt: Date?

    /// Reuses a successful read for 15 minutes. About may be opened repeatedly from the menu-bar
    /// panel, and public GitHub API calls should not be spent on data that changes slowly.
    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force,
           let loadedAt,
           Date().timeIntervalSince(loadedAt) < 15 * 60,
           profile != nil || repository != nil {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let profileResult = try? Self.fetch(
            GitHubProfile.self,
            from: URL(string: "https://api.github.com/users/zEhmsy")!
        )
        async let repositoryResult = try? Self.fetch(
            GitHubRepository.self,
            from: URL(string: "https://api.github.com/repos/zEhmsy/fluxa")!
        )

        let (newProfile, newRepository) = await (profileResult, repositoryResult)
        if let newProfile { profile = newProfile }
        if let newRepository { repository = newRepository }

        if newProfile != nil || newRepository != nil {
            loadedAt = Date()
        } else if profile == nil && repository == nil {
            errorMessage = "Live GitHub details are unavailable right now."
        }
    }

    // MARK: - Request

    private nonisolated static func fetch<Value: Decodable & Sendable>(
        _ type: Value.Type,
        from url: URL
    ) async throws -> Value {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        request.setValue("Fluxa/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(type, from: data)
    }
}
