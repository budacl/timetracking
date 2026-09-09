import Foundation

/// Minimal YouTrack REST client (permanent-token auth).
struct YouTrackClient {
    let baseURL: URL
    let token: String

    struct Me: Decodable { let id: String; let login: String; let name: String? }

    struct Issue: Decodable {
        let idReadable: String
        let summary: String?
        let project: Project?
        struct Project: Decodable { let id: String; let shortName: String? }
    }

    struct WorkItemType: Decodable { let id: String; let name: String? }

    struct WorkItem: Decodable {
        let id: String
        let date: Double?
        let duration: Duration?
        let issue: IssueRef?
        struct Duration: Decodable { let minutes: Int? }
        struct IssueRef: Decodable { let idReadable: String?; let summary: String? }
    }

    private struct Created: Decodable { let id: String }
    private struct APIError: Decodable { let error: String?; let error_description: String? }

    enum ClientError: LocalizedError {
        case invalidBaseURL
        case missingToken
        case http(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL: return "The YouTrack server URL is not valid."
            case .missingToken: return "No YouTrack token is set. Add one in Settings (⌘,)."
            case .http(let status, let message): return "YouTrack returned HTTP \(status): \(message)"
            }
        }
    }

    init?(baseURL: String, token: String) {
        var raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard let url = URL(string: raw), url.scheme != nil, url.host != nil else { return nil }
        self.baseURL = url
        self.token = token
    }

    // MARK: Endpoints

    func me() async throws -> Me {
        try await get("users/me", query: [("fields", "id,login,name")])
    }

    func issue(_ id: String) async throws -> Issue {
        try await get("issues/\(id)", query: [("fields", "idReadable,summary,project(id,shortName)")])
    }

    func workItemTypes(projectId: String) async throws -> [WorkItemType] {
        try await get("admin/projects/\(projectId)/timeTrackingSettings/workItemTypes", query: [("fields", "id,name")])
    }

    /// Creates a work item and returns its id.
    func logWork(issueId: String, minutes: Int, date: Date, text: String, typeId: String?) async throws -> String {
        var body: [String: Any] = [
            "duration": ["minutes": minutes],
            "date": Int(date.timeIntervalSince1970 * 1000),
        ]
        if !text.isEmpty { body["text"] = text }
        if let typeId { body["type"] = ["id": typeId] }
        let created: Created = try await post("issues/\(issueId)/timeTracking/workItems", query: [("fields", "id")], body: body)
        return created.id
    }

    /// Work items authored by `authorId` between two dates (inclusive).
    func workItems(authorId: String, from: Date, to: Date) async throws -> [WorkItem] {
        let f = DateFormatter()
        f.calendar = CzechCalendar.calendar
        f.dateFormat = "yyyy-MM-dd"
        return try await get("workItems", query: [
            ("fields", "id,date,duration(minutes),issue(idReadable,summary)"),
            ("author", authorId),
            ("startDate", f.string(from: from)),
            ("endDate", f.string(from: to)),
            ("$top", "1000"),
        ])
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ path: String, query: [(String, String)]) async throws -> T {
        try await send(request(path, method: "GET", query: query, body: nil))
    }

    private func post<T: Decodable>(_ path: String, query: [(String, String)], body: [String: Any]) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(request(path, method: "POST", query: query, body: data))
    }

    private func request(_ path: String, method: String, query: [(String, String)], body: Data?) throws -> URLRequest {
        guard !token.isEmpty else { throw ClientError.missingToken }
        guard var components = URLComponents(url: baseURL.appendingPathComponent("api/\(path)"), resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidBaseURL
        }
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { throw ClientError.invalidBaseURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let api = try? JSONDecoder().decode(APIError.self, from: data)
            let message = api?.error_description ?? api?.error ?? String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(status: status, message: message.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
