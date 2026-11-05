import Foundation
import Network
import Observation

/// A request can arrive across several TCP packets, so it is complete only once the headers
/// and all `Content-Length` bytes are in.
public enum HTTPRequestFraming {
    /// Stops a client from growing the buffer forever.
    public static let maximumSize = 10 * 1024 * 1024

    public static func isComplete(_ data: Data) -> Bool {
        guard data.count < maximumSize else { return true }
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else { return false }

        let headers = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self).lowercased()
        for line in headers.components(separatedBy: "\r\n") where line.hasPrefix("content-length:") {
            let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            return data.distance(from: headerEnd.upperBound, to: data.endIndex) >= (Int(value) ?? 0)
        }
        return true
    }
}

/// Listening on loopback keeps the network out, but a web page can still send requests to
/// localhost, so requests from browsers are refused here.
public enum HTTPRequestGuard {
    /// The HTTP status to refuse the request with, or nil when it may proceed.
    public static func rejectionStatus(forRequestHead head: String, authToken: String) -> Int? {
        var headers: [String: String] = [:]
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        // Browsers always send Origin on cross-site requests; MCP clients are not browsers.
        guard headers["origin"] == nil else { return 403 }
        // A DNS rebinding attack reaches this port with the attacker's own domain as Host.
        guard let host = headers["host"], isLoopback(host: host) else { return 403 }

        let token = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty, headers["authorization"] != "Bearer \(token)" {
            return 401
        }
        return nil
    }

    private static func isLoopback(host: String) -> Bool {
        let lowered = host.lowercased()
        let name: String
        if lowered.hasPrefix("["), let end = lowered.firstIndex(of: "]") {
            name = String(lowered[...end])
        } else {
            name = lowered.components(separatedBy: ":")[0]
        }
        return ["127.0.0.1", "localhost", "[::1]"].contains(name)
    }
}

public struct MCPToolDefinition: @unchecked Sendable {
    public let name: String
    public let description: String
    public let inputSchema: [String: Any]
}

public enum AIClientTarget: String, CaseIterable, Identifiable, Sendable {
    case claude = "Claude Desktop"
    case antigravity = "Antigravity"
    case cursor = "Cursor IDE"
    case windsurf = "Windsurf"

    public var id: String { rawValue }

    public var badge: String {
        switch self {
        case .claude: return "Anthropic"
        case .antigravity: return "Agent"
        case .cursor: return "Cursor"
        case .windsurf: return "Codeium"
        }
    }

    public var badgeColorName: String {
        switch self {
        case .claude: return "orange"
        case .antigravity: return "purple"
        case .cursor: return "blue"
        case .windsurf: return "teal"
        }
    }

    public var configPathDescription: String {
        switch self {
        case .claude: return "~/Library/Application Support/Claude/claude_desktop_config.json"
        case .antigravity: return "~/.gemini/config/mcp_config.json"
        case .cursor: return "~/.cursor/mcp.json"
        case .windsurf: return "~/.codeium/windsurf/mcp_config.json"
        }
    }

    public var configURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude:
            return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .antigravity:
            return home.appendingPathComponent(".gemini/config/mcp_config.json")
        case .cursor:
            return home.appendingPathComponent(".cursor/mcp.json")
        case .windsurf:
            return home.appendingPathComponent(".codeium/windsurf/mcp_config.json")
        }
    }

    public var isInstalledOnSystem: Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        switch self {
        case .claude:
            return fm.fileExists(atPath: "/Applications/Claude.app") || fm.fileExists(atPath: home.appendingPathComponent("Library/Application Support/Claude").path)
        case .antigravity:
            return fm.fileExists(atPath: home.appendingPathComponent(".gemini").path)
        case .cursor:
            return fm.fileExists(atPath: "/Applications/Cursor.app") || fm.fileExists(atPath: home.appendingPathComponent(".cursor").path)
        case .windsurf:
            return fm.fileExists(atPath: "/Applications/Windsurf.app") || fm.fileExists(atPath: home.appendingPathComponent(".codeium/windsurf").path)
        }
    }

    public var isConfigured: Bool {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else {
            return false
        }
        return servers["cocoa"] != nil || servers["cocoa-local"] != nil
    }
}

@Observable
public final class MCPServerService: @unchecked Sendable {
    public static let shared = MCPServerService()

    public var isRunning: Bool = false
    public var currentPort: Int = 4040
    public var requestCount: Int = 0
    public var lastRequestSummary: String = "No requests received yet"
    public var lastActivityTime: Date? = nil

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.cocoa.mcp.server", qos: .userInitiated)

    private init() {}

    // MARK: - Server Lifecycle
    public func start(port: Int? = nil) {
        stop()

        let targetPort = port ?? AppSettings.shared.mcpServerPort
        self.currentPort = targetPort

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(targetPort)) else {
                print("[MCP] Invalid port: \(targetPort)")
                return
            }

            let parameters = NWParameters.tcp
            // Only this Mac can connect. Binding the address is what does this: a loopback
            // interface requirement alone still leaves the socket listening on every address.
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)

            let newListener = try NWListener(using: parameters)
            self.listener = newListener

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        print("[MCP] Server listening on 127.0.0.1:\(targetPort)")
                    case .failed(let error):
                        self.isRunning = false
                        print("[MCP] Server failed: \(error.localizedDescription)")
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            newListener.start(queue: queue)
        } catch {
            print("[MCP] Error starting listener: \(error.localizedDescription)")
            Task { @MainActor in
                self.isRunning = false
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        Task { @MainActor in
            self.isRunning = false
        }
    }

    public func restart(port: Int) {
        stop()
        AppSettings.shared.mcpServerPort = port
        start(port: port)
    }

    // MARK: - Connection & HTTP Handling
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHTTPRequest(connection: connection)
    }

    private func readHTTPRequest(connection: NWConnection, received: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = received
            if let data {
                buffer.append(data)
            }
            guard !buffer.isEmpty else {
                if isComplete || error != nil { connection.cancel() }
                return
            }
            guard HTTPRequestFraming.isComplete(buffer) || isComplete || error != nil else {
                self.readHTTPRequest(connection: connection, received: buffer)
                return
            }

            let responseData = self.processRawHTTPData(buffer)
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func processRawHTTPData(_ data: Data) -> Data {
        guard let requestString = String(data: data, encoding: .utf8) else {
            return makeHTTPResponse(status: 400, body: "{\"error\": \"Bad Request\"}")
        }

        let requestHead = requestString.components(separatedBy: "\r\n\r\n")[0]
        if let status = HTTPRequestGuard.rejectionStatus(forRequestHead: requestHead, authToken: AppSettings.shared.mcpAuthToken) {
            return makeHTTPResponse(status: status, body: "{\"error\": \"Request refused\"}")
        }

        // Handle GET /status or GET /
        if requestString.hasPrefix("GET /status") || requestString.hasPrefix("GET / ") {
            let statusJSON = """
            {
                "status": "ok",
                "server": "Cocoa MCP Server",
                "version": "1.0.0",
                "port": \(currentPort),
                "requestsHandled": \(requestCount)
            }
            """
            return makeHTTPResponse(status: 200, body: statusJSON)
        }

        // Extract HTTP Body after double CRLF
        var bodyData: Data? = nil
        if let range = requestString.range(of: "\r\n\r\n") {
            let bodySubstring = requestString[range.upperBound...]
            bodyData = bodySubstring.data(using: .utf8)
        } else if let range = requestString.range(of: "\n\n") {
            let bodySubstring = requestString[range.upperBound...]
            bodyData = bodySubstring.data(using: .utf8)
        }

        guard let body = bodyData, !body.isEmpty else {
            return makeHTTPResponse(status: 200, body: "{\"server\": \"Cocoa MCP Server\", \"message\": \"Send POST with JSON-RPC payload\"}")
        }

        let rpcResponse = processJSONRPCMessage(body)
        return makeHTTPResponse(status: 200, body: rpcResponse)
    }

    private func makeHTTPResponse(status: Int, body: String) -> Data {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 401: statusText = "Unauthorized"
        case 403: statusText = "Forbidden"
        default: statusText = "Bad Request"
        }
        let header = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        return header.data(using: .utf8) ?? Data()
    }

    // MARK: - JSON-RPC 2.0 Dispatcher
    public func processJSONRPCMessage(_ messageData: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
              let method = json["method"] as? String else {
            return "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null}"
        }

        let requestId = json["id"]
        let params = json["params"] as? [String: Any] ?? [:]

        Task { @MainActor in
            self.requestCount += 1
            self.lastActivityTime = Date()
            self.lastRequestSummary = "Method: \(method) at \(Date().formatted(date: .omitted, time: .standard))"
        }

        switch method {
        case "initialize":
            let result: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": ["listChanged": true],
                    "resources": ["subscribe": false, "listChanged": false],
                    "prompts": ["listChanged": false]
                ],
                "serverInfo": [
                    "name": "cocoa",
                    "version": "1.0.0"
                ]
            ]
            return formatRPCSuccess(id: requestId, result: result)

        case "notifications/initialized":
            return ""

        case "ping":
            return formatRPCSuccess(id: requestId, result: [String: Any]())

        case "tools/list":
            let tools = availableToolsList()
            let result: [String: Any] = ["tools": tools]
            return formatRPCSuccess(id: requestId, result: result)

        case "tools/call":
            guard let toolName = params["name"] as? String else {
                return formatRPCError(id: requestId, code: -32602, message: "Missing tool name in tools/call")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let callResult = executeTool(name: toolName, arguments: arguments)
            return formatRPCSuccess(id: requestId, result: callResult)

        case "resources/list":
            let resources: [[String: Any]] = [
                [
                    "uri": "cocoa://tasks/today",
                    "name": "Today Tasks",
                    "description": "All pending tasks on the Today board in Cocoa",
                    "mimeType": "application/json"
                ],
                [
                    "uri": "cocoa://tasks/all",
                    "name": "All Tasks",
                    "description": "All tasks in Cocoa categorized by board and list",
                    "mimeType": "application/json"
                ],
                [
                    "uri": "cocoa://timer/status",
                    "name": "Focus Timer Status",
                    "description": "Current active task, timer state, and remaining focus minutes",
                    "mimeType": "application/json"
                ]
            ]
            return formatRPCSuccess(id: requestId, result: ["resources": resources])

        case "resources/read":
            guard let uri = params["uri"] as? String else {
                return formatRPCError(id: requestId, code: -32602, message: "Missing uri in resources/read")
            }
            let readResult = executeResourceRead(uri: uri)
            return formatRPCSuccess(id: requestId, result: readResult)

        default:
            return formatRPCError(id: requestId, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func formatRPCSuccess(id: Any?, result: [String: Any]) -> String {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result
        ]
        if let id {
            payload["id"] = id
        } else {
            payload["id"] = NSNull()
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\"jsonrpc\":\"2.0\",\"result\":{},\"id\":null}"
    }

    private func formatRPCError(id: Any?, code: Int, message: String) -> String {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message
            ]
        ]
        if let id {
            payload["id"] = id
        } else {
            payload["id"] = NSNull()
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":\(code),\"message\":\"\(message)\"},\"id\":null}"
    }

    // MARK: - Tool Definitions
    public func availableToolsList() -> [[String: Any]] {
        return [
            [
                "name": "cocoa_get_active_task",
                "description": "Get the current active focus task and timer state in Cocoa (remaining seconds, estimated minutes, time spent, running/paused).",
                "inputSchema": [
                    "type": "object",
                    "properties": [String: Any]()
                ]
            ],
            [
                "name": "cocoa_get_task",
                "description": "Read one task in full: its Markdown notes, subtasks, comments, and details. Use this to read the brief for a task and any earlier feedback.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string", "description": "UUID of the task, from cocoa_list_tasks. If omitted, reads the active task."]
                    ]
                ]
            ],
            [
                "name": "cocoa_list_tasks",
                "description": "List tasks from Cocoa. Can filter by board ('Today', 'Upcoming', 'Backlog', 'Completed') or by list name. Tasks with notes are marked; use cocoa_get_task to read them.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "board": [
                            "type": "string",
                            "enum": ["Today", "Upcoming", "Backlog", "Completed"],
                            "description": "Filter by board name"
                        ],
                        "list_name": [
                            "type": "string",
                            "description": "Filter by list category name (e.g. 'General', 'Work', 'Research')"
                        ]
                    ]
                ]
            ],
            [
                "name": "cocoa_create_task",
                "description": "Create a new task in Cocoa with title, estimated minutes, priority, list, and notes.",
                "inputSchema": [
                    "type": "object",
                    "required": ["title"],
                    "properties": [
                        "title": ["type": "string", "description": "The title of the task"],
                        "estimated_minutes": ["type": "integer", "description": "Estimated duration in minutes (e.g. 15, 25, 45, 60)", "default": 25],
                        "priority": ["type": "string", "enum": ["Low", "Medium", "High"], "default": "Medium"],
                        "board": ["type": "string", "enum": ["Today", "Upcoming", "Backlog"], "default": "Today"],
                        "list_name": ["type": "string", "description": "Category list name (e.g. 'General')", "default": "General"],
                        "notes": ["type": "string", "description": "Initial notes in GitHub-flavored Markdown"]
                    ]
                ]
            ],
            [
                "name": "cocoa_add_subtasks",
                "description": "Add one or more subtasks/checklist items to an existing task or to the currently active task.",
                "inputSchema": [
                    "type": "object",
                    "required": ["subtasks"],
                    "properties": [
                        "task_id": ["type": "string", "description": "UUID of the task. If omitted, adds to the active task."],
                        "subtasks": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Array of subtask titles to add"
                        ]
                    ]
                ]
            ],
            [
                "name": "cocoa_update_subtask",
                "description": "Edit or rename an existing subtask/checklist item in a task.",
                "inputSchema": [
                    "type": "object",
                    "required": ["subtask_id", "new_title"],
                    "properties": [
                        "task_id": ["type": "string", "description": "UUID of the task. If omitted, uses active task."],
                        "subtask_id": ["type": "string", "description": "UUID of the subtask to update"],
                        "new_title": ["type": "string", "description": "The new title text for the subtask"]
                    ]
                ]
            ],
            [
                "name": "cocoa_complete_task",
                "description": "Mark a task as completed.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string", "description": "UUID of the task to complete. If omitted, completes the active task."]
                    ]
                ]
            ],
            [
                "name": "cocoa_start_timer",
                "description": "Start or resume the focus timer on the active task in Cocoa.",
                "inputSchema": [
                    "type": "object",
                    "properties": [String: Any]()
                ]
            ],
            [
                "name": "cocoa_pause_timer",
                "description": "Pause the focus timer in Cocoa.",
                "inputSchema": [
                    "type": "object",
                    "properties": [String: Any]()
                ]
            ],
            [
                "name": "cocoa_reset_timer",
                "description": "Reset the current focus timer back to its initial estimated duration.",
                "inputSchema": [
                    "type": "object",
                    "properties": [String: Any]()
                ]
            ],
            [
                "name": "cocoa_update_notes",
                "description": "Replace or append to a task's notes. Notes are Markdown and appear formatted in Cocoa straight away: headings, bold, italic, strikethrough, inline code, fenced code blocks, lists, task lists (- [ ]), quotes, links, and tables. Set append to true to add feedback without replacing what the user wrote.",
                "inputSchema": [
                    "type": "object",
                    "required": ["notes"],
                    "properties": [
                        "task_id": ["type": "string", "description": "UUID of the task. If omitted, updates the active task."],
                        "notes": ["type": "string", "description": "The notes content in GitHub-flavored Markdown"],
                        "append": ["type": "boolean", "description": "If true, appends to existing notes. If false, replaces existing notes.", "default": false]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Tool Execution
    private func executeTool(name: String, arguments: [String: Any]) -> [String: Any] {
        var outputText = ""
        let argsData = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data()

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            let args = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
            let taskStore = WindowManager.shared.taskStore
            let timerManager = WindowManager.shared.timerManager

            switch name {
            case "cocoa_get_active_task":
                if let active = taskStore.activeTask {
                    let subtasksCompleted = active.subtasks.filter { $0.isCompleted }.count
                    let summary = """
                    Active Task: \(active.title)
                    ID: \(active.id.uuidString)
                    Board: \(active.board.rawValue)
                    List: \(active.listName)
                    Priority: \(active.priority.rawValue)
                    Estimate: \(active.estimatedMinutes)m
                    Time Spent: \(active.timeSpentSeconds / 60)m \(active.timeSpentSeconds % 60)s
                    Subtasks: \(subtasksCompleted)/\(active.subtasks.count) completed
                    Timer State: \(timerManager.state.rawValue.uppercased()) (\(timerManager.formattedTime) remaining)
                    Notes: \(active.notes.isEmpty ? "(none)" : active.notes)
                    """
                    outputText = summary
                } else {
                    outputText = "No active focus task. Cocoa is idle."
                }

            case "cocoa_get_task":
                let targetTaskId: UUID?
                if let idStr = args["task_id"] as? String {
                    targetTaskId = UUID(uuidString: idStr)
                } else {
                    targetTaskId = taskStore.activeTaskId
                }

                if let targetTaskId, let task = taskStore.tasks.first(where: { $0.id == targetTaskId }) {
                    outputText = task.agentSummary
                } else {
                    outputText = "Error: Task not found."
                }

            case "cocoa_list_tasks":
                var filtered = taskStore.tasks
                if let boardStr = args["board"] as? String, let board = TaskBoard(rawValue: boardStr) {
                    filtered = filtered.filter { $0.board == board }
                }
                if let listName = args["list_name"] as? String {
                    filtered = filtered.filter { $0.listName.caseInsensitiveCompare(listName) == .orderedSame }
                }

                if filtered.isEmpty {
                    outputText = "No tasks found matching query."
                } else {
                    var lines: [String] = ["Found \(filtered.count) tasks:"]
                    for t in filtered {
                        let check = t.isCompleted ? "[x]" : "[ ]"
                        let notesMark = t.notes.isEmpty ? "" : " (has notes)"
                        lines.append("- \(check) \(t.title) (\(t.estimatedMinutes)m) [\(t.board.rawValue) / \(t.listName)]\(notesMark) ID: \(t.id.uuidString)")
                    }
                    outputText = lines.joined(separator: "\n")
                }

            case "cocoa_create_task":
                let title = args["title"] as? String ?? "New Task"
                let est = args["estimated_minutes"] as? Int ?? 25
                let prioStr = args["priority"] as? String ?? "Medium"
                let prio = TaskPriority(rawValue: prioStr) ?? .medium
                let boardStr = args["board"] as? String ?? "Today"
                let board = TaskBoard(rawValue: boardStr) ?? .today
                let list = args["list_name"] as? String ?? "General"
                let notes = args["notes"] as? String ?? ""

                taskStore.addTask(
                    title: title,
                    notes: notes,
                    estimatedMinutes: est,
                    priority: prio,
                    listName: list,
                    board: board
                )

                if let created = taskStore.tasks.first {
                    outputText = "Created task '\(created.title)' (ID: \(created.id.uuidString)) on \(board.rawValue) board."
                } else {
                    outputText = "Task created."
                }

            case "cocoa_add_subtasks":
                guard let subtaskList = args["subtasks"] as? [String], !subtaskList.isEmpty else {
                    outputText = "Error: 'subtasks' array is empty."
                    semaphore.signal()
                    return
                }

                let targetTaskId: UUID?
                if let idStr = args["task_id"] as? String, let parsed = UUID(uuidString: idStr) {
                    targetTaskId = parsed
                } else {
                    targetTaskId = taskStore.activeTaskId ?? taskStore.tasks.first?.id
                }

                if let targetId = targetTaskId, let task = taskStore.tasks.first(where: { $0.id == targetId }) {
                    for sub in subtaskList {
                        taskStore.addSubtask(to: targetId, title: sub)
                    }
                    outputText = "Added \(subtaskList.count) subtasks to task '\(task.title)'."
                } else {
                    outputText = "Error: Task not found."
                }

            case "cocoa_update_subtask":
                guard let subtaskIdStr = args["subtask_id"] as? String, let subtaskId = UUID(uuidString: subtaskIdStr),
                      let newTitle = args["new_title"] as? String, !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    outputText = "Error: 'subtask_id' and non-empty 'new_title' are required."
                    semaphore.signal()
                    return
                }

                let targetTaskId: UUID?
                if let idStr = args["task_id"] as? String, let parsed = UUID(uuidString: idStr) {
                    targetTaskId = parsed
                } else {
                    targetTaskId = taskStore.tasks.first(where: { $0.subtasks.contains(where: { $0.id == subtaskId }) })?.id ?? taskStore.activeTaskId
                }

                if let targetId = targetTaskId {
                    taskStore.updateSubtask(in: targetId, subtaskId: subtaskId, newTitle: newTitle)
                    outputText = "Updated subtask successfully to '\(newTitle)'."
                } else {
                    outputText = "Error: Task containing subtask \(subtaskId) not found."
                }

            case "cocoa_complete_task":
                let targetTaskId: UUID?
                if let idStr = args["task_id"] as? String, let parsed = UUID(uuidString: idStr) {
                    targetTaskId = parsed
                } else {
                    targetTaskId = taskStore.activeTaskId ?? taskStore.tasks.first?.id
                }

                if let targetId = targetTaskId, let task = taskStore.tasks.first(where: { $0.id == targetId }) {
                    if !task.isCompleted {
                        taskStore.toggleCompleted(id: targetId)
                    }
                    outputText = "Marked task '\(task.title)' as completed!"
                } else {
                    outputText = "Error: Task not found."
                }

            case "cocoa_start_timer":
                timerManager.start()
                outputText = "Focus timer started for active task (\(timerManager.formattedTime) remaining)."

            case "cocoa_pause_timer":
                timerManager.pause()
                outputText = "Focus timer paused at \(timerManager.formattedTime)."

            case "cocoa_reset_timer":
                timerManager.reset()
                outputText = "Focus timer reset to \(timerManager.formattedTime)."

            case "cocoa_update_notes":
                let newNotes = args["notes"] as? String ?? ""
                let append = args["append"] as? Bool ?? false

                let targetTaskId: UUID?
                if let idStr = args["task_id"] as? String, let parsed = UUID(uuidString: idStr) {
                    targetTaskId = parsed
                } else {
                    targetTaskId = taskStore.activeTaskId ?? taskStore.tasks.first?.id
                }

                if let targetId = targetTaskId, let task = taskStore.tasks.first(where: { $0.id == targetId }) {
                    // A blank line keeps appended feedback from merging into the block above it.
                    let updated = append ? "\(task.notes)\n\n\(newNotes)".trimmingCharacters(in: .whitespacesAndNewlines) : newNotes
                    taskStore.updateNotes(for: targetId, notes: updated)
                    outputText = "Updated notes for task '\(task.title)'."
                } else {
                    outputText = "Error: Task not found."
                }

            default:
                outputText = "Unknown tool: \(name)"
            }

            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5.0)

        return [
            "content": [
                [
                    "type": "text",
                    "text": outputText
                ]
            ]
        ]
    }

    // MARK: - Resource Execution
    private func executeResourceRead(uri: String) -> [String: Any] {
        var textContent = "{}"
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            let taskStore = WindowManager.shared.taskStore
            let timerManager = WindowManager.shared.timerManager

            switch uri {
            case "cocoa://tasks/today":
                let today = taskStore.todayTasks
                if let data = try? JSONEncoder().encode(today), let str = String(data: data, encoding: .utf8) {
                    textContent = str
                }
            case "cocoa://tasks/all":
                let all = taskStore.tasks
                if let data = try? JSONEncoder().encode(all), let str = String(data: data, encoding: .utf8) {
                    textContent = str
                }
            case "cocoa://timer/status":
                let statusDict: [String: Any] = [
                    "state": timerManager.state.rawValue,
                    "remainingSeconds": timerManager.remainingSeconds,
                    "totalSeconds": timerManager.totalSeconds,
                    "formattedTime": timerManager.formattedTime,
                    "progress": timerManager.progress,
                    "activeTaskId": taskStore.activeTaskId?.uuidString ?? "",
                    "activeTaskTitle": taskStore.activeTask?.title ?? ""
                ]
                if let data = try? JSONSerialization.data(withJSONObject: statusDict), let str = String(data: data, encoding: .utf8) {
                    textContent = str
                }
            default:
                textContent = "{\"error\": \"Resource not found: \(uri)\"}"
            }

            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3.0)

        return [
            "contents": [
                [
                    "uri": uri,
                    "mimeType": "application/json",
                    "text": textContent
                ]
            ]
        ]
    }

    // MARK: - 1-Click Client MCP Installer & Exporters
    public var effectiveBinaryPath: String {
        if let exec = Bundle.main.executablePath, FileManager.default.fileExists(atPath: exec) {
            return exec
        }
        if FileManager.default.fileExists(atPath: "/Applications/Cocoa.app/Contents/MacOS/Cocoa") {
            return "/Applications/Cocoa.app/Contents/MacOS/Cocoa"
        }
        return Bundle.main.bundlePath + "/Contents/MacOS/Cocoa"
    }

    public func installMCP(to target: AIClientTarget) throws {
        let fileURL = target.configURL
        let fileManager = FileManager.default

        let parentDir = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        var rootObj: [String: Any] = [:]
        if fileManager.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                rootObj = json
            }
        }

        var mcpServers = rootObj["mcpServers"] as? [String: Any] ?? [:]
        mcpServers["cocoa"] = [
            "command": effectiveBinaryPath,
            "args": ["--mcp"]
        ]
        rootObj["mcpServers"] = mcpServers

        let outputData = try JSONSerialization.data(withJSONObject: rootObj, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: fileURL, options: [.atomic])
    }

    public func uninstallMCP(from target: AIClientTarget) throws {
        let fileURL = target.configURL
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              var rootObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var mcpServers = rootObj["mcpServers"] as? [String: Any] else {
            return
        }

        mcpServers.removeValue(forKey: "cocoa")
        mcpServers.removeValue(forKey: "cocoa-local")
        rootObj["mcpServers"] = mcpServers

        let outputData = try JSONSerialization.data(withJSONObject: rootObj, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: fileURL, options: [.atomic])
    }

    public func installToAllDetectedClients() -> (success: [AIClientTarget], failed: [AIClientTarget]) {
        var success: [AIClientTarget] = []
        var failed: [AIClientTarget] = []
        for target in AIClientTarget.allCases {
            if target.isInstalledOnSystem {
                do {
                    try installMCP(to: target)
                    success.append(target)
                } catch {
                    failed.append(target)
                }
            }
        }
        return (success, failed)
    }

    public func configJSON(for target: AIClientTarget) -> String {
        return """
        {
          "mcpServers": {
            "cocoa": {
              "command": "\(effectiveBinaryPath)",
              "args": ["--mcp"]
            }
          }
        }
        """
    }

    public func claudeDesktopConfig() -> String {
        return configJSON(for: .claude)
    }

    public func cursorConfig() -> String {
        return configJSON(for: .cursor)
    }

    public func antigravityConfig() -> String {
        return configJSON(for: .antigravity)
    }

    // MARK: - Headless Stdio MCP Server (for Claude Desktop / Cursor CLI)
    /// A bridge to the running app: the app holds tasks in memory and would overwrite anything
    /// this process wrote to tasks.json itself, so every tool call goes through the app.
    public static func runStdioServer() {
        let standardInput = FileHandle.standardInput
        let standardOutput = FileHandle.standardOutput
        let settings = stdioSettings()

        while true {
            guard let lineData = readStdinLine(from: standardInput), !lineData.isEmpty else {
                break
            }

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let method = json["method"] as? String else {
                continue
            }

            let id = json["id"]

            var responseObj: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id ?? NSNull()
            ]

            switch method {
            case "initialize":
                responseObj["result"] = [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [
                        "tools": ["listChanged": true],
                        "resources": ["subscribe": false, "listChanged": false]
                    ],
                    "serverInfo": ["name": "cocoa-stdio", "version": "1.0.0"]
                ]

            case "notifications/initialized":
                continue

            case "ping":
                responseObj["result"] = [String: Any]()

            case "tools/list":
                responseObj["result"] = ["tools": MCPServerService.shared.availableToolsList()]

            case "tools/call", "resources/list", "resources/read":
                if let forwarded = forwardToRunningApp(lineData, port: settings.mcpServerPort, token: settings.mcpAuthToken) {
                    standardOutput.write(forwarded + Data("\n".utf8))
                    continue
                }
                let message = "Cocoa is not reachable on port \(settings.mcpServerPort). Open Cocoa, turn on the MCP server in Settings > AI & MCP, then try again."
                if method == "tools/call" {
                    responseObj["result"] = [
                        "content": [["type": "text", "text": message]],
                        "isError": true
                    ]
                } else {
                    responseObj["error"] = ["code": -32000, "message": message]
                }

            default:
                responseObj["error"] = ["code": -32601, "message": "Method not found: \(method)"]
            }

            if let respData = try? JSONSerialization.data(withJSONObject: responseObj),
               var respString = String(data: respData, encoding: .utf8) {
                respString.append("\n")
                if let outData = respString.data(using: .utf8) {
                    standardOutput.write(outData)
                }
            }
        }
    }

    /// Reads the file directly, because AppSettings.shared rewrites settings.json when it loads.
    private static func stdioSettings() -> AppSettingsPayload {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let settingsURL = appSupport.appendingPathComponent("Cocoa/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(AppSettingsPayload.self, from: data) else {
            return AppSettingsPayload()
        }
        return settings
    }

    private static func forwardToRunningApp(_ body: Data, port: Int, token: String) -> Data? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/mcp") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        final class Result: @unchecked Sendable { var data: Data? }
        let result = Result()
        let finished = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                result.data = data
            }
            finished.signal()
        }.resume()
        finished.wait()
        return result.data
    }

    private static func readStdinLine(from fileHandle: FileHandle) -> Data? {
        var buffer = Data()
        while true {
            let chunk = fileHandle.readData(ofLength: 1)
            if chunk.isEmpty {
                return buffer.isEmpty ? nil : buffer
            }
            if chunk[0] == 0x0A { // \n
                return buffer
            }
            buffer.append(chunk)
        }
    }
}
