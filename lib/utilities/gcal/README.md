# Google Calendar MCP Server

A Ruby-based Model Context Protocol (MCP) server that provides programmatic access to Google Calendar. This server can operate in two modes:

1. **CLI script**: Direct command-line usage for listing events and calendar information
2. **MCP server**: Integration with AI assistants like Claude Code

## Features

- 📅 **List events** from your Google Calendar with date range filtering
- 📋 **List calendars** and view calendar metadata
- 🔍 **Search events** by text content
- 🔐 **OAuth 2.0 authentication** with credential persistence (shares credentials with gdrive utility)
- 🛡️ **Error handling** with retry logic and comprehensive logging

## Prerequisites

### 1. Ruby Environment

```bash
# Install Ruby dependencies
bundle install
```

Required gems:
- `google-apis-calendar_v3` - Google Calendar API client
- `googleauth` - Google OAuth authentication
- `thor` - CLI framework

### 2. Google Cloud Platform Setup

#### Step 1: Create a Google Cloud Project

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Note your project ID

#### Step 2: Enable the Google Calendar API

1. In the Cloud Console, go to **APIs & Services > Library**
2. Search for "Google Calendar API"
3. Click on it and click **Enable**

#### Step 3: Create OAuth 2.0 Credentials

1. Go to **APIs & Services > Credentials**
2. Click **+ Create Credentials > OAuth client ID**
3. If prompted, configure the OAuth consent screen:
   - Choose **External** user type
   - Fill in required fields (app name, user support email)
   - Add your email to test users
   - **Scopes**: Add `https://www.googleapis.com/auth/calendar.readonly`
4. For Application type, choose **Desktop application**
5. Give it a name (e.g., "Google Calendar MCP Server")
6. **Add Authorized redirect URI**: `http://localhost:8080`
7. Click **Create**
8. Download the JSON file containing your client ID and secret

#### Step 4: Configure OAuth Credentials

The Google OAuth credentials will be configured during the authentication process. You'll need the Client ID and Client Secret from the JSON file you downloaded in Step 3.

**Note**: All Google services (Calendar, Drive, Meet) share the same authentication system, so you only need to authenticate once.

## Authentication

Before using the Google Calendar MCP server, you need to authenticate with Google:

```bash
mcpz google auth
```

This will open a browser for Google OAuth authorization and save credentials to `~/.config/mcpeasy/google/token.json`. The credentials are shared with all Google services and will be automatically refreshed when needed.

## Usage

### CLI Mode

#### Test Connection
```bash
mcpz gcal test
```

#### List Events
```bash
# List today's events
mcpz gcal events

# List events for a specific date range
mcpz gcal events --start "2024-01-01" --end "2024-01-31"

# Limit results
mcpz gcal events --max-results 10
```

#### List Calendars
```bash
mcpz gcal calendars
```

### MCP Server Mode

#### Configuration for Claude Code

Add to your `.mcp.json` configuration:

```json
{
  "mcpServers": {
    "gcal": {
      "command": "mcpz",
      "args": ["gcal", "mcp"]
    }
  }
}
```

#### Run as Standalone MCP Server

```bash
mcpz gcal mcp
```

The server provides these tools to Claude Code:

- **test_connection**: Test Google Calendar API connectivity
- **list_events**: List calendar events with optional date filtering
- **list_calendars**: List available calendars
- **search_events**: Search for events by text content

## Security & Permissions

### Required OAuth Scopes

- `https://www.googleapis.com/auth/calendar.readonly` - Read-only access to Google Calendar

### Local File Storage

- **Credentials**: Stored in `~/.config/mcpeasy/google/token.json`
- **Logs**: Stored in `./logs/mcp_gcal_*.log`

### Best Practices

1. **Never commit** credential files to version control
2. **Limit scope** to read-only access
3. **Regular rotation** of OAuth credentials (recommended annually)
4. **Monitor usage** through Google Cloud Console

## Troubleshooting

### Common Issues

#### "Authentication required" Error
- Run `mcpz google auth` to authenticate
- Check that `~/.config/mcpeasy/google/token.json` exists and is valid
- Verify your Google OAuth credentials are configured correctly

#### "Bad credentials" Error
- Regenerate OAuth credentials in Google Cloud Console
- Re-run authentication: `mcpz google auth`

#### "Calendar API has not been used" Error
- Ensure the Google Calendar API is enabled in your project
- Go to Google Cloud Console > APIs & Services > Library
- Search for "Google Calendar API" and enable it

#### "Access denied" Error
- Ensure the Google Calendar API is enabled in your project
- Check that your OAuth consent screen includes the calendar.readonly scope
- Verify you're using the correct Google account

### Debug Logging

Check the log files for detailed error information:

```bash
# View recent errors
tail -f logs/mcp_gcal_error.log

# View startup logs
tail -f logs/mcp_gcal_startup.log
```

### Testing the Setup

1. **Test CLI authentication**:
   ```bash
   mcpz gcal test
   ```

2. **Test MCP server**:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | mcpz gcal mcp
   ```

## Development

### File Structure

```
utilities/gcal/
├── cli.rb          # Thor-based CLI interface
├── mcp.rb          # MCP server implementation  
├── gcal_tool.rb    # Google Calendar API wrapper
└── README.md       # This file
```

### Adding New Features

1. **New API methods**: Add to `GcalTool` class
2. **New CLI commands**: Add to `GcalCLI` class  
3. **New MCP tools**: Add to `MCPServer` class

### Testing

```bash
# Run Ruby linting
bundle exec standardrb

# Test CLI commands
mcpz gcal test
mcpz gcal events --max-results 5

# Test MCP server manually
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | mcpz gcal mcp
```

## Contributing

1. Follow existing code patterns and style
2. Add comprehensive error handling
3. Update this README for new features
4. Test both CLI and MCP modes

## License

This project follows the same license as the parent repository.
