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
- `dotenv` - Environment variable management

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

#### Step 4: Configure Environment Variables

1. Copy the `env.template` file to `.env` in the project root:
   ```bash
   cp env.template .env
   ```

2. Add your Google OAuth credentials to `.env`:
   ```bash
   # Google Drive API credentials
   GOOGLE_CLIENT_ID="your_client_id_here.apps.googleusercontent.com"
   GOOGLE_CLIENT_SECRET="your_client_secret_here"
   ```

   Extract these values from the JSON file you downloaded in Step 3.

## Authentication

Before using the Google Drive MCP server, you need to authenticate with Google:

```bash
cd utilities/gdrive
ruby cli.rb auth
```

This will:
1. Open a browser window for Google OAuth
2. Ask you to sign in and authorize the application
3. Prompt you to enter the authorization code
4. Save credentials to `.gdrive-token.json`

**Note**: The credentials are saved locally and will be automatically refreshed when needed.

## Usage

### CLI Mode

#### Test Connection
```bash
ruby cli.rb test
```

#### Search for Files
```bash
# Basic search
ruby cli.rb search "quarterly report"

# Limit results
ruby cli.rb search "meeting notes" --max-results 5
```

#### List Recent Files
```bash
# List 20 most recent files
ruby cli.rb list

# Limit results
ruby cli.rb list --max-results 10
```

#### Get File Content
```bash
# Display content in terminal
ruby cli.rb get "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"

# Save to file
ruby cli.rb get "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms" --output document.md
```

### MCP Server Mode

#### Configuration for Claude Code

Add to your `.mcp.json` configuration:

```json
{
  "mcpServers": {
    "gdrive": {
      "command": "ruby",
      "args": ["utilities/gdrive/mcp.rb"],
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

- **Credentials**: Stored in `.gdrive-token.json` (git-ignored)
- **Logs**: Stored in `./logs/mcp_gdrive_*.log`

### Best Practices

1. **Never commit** credential files to version control
2. **Limit scope** to read-only access
3. **Regular rotation** of OAuth credentials (recommended annually)
4. **Monitor usage** through Google Cloud Console

## Troubleshooting

### Common Issues

#### "Authentication required" Error
- Run `ruby cli.rb auth` to authenticate
- Check that `.gdrive-token.json` exists and is valid
- Verify your `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in `.env`

#### "Bad credentials" Error
- Regenerate OAuth credentials in Google Cloud Console
- Update `.env` file with new credentials
- Re-run authentication: `ruby cli.rb auth`

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
   ruby cli.rb test
   ```

2. **Test MCP server**:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ruby mcp.rb
   ```

## Development

### File Structure

```
utilities/gdrive/
├── cli.rb          # Thor-based CLI interface
├── mcp.rb          # MCP server implementation  
├── gdrive_tool.rb  # Google Drive API wrapper
└── README.md       # This file
```

### Adding New Features

1. **New API methods**: Add to `GdriveTool` class
2. **New CLI commands**: Add to `GdriveCLI` class  
3. **New MCP tools**: Add to `MCPServer` class

### Testing

```bash
# Run Ruby linting
bundle exec standardrb

# Test CLI commands
ruby cli.rb test
ruby cli.rb list --max-results 5

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