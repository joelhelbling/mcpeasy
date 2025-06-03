# Notion MCP Server

A Ruby-based Model Context Protocol (MCP) server that provides programmatic access to Notion's API. This server can operate in two modes:

1. **CLI script**: Direct command-line usage for searching pages, databases, and retrieving content
2. **MCP server**: Integration with AI assistants like Claude Code

## Features

- 🔍 **Search pages** and databases in your Notion workspace
- 📄 **Get page details** including properties and metadata
- 📝 **Retrieve page content** as formatted text
- 🗃️ **Query databases** to find specific entries
- 👥 **List users** in your Notion workspace
- 👤 **Get user details** including email and avatar
- 🤖 **Get bot information** for the integration
- 🔐 **API key authentication** with secure credential storage
- 🛡️ **Error handling** with comprehensive API failure reporting
- ✅ **Connection testing** to verify authentication before operations

## Prerequisites

### 1. Ruby Environment

```bash
# Install Ruby dependencies
bundle install
```

Required gems:
- `standard` - Ruby code linting

### 2. Notion Integration Setup

#### Step 1: Create a Notion Integration

1. Go to https://www.notion.so/my-integrations
2. Click **"New integration"**
3. Give your integration a name (e.g., "MCPEasy Integration")
4. Select the workspace you want to integrate with
5. Click **"Submit"**
6. Copy the **"Internal Integration Token"** (starts with `secret_`)

#### Step 2: Grant Database/Page Access

Your integration needs explicit access to pages and databases:

1. **For databases**: Open the database → Click "..." → "Add connections" → Select your integration
2. **For pages**: Open the page → Click "..." → "Add connections" → Select your integration

**Important**: The integration can only access content you explicitly share with it.

#### Step 3: Configure Credentials

Configure your Notion API key using the gem's configuration system:

```bash
mcpz notion set_api_key secret_your-actual-notion-token
```

This will store your API key securely in `~/.config/mcpeasy/notion.json`.

## Usage

### CLI Mode

#### Test Connection
```bash
mcpz notion test
```

#### Search Pages
```bash
# Search all pages
mcpz notion search_pages

# Search with query
mcpz notion search_pages "meeting notes"

# Limit results
mcpz notion search_pages "project" --limit 5
```

#### Search Databases
```bash
# Search all databases
mcpz notion search_databases

# Search with query
mcpz notion search_databases "tasks"

# Limit results
mcpz notion search_databases "calendar" --limit 3
```

#### Get Page Details
```bash
# Get page metadata and properties
mcpz notion get_page PAGE_ID
```

#### Get Page Content
```bash
# Get the text content of a page
mcpz notion get_content PAGE_ID
```

#### Query Database Entries
```bash
# Get entries from a database
mcpz notion query_database DATABASE_ID

# Limit results
mcpz notion query_database DATABASE_ID --limit 20
```

#### User Management
```bash
# List all users in workspace
mcpz notion list_users

# Get details for a specific user
mcpz notion get_user USER_ID

# Get bot integration details
mcpz notion bot_info
```

### MCP Server Mode

#### Configuration for Claude Code

Add to your `.mcp.json` configuration:

```json
{
  "mcpServers": {
    "notion": {
      "command": "mcpz",
      "args": ["notion", "mcp"]
    }
  }
}
```

#### Run as Standalone MCP Server

```bash
mcpz notion mcp
```

The server provides these tools to Claude Code:

- **test_connection**: Test Notion API connectivity
- **search_pages**: Search for pages in your workspace
- **search_databases**: Find databases in your workspace
- **get_page**: Get detailed information about a specific page
- **get_page_content**: Retrieve the text content of a page
- **query_database**: Query entries within a specific database
- **list_users**: List all users in the workspace
- **get_user**: Get details of a specific user
- **get_bot_user**: Get information about the integration bot

## Security & Permissions

### Required Notion Permissions

Your integration needs to be added to each page/database you want to access:

- **Read content**: Required for all operations
- **No additional permissions needed**: This integration is read-only

### Local File Storage

- **Credentials**: Stored in `~/.config/mcpeasy/notion.json`
- **Logs**: Application logs for debugging

### Best Practices

1. **Never commit** API keys to version control
2. **Grant minimal access** - only share necessary pages/databases with the integration
3. **Regular rotation** of API keys (recommended annually)
4. **Monitor usage** through Notion's integration settings

## Troubleshooting

### Common Issues

#### "Authentication failed" Error
- Check that your API key is correct and starts with `secret_`
- Re-run: `mcpz notion set_api_key secret_your-actual-notion-token`
- Verify the integration hasn't been deleted or disabled
- Ensure you're using an "Internal Integration Token", not a public OAuth token

#### "Access forbidden" Error
- The integration doesn't have access to the requested resource
- Add the integration to the specific page or database:
  - Open page/database → "..." menu → "Add connections" → Select your integration

#### "Resource not found" Error
- Verify the page/database ID is correct
- Ensure the integration has been granted access to that specific resource
- Check that the page/database hasn't been deleted

#### "Rate limit exceeded" Error
- Notion has rate limits (3 requests per second)
- Wait a moment and try again
- The tool includes automatic retry logic for rate limits

### Finding Page and Database IDs

1. **From Notion URL**: 
   - Page: `https://notion.so/Page-Title-32alphanumeric` → ID is the 32-character string
   - Database: `https://notion.so/database/32alphanumeric` → ID is the 32-character string

2. **From search results**: Use `mcpz notion search_pages` or `mcpz notion search_databases`

### Testing the Setup

1. **Test CLI authentication**:
   ```bash
   mcpz notion test
   ```

2. **Test MCP server**:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | mcpz notion mcp
   ```

3. **Test basic search**:
   ```bash
   mcpz notion search_pages
   ```

## Development

### File Structure

```
lib/utilities/notion/
├── cli.rb          # Thor-based CLI interface
├── mcp.rb          # MCP server implementation  
├── service.rb      # Notion API wrapper
└── README.md       # This file
```

### Adding New Features

1. **New API methods**: Add to `Service` class
2. **New CLI commands**: Add to `CLI` class  
3. **New MCP tools**: Add to `MCPServer` class

### API Coverage

Currently implemented Notion API endpoints:
- `/search` - Search pages and databases
- `/pages/{id}` - Get page details
- `/blocks/{id}/children` - Get page content blocks
- `/databases/{id}/query` - Query database entries
- `/users` - List all users in workspace
- `/users/{id}` - Get specific user details
- `/users/me` - Get bot user information and test authentication

### Testing

```bash
# Run Ruby linting
bundle exec standardrb

# Test CLI commands
mcpz notion test
mcpz notion search_pages

# Test MCP server manually
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | mcpz notion mcp
```

## Contributing

1. Follow existing code patterns and style
2. Add comprehensive error handling
3. Update this README for new features
4. Test both CLI and MCP modes

## License

This project follows the same license as the parent repository.