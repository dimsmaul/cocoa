<div align="center">
  <img src="Resources/CocoaLogo.png" width="140" height="140" alt="Cocoa Logo" />
  <h1>Cocoa 🍫</h1>
  <p><strong>Native macOS Focus & Task Companion</strong></p>
  <p>Engineered with Swift 6, SwiftUI & AppKit · Dynamic Island · Floating Tower · Local-First · Supabase Sync · Native MCP Server</p>
</div>

---

## Features

1. **Multi-Surface Window Experience**:
   - **Notch Mode (Dynamic Island Pill)**: Snaps directly into the MacBook camera notch (or top-center on external monitors) with smooth expansion on hover and click.
   - **Floating Window Mode (Tower)**: A glassmorphic, compact floating widget that can be positioned anywhere on screen.
   - **Main App Dashboard**: Full sidebar organization with custom project lists, task details inspector, and Kanban view.
2. **Notch Protection & Hover Behavior**:
   - **Hover Debounce Delay**: When idle, hovering requires a short configurable delay (~350ms) before expanding to prevent accidental triggers while navigating menu bars.
   - **Active Timer Shield**: When a focus timer is running, hovering will not expand the island, preventing distraction. Full detail opens only on explicit click.
   - **Auto-Collapse**: Moving the mouse away collapses the expanded island back into the minimal notch pill.
3. **Task & Project Management**:
   - Board views: Today, Upcoming, Backlog, and Completed.
   - Kanban board view filtered per project list.
   - Subtasks and checklists with progress indicators.
   - Native rich text notes for deep work contexts.
   - Local-first persistence (`~/Library/Application Support/Cocoa/tasks.json`).
4. **Model Context Protocol (MCP) Server**:
   - Built-in headless Stdio (`Cocoa --mcp`) and HTTP/SSE JSON-RPC 2.0 server.
   - Exposes 9 native tools to external AI agents (`cocoa_list_tasks`, `cocoa_create_task`, `cocoa_start_timer`, `cocoa_complete_task`, etc.).
   - 1-Click "Apply" integration for Claude Desktop, Cursor IDE, and Antigravity.
5. **Cloud Sync & Automatic Migration**:
   - Local-first architecture with optional Supabase real-time sync.
   - Automated schema discovery and migration on initial sync without requiring manual SQL setup.
   - Offline resilience with dual persistence in `settings.json` and `tasks.json`.

---

## Model Context Protocol (MCP) Setup

Cocoa provides a native MCP server so your AI coding agents and desktop assistants can read and manage your tasks, active focus session, and timers in real-time.

You can connect directly from **Cocoa Settings (`Cmd + ,`) > AI & MCP Server** by clicking **"Apply"** next to your preferred AI tool, or configure manually:

### Claude Desktop (`claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "cocoa": {
      "command": "/Applications/Cocoa.app/Contents/MacOS/Cocoa",
      "args": ["--mcp"]
    }
  }
}
```

### Antigravity (`~/.gemini/config/mcp_config.json`):
```json
{
  "mcpServers": {
    "cocoa": {
      "command": "/Applications/Cocoa.app/Contents/MacOS/Cocoa",
      "args": ["--mcp"]
    }
  }
}
```

### Cursor IDE (`~/.cursor/mcp.json`):
```json
{
  "mcpServers": {
    "cocoa": {
      "command": "/Applications/Cocoa.app/Contents/MacOS/Cocoa",
      "args": ["--mcp"]
    }
  }
}
```

---

## Cloud Sync (Supabase)

Cocoa is local-first by default. To enable cross-device cloud sync:
1. Open **Cocoa Settings (`Cmd + ,`) > Supabase Sync**.
2. Toggle **Enable Cloud Sync**.
3. Enter your **Project URL** and **Anon API Key**.
4. Click **Test Connection** or **Sync Now**. Cocoa automatically verifies and adapts to the database schema.

---

## Build & Release

### Prerequisites
- macOS 14.0 (Sonoma) or newer
- Xcode 15+ / Swift 6.0 toolchain

### Build Application Bundle:
```bash
cd Cocoa
./build-app.sh
open Cocoa.app
```

### Run via Swift CLI:
```bash
cd Cocoa
swift run
```

### Automated CI/CD & DMG Releases:
Every release tag (e.g. `v1.0.0`) pushed to GitHub automatically triggers the GitHub Actions workflow to build and package `Cocoa.dmg` as a downloadable GitHub Release asset.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
