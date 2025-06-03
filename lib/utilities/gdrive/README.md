# Google Drive MCP Server

A Ruby-based Model Context Protocol (MCP) server that provides programmatic access to Google Drive. This server can operate in two modes:

1. **CLI script**: Direct command-line usage for searching, listing, and retrieving files
2. **MCP server**: Integration with AI assistants like Claude Code

## Features

- 🔍 **Search files** by content or name in Google Drive
- 📂 **List recent files** with metadata
- 📄 **Retrieve file content** with automatic format conversion
- 🔄 **Export Google Workspace documents**:
  - Google Docs → Markdown
  - Google Sheets → CSV  
  - Google Presentations → Plain text
  - Google Drawings → PNG
- 🔐 **OAuth 2.0 authentication** with credential persistence
- 🛡️ **Error handling** with retry logic and comprehensive logging

## Prerequisites

### 1. Ruby Environment

```bash
# Install Ruby dependencies
bundle install
```

Required gems:
- `google-apis-drive_v3` - Google Drive API client
- `googleauth` - Google OAuth authentication
- `thor` - CLI framework

### 2. Google Cloud Platform Setup

#### Step 1: Create a Google Cloud Project

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Note your project ID

#### Step 2: Enable the Google Drive API

1. In the Cloud Console, go to **APIs & Services > Library**
2. Search for "Google Drive API"
3. Click on it and click **Enable**

#### Step 3: Create OAuth 2.0 Credentials

1. Go to **APIs & Services > Credentials**
2. Click **+ Create Credentials > OAuth client ID**
3. If prompted, configure the OAuth consent screen:
   - Choose **External** user type
   - Fill in required fields (app name, user support email)
   - Add your email to test users
   - Scopes: you can leave this empty for now
4. For Application type, choose **Desktop application**
5. Give it a name (e.g., "Google Drive MCP Server")
6. **Add Authorized redirect URI**: `http://localhost:8080`
7. Click **Create**
8. Download the JSON file containing your client ID and secret

#### Step 4: Configure OAuth Credentials

The Google OAuth credentials will be configured during the authentication process. You'll need the Client ID and Client Secret from the JSON file you downloaded in Step 3.

**Note**: All Google services (Calendar, Drive, Meet) share the same authentication system, so you only need to authenticate once.

## Authentication

Before using the Google Drive MCP server, you need to authenticate with Google:

```bash
mcpz google auth
```

This will open a browser for Google OAuth authorization and save credentials to `~/.config/mcpeasy/google/token.json`. The credentials are shared with all Google services and will be automatically refreshed when needed.

## Usage

### CLI Mode

#### Test Connection
```bash
mcpz gdrive test
```

#### Search for Files
```bash
# Basic search
mcpz gdrive search "quarterly report"

# Limit results
mcpz gdrive search "meeting notes" --max-results 5
```

#### List Recent Files
```bash
# List 20 most recent files
mcpz gdrive list

# Limit results
mcpz gdrive list --max-results 10
```

#### Get File Content
```bash
# Display content in terminal
mcpz gdrive get "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"

# Save to file
mcpz gdrive get "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms" --output document.md
```

### MCP Server Mode

#### Configuration for Claude Code

Add to your `.mcp.json` configuration:

```json
{
  "mcpServers": {
    "gdrive": {
      "command": "mcpz",
      "args": ["gdrive", "mcp"]
    }
  }
}
```

#### Run as Standalone MCP Server

```bash
mcpz gdrive mcp
```

The server provides these tools to Claude Code:

- **test_connection**: Test Google Drive API connectivity
- **search_files**: Search for files by content or name
- **get_file_content**: Retrieve content of a specific file
- **list_files**: List recent files in Google Drive

## File Format Support

### Google Workspace Documents

The server automatically exports Google Workspace documents to readable formats:

| Document Type | Export Format | File Extension |
|---------------|---------------|----------------|
| Google Docs | Markdown | `.md` |
| Google Sheets | CSV | `.csv` |
| Google Slides | Plain text | `.txt` |
| Google Drawings | PNG image | `.png` |

### Regular Files

All other file types (PDFs, images, text files, etc.) are downloaded in their original format.

## Security & Permissions

### Required OAuth Scopes

- `https://www.googleapis.com/auth/drive.readonly` - Read-only access to Google Drive

### Local File Storage

- **Credentials**: Stored in `~/.config/mcpeasy/google/token.json`
- **Logs**: Stored in `./logs/mcp_gdrive_*.log`

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

#### "Quota exceeded" Error
- Check your Google Cloud Console for API quota limits
- Wait for quota reset (usually daily)
- Consider requesting higher quota limits

#### "Access denied" Error
- Ensure the Google Drive API is enabled in your project
- Check that your OAuth consent screen is properly configured
- Verify you're using the correct Google account

### Debug Logging

Check the log files for detailed error information:

```bash
# View recent errors
tail -f logs/mcp_gdrive_error.log

# View startup logs
tail -f logs/mcp_gdrive_startup.log
```

### Testing the Setup

1. **Test CLI authentication**:
   ```bash
   mcpz gdrive test
   ```

2. **Test MCP server**:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | mcpz gdrive mcp
   ```

## Development

### File Structure

```
utilities/gdrive/
├── cli.rb          # Thor-based CLI interface
├── mcp.rb          # MCP server implementation  
├── service.rb      # Google Drive API wrapper
└── README.md       # This file
```

### Adding New Features

1. **New API methods**: Add to `Service` class
2. **New CLI commands**: Add to `CLI` class  
3. **New MCP tools**: Add to `MCPServer` class

### Testing

```bash
# Run Ruby linting
bundle exec standardrb

# Test CLI commands
mcpz gdrive test
mcpz gdrive list --max-results 5

# Test MCP server manually
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | mcpz gdrive mcp
```

## Contributing

1. Follow existing code patterns and style
2. Add comprehensive error handling
3. Update this README for new features
4. Test both CLI and MCP modes

## License

This project follows the same license as the parent repository.