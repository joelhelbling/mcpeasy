# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby utility repository containing a Slack integration tool (`slack_poster.rb`) that provides programmatic access to Slack's Web API. It can operate in two modes:
1. **CLI script**: Direct command-line usage for posting messages to channels
2. **MCP server**: Model Context Protocol server for integration with AI assistants like Claude Code

## Dependencies and Setup

Install dependencies:
```bash
bundle install
```

The project requires:
- A Slack bot token (stored in `.env` file as `SLACK_BOT_TOKEN`)
- Ruby gems: `slack-ruby-client`, `dotenv`, and `standard`

## Common Commands

### CLI Mode

Run the Slack poster:
```bash
ruby slack_poster.rb <channel> <message> [username]
```

List available Slack channels:
```bash
ruby slack_poster.rb
```

### MCP Server Mode

Run as MCP server (typically configured in `.mcp.json`):
```bash
ruby slack_poster.rb --mcp
```

### Development Commands

Make script executable:
```bash
chmod +x slack_poster.rb
```

Run linting:
```bash
bundle exec standardrb
```

## Code Quality

**IMPORTANT**: When editing Ruby source code, you MUST run `bundle exec standardrb` after making changes and fix any linting issues that are reported.

## Architecture

The main components are:

### SlackPoster Class
- Wraps the Slack Web API client
- Provides error handling for API failures
- Tests authentication before operations
- Supports posting messages with optional custom usernames
- Can list available channels

### MCPMode Class
- Implements the Model Context Protocol (MCP) server
- Handles JSON-RPC requests for tool calls
- Provides three tools: `post_message`, `list_channels`, and `test_connection`
- Enables integration with AI assistants like Claude Code

### Execution Modes
- **CLI mode**: Direct command-line usage with argument parsing
- **MCP mode**: JSON-RPC server mode activated with `--mcp` flag

Both modes follow the pattern: authenticate, validate connection, then perform the requested operation.