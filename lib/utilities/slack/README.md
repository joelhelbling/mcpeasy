# Slack MCP Server

A Ruby-based Model Context Protocol (MCP) server that provides programmatic access to Slack's Web API. This server can operate in two modes:

1. **CLI script**: Direct command-line usage for posting messages to channels
2. **MCP server**: Integration with AI assistants like Claude Code

## Features

- 💬 **Post messages** to Slack channels with optional custom usernames
- 📋 **List channels** to see available public and private channels
- 🔐 **Bot token authentication** with secure credential storage
- 🛡️ **Error handling** with comprehensive API failure reporting
- ✅ **Connection testing** to verify authentication before operations

## Prerequisites

### 1. Ruby Environment

```bash
# Install Ruby dependencies
bundle install
```

Required gems:
- `slack-ruby-client` - Slack Web API client
- `standard` - Ruby code linting

### 2. Slack App Setup

#### Step 1: Create a Slack App

1. Go to https://api.slack.com/apps
2. Click **"Create New App"** → **"From scratch"**
3. Give your app a name and select your workspace
4. Note your app's details

#### Step 2: Configure OAuth Permissions

1. Go to **"OAuth & Permissions"** in the sidebar
2. Under **"Scopes"** → **"Bot Token Scopes"**, add these permissions:
   - `chat:write` - Required to post messages
   - `channels:read` - Optional, for listing public channels
   - `groups:read` - Optional, for listing private channels
3. Click **"Install to Workspace"** at the top
4. Copy the **"Bot User OAuth Token"** (starts with `xoxb-`)

#### Step 3: Configure Credentials

Configure your Slack bot token using the gem's configuration system:

```bash
mcpz slack set_bot_token xoxb-your-actual-slack-token
```

This will store your bot token securely in `~/.config/mcpeasy/slack.json`.

## Usage

### CLI Mode

#### Test Connection
```bash
mcpz slack test
```

#### Post Messages
```bash
# Post a simple message
mcpz slack post general "Hello from Ruby!"

# Post with a custom username
mcpz slack post general "Deployment completed successfully!" --username "DeployBot"

# Use channel with or without # prefix
mcpz slack post "#general" "Message with # prefix"
```

#### List Channels
```bash
# List all available channels
mcpz slack channels
```

### MCP Server Mode

#### Configuration for Claude Code

Add to your `.mcp.json` configuration:

```json
{
  "mcpServers": {
    "slack": {
      "command": "mcpz",
      "args": ["slack", "mcp"]
    }
  }
}
```

#### Run as Standalone MCP Server

```bash
mcpz slack mcp
```

The server provides these tools to Claude Code:

- **test_connection**: Test Slack API connectivity
- **post_message**: Post messages to channels with optional custom username
- **list_channels**: List available public and private channels

## Security & Permissions

### Required OAuth Scopes

- `chat:write` - Required to post messages
- `channels:read` - Optional, for listing public channels  
- `groups:read` - Optional, for listing private channels

### Local File Storage

- **Credentials**: Stored in `~/.config/mcpeasy/slack.json`
- **Logs**: Application logs for debugging

### Best Practices

1. **Never commit** bot tokens to version control
2. **Limit permissions** to only what's needed for your use case
3. **Regular rotation** of bot tokens (recommended annually)
4. **Monitor usage** through Slack's app management dashboard

## Troubleshooting

### Common Issues

#### "Invalid auth" Error
- Check that your bot token is correct and starts with `xoxb-`
- Re-run: `mcpz slack set_bot_token xoxb-your-actual-slack-token`
- Verify the token hasn't expired or been revoked
- Ensure the app is installed in your workspace

#### "Missing scope" Error
- Add the required OAuth scopes in your Slack app configuration
- Reinstall the app to workspace after adding scopes
- Required scopes: `chat:write` (minimum), `channels:read`, `groups:read` (optional)

#### "Channel not found" Error
- Verify the channel name is spelled correctly
- Ensure your bot has access to the channel (invite the bot if needed)
- Try using the channel ID instead of the name

#### "Bot not in channel" Error
- Invite your bot to the channel: `/invite @your-bot-name`
- Or use channels where the bot is already a member

### Testing the Setup

1. **Test CLI authentication**:
   ```bash
   mcpz slack test
   ```

2. **Test MCP server**:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | mcpz slack mcp
   ```

## Development

### File Structure

```
lib/utilities/slack/
├── cli.rb          # Thor-based CLI interface
├── mcp.rb          # MCP server implementation  
├── slack_tool.rb   # Slack Web API wrapper
└── README.md       # This file
```

### Adding New Features

1. **New API methods**: Add to `SlackTool` class
2. **New CLI commands**: Add to `SlackCLI` class  
3. **New MCP tools**: Add to `MCPServer` class

### Testing

```bash
# Run Ruby linting
bundle exec standardrb

# Test CLI commands
mcpz slack test
mcpz slack channels

# Test MCP server manually
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | mcpz slack mcp
```

## Contributing

1. Follow existing code patterns and style
2. Add comprehensive error handling
3. Update this README for new features
4. Test both CLI and MCP modes

## License

This project follows the same license as the parent repository.