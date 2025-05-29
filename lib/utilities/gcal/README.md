# Google Calendar MCP Server

A Ruby-based Model Context Protocol (MCP) server that provides programmatic access to Google Calendar. This server can operate in two modes:

1. **CLI script**: Direct command-line usage for listing events and calendar information
2. **MCP server**: Integration with AI assistants like Claude Code

## Features

- 📅 **List events** from your Google Calendar with date range filtering
- 📋 **Get calendar information** including calendar metadata
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
- `dotenv` - Environment variable management

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

#### Step 4: Configure Environment Variables

1. Copy the `env.template` file to `.env` in the project root:
   ```bash
   cp env.template .env
   ```

2. Add your Google OAuth credentials to `.env`:
   ```bash
   # Google API credentials (shared with gdrive utility)
   GOOGLE_CLIENT_ID="your_client_id_here.apps.googleusercontent.com"
   GOOGLE_CLIENT_SECRET="your_client_secret_here"
   ```

   Extract these values from the JSON file you downloaded in Step 3.

**Note**: If you've already set up the gdrive utility, you can use the same OAuth credentials since both utilities share the same authentication system.

## Authentication

Before using the Google Calendar MCP server, you need to authenticate with Google:

```bash
cd utilities/gcal
ruby cli.rb auth
```

This will:
1. Open a browser window for Google OAuth
2. Ask you to sign in and authorize the application
3. Prompt you to enter the authorization code
4. Save credentials to `.gcal-token.json`

**Note**: The credentials are saved locally and will be automatically refreshed when needed.

## Usage

### CLI Mode

#### Test Connection
```bash
ruby cli.rb test
```

#### List Events
```bash
# List today's events
ruby cli.rb events

# List events for a specific date range
ruby cli.rb events --start "2024-01-01" --end "2024-01-31"

# Limit results
ruby cli.rb events --max-results 10
```

#### List Calendars
```bash
ruby cli.rb calendars
```

### MCP Server Mode

#### Configuration for Claude Code

Add to your `.mcp.json` configuration:

```json
{
  "mcpServers": {
    "gcal": {
      "command": "ruby",
      "args": ["utilities/gcal/mcp.rb"],
      "cwd": "/path/to/your/project"
    }
  }
}
```

#### Run as Standalone MCP Server

```bash
ruby mcp.rb
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

- **Credentials**: Stored in `.gcal-token.json` (git-ignored)
- **Logs**: Stored in `./logs/mcp_gcal_*.log`

### Best Practices

1. **Never commit** credential files to version control
2. **Limit scope** to read-only access
3. **Regular rotation** of OAuth credentials (recommended annually)
4. **Monitor usage** through Google Cloud Console

## Troubleshooting

### Common Issues

#### "Authentication required" Error
- Run `ruby cli.rb auth` to authenticate
- Check that `.gcal-token.json` exists and is valid
- Verify your `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in `.env`

#### "Bad credentials" Error
- Regenerate OAuth credentials in Google Cloud Console
- Update `.env` file with new credentials
- Re-run authentication: `ruby cli.rb auth`

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
   ruby cli.rb test
   ```

2. **Test MCP server**:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ruby mcp.rb
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
ruby cli.rb test
ruby cli.rb events --max-results 5

# Test MCP server manually
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | ruby mcp.rb
```

## Contributing

1. Follow existing code patterns and style
2. Add comprehensive error handling
3. Update this README for new features
4. Test both CLI and MCP modes

## License

This project follows the same license as the parent repository.