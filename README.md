# MCPEasy

A Ruby gem that provides multiple Model Context Protocol (MCP) servers for integrating with AI assistants like Claude Code. Each MCP server provides programmatic access to popular web services and APIs.

## Installation

Install the gem globally:

```bash
gem install mcpeasy
```

This makes the `mcpz` command available system-wide for both CLI usage and MCP server configuration.

## Available MCP Servers

This gem includes the following MCP servers, each providing both CLI and MCP server functionality:

### 🗣️ [Slack](./lib/utilities/slack/)
Post messages to Slack channels and list available channels.
- CLI: Direct message posting with custom usernames
- MCP: Integration for AI assistants to send Slack notifications

### 📅 [Google Calendar](./lib/utilities/gcal/)
Access and search Google Calendar events.
- CLI: List events, search by date range, view calendar information
- MCP: AI assistant access to calendar data and event search

### 📂 [Google Drive](./lib/utilities/gdrive/)
Search and retrieve files from Google Drive with automatic format conversion.
- CLI: Search files, list recent files, retrieve content
- MCP: AI assistant access to Drive files and documents

### 🎥 [Google Meet](./lib/utilities/gmeet/)
Find and manage Google Meet meetings from your calendar.
- CLI: List meetings, search by content, get meeting URLs
- MCP: AI assistant access to upcoming meetings and direct links

## Quick Start

### 1. Configuration Setup

Configure your API credentials for each service you plan to use:

```bash
# For Slack
mcpz slack set_bot_token xoxb-your-slack-token

# For Google services (Calendar, Drive, Meet)
mcpz google auth
```

Credentials are stored securely in `~/.config/mcpeasy/` (see individual server documentation for specific setup requirements).

### 2. CLI Usage

Each MCP server can be used directly from the command line:

```bash
# Slack
mcpz slack post general "Hello from Ruby!"

# Google Calendar  
mcpz gcal events --start "2024-01-01"

# Google Drive
mcpz gdrive search "quarterly report"

# Google Meet
mcpz gmeet upcoming
```

### 3. MCP Server Configuration

For use with Claude Code, add servers to your `.mcp.json`:

```json
{
  "mcpServers": {
    "slack": {
      "command": "mcpz",
      "args": ["slack", "mcp"]
    },
    "gcal": {
      "command": "mcpz", 
      "args": ["gcal", "mcp"]
    },
    "gdrive": {
      "command": "mcpz",
      "args": ["gdrive", "mcp"]
    },
    "gmeet": {
      "command": "mcpz",
      "args": ["gmeet", "mcp"]
    }
  }
}
```

## Development

### Setup

1. Clone the repository and install dependencies:
   ```bash
   git clone <repository-url>
   cd mcpeasy
   bundle install
   ```

2. Create configuration directories (if not automatically created):
   ```bash
   # Run manually during development
   bundle exec ruby -r "./lib/mcpeasy/setup" -e "Mcpeasy::Setup.create_config_directories"
   
   # Or use the CLI command after building the gem locally
   bin/mcpz setup
   ```

### Code Quality

Run linting before committing changes:

```bash
bundle exec standardrb
```

### Project Structure

```
lib/
├── mcpeasy.rb           # Main gem file
├── mcpeasy/             # Gem core functionality
└── utilities/           # MCP servers
    ├── slack/           # Slack integration
    ├── gcal/            # Google Calendar
    ├── gdrive/          # Google Drive  
    └── gmeet/           # Google Meet
```

### Contributing

1. Follow existing code patterns and Ruby style conventions
2. Add comprehensive error handling and logging
3. Update relevant documentation for new features
4. Test both CLI and MCP server modes
5. Run `bundle exec standardrb` before submitting changes

## License

This project is licensed under the MIT License.

## Support

For issues, questions, or contributions, please visit the project repository.