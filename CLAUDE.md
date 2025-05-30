# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**MCPEasy** is a Ruby gem that provides multiple Model Context Protocol (MCP) servers for integrating with AI assistants like Claude Code. The gem includes MCP servers for:

- **Slack** - Post messages and list channels
- **Google Calendar** - Access and search calendar events
- **Google Drive** - Search and retrieve files with automatic format conversion
- **Google Meet** - Find and manage Google Meet meetings

Each MCP server provides both CLI functionality and MCP server capabilities for AI assistant integration.

## Dependencies and Setup

### Development Setup

Install dependencies:
```bash
bundle install
```

### Local Testing

Build and install the gem locally:
```bash
gem build mcpeasy.gemspec
gem install mcpeasy-*.gem
```

The gem is now available as the `mcpz` command system-wide.

## Common Commands

### Gem CLI Commands

```bash
# Setup configuration directories
mcpz setup

# Check configuration status
mcpz config

# Set up authentication
mcpz google auth
mcpz slack set_bot_token xoxb-your-token

# Use individual services
mcpz slack post general "Hello world"
mcpz gcal events --start "2024-01-01"
mcpz gdrive search "quarterly report"
mcpz gmeet upcoming

# Run MCP servers
mcpz slack mcp
mcpz gcal mcp
mcpz gdrive mcp
mcpz gmeet mcp
```

### Development Commands

Run linting:
```bash
bundle exec standardrb
```

Build gem:
```bash
gem build mcpeasy.gemspec
```

### MCP Server Configuration

For use with Claude Code, add to `.mcp.json`:
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

## Code Quality

**IMPORTANT**: When editing Ruby source code, you MUST run `bundle exec standardrb` after making changes and fix any linting issues that are reported.

## Architecture

### Gem Structure
```
lib/
├── mcpeasy.rb           # Main gem entry point
├── mcpeasy/             # Core gem functionality
│   ├── version.rb       # Gem version
│   ├── config.rb        # Configuration management
│   └── cli.rb           # Thor-based CLI interface
└── utilities/           # Individual MCP servers
    ├── slack/           # Slack integration
    ├── gcal/            # Google Calendar
    ├── gdrive/          # Google Drive
    └── gmeet/           # Google Meet
```

### Core Components

#### CLI (lib/mcpeasy/cli.rb)
- Thor-based command-line interface
- Subcommands for each service (slack, gcal, gdrive, gmeet)
- Configuration and setup commands
- Unified `mcpz` executable

#### Config (lib/mcpeasy/config.rb)
- Manages credentials and configuration
- Stores settings in `~/.config/mcpeasy/`
- Handles Google OAuth and Slack tokens

#### Individual MCP Servers
Each service directory follows a consistent structure with four key components:

##### `cli.rb` - Service-specific CLI Commands
- Extends Thor for command-line interface functionality
- Provides user-friendly CLI commands for the service
- Handles argument parsing and validation
- Calls into the `*_tool.rb` for actual service operations
- Example: `mcpz slack post` command implementation

##### `mcp.rb` - MCP Server Implementation
- Implements the Model Context Protocol JSON-RPC server
- Handles MCP initialization, tool registration, and request processing
- Translates MCP tool calls into `*_tool.rb` method calls
- Provides structured responses back to AI assistants
- Runs as a persistent server process when called with `mcpz [service] mcp`

##### `*_tool.rb` - Core Service Functionality
- Contains the main business logic for interacting with external APIs
- Handles authentication, API calls, error handling, and response formatting
- Shared between both CLI and MCP modes for consistency
- Service-specific naming: `slack_tool.rb`, `gcal_tool.rb`, `gdrive_tool.rb`, `gmeet_tool.rb`
- Designed to be framework-agnostic and reusable

##### `README.md` - Service-specific Documentation
- Detailed setup instructions for the specific service
- API credential configuration steps
- CLI usage examples and MCP server configuration
- Service-specific features and limitations
- Troubleshooting guides

### Execution Patterns
All services follow the same pattern:
1. **CLI mode**: Direct command-line usage via `mcpz [service] [command]`
2. **MCP mode**: JSON-RPC server mode via `mcpz [service] mcp`
3. **Authentication**: Service-specific auth handling with shared config storage