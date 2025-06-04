# Gmail MCP Server

A Model Context Protocol (MCP) server for Gmail integration with AI assistants.

## Features

- **List emails** with filtering by date range, sender, subject, labels, and read/unread status
- **Search emails** using Gmail's powerful search syntax
- **Get email content** including full body, headers, and attachment information
- **Send emails** with support for CC, BCC, and reply-to fields
- **Reply to emails** with automatic threading and optional quoted text
- **Email management** - mark as read/unread, add/remove labels, archive, and trash
- **Test connection** to verify Gmail API connectivity

## Prerequisites

1. **Google Cloud Project** with Gmail API enabled
2. **OAuth 2.0 credentials** (client ID and client secret)
3. **Ruby environment** with required gems

## Setup

### 1. Enable Gmail API

1. Go to the [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project or select an existing one
3. Enable the Gmail API:
   - Navigate to "APIs & Services" > "Library"
   - Search for "Gmail API" and click "Enable"

### 2. Create OAuth 2.0 Credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth 2.0 Client IDs"
3. Set application type to "Desktop application"
4. Download the JSON file containing your credentials

### 3. Install and Configure MCPEasy

```bash
# Install the gem
gem install mcpeasy

# Set up configuration directories
mcpz setup

# Save your Google credentials
mcpz set_google_credentials path/to/your/credentials.json

# Authenticate with Gmail (will open browser for OAuth)
mcpz gmail auth
```

### 4. Verify Setup

```bash
# Test the connection
mcpz gmail test
```

## CLI Usage

### Authentication
```bash
# Authenticate with Gmail API
mcpz gmail auth
```

### Listing Emails
```bash
# List recent emails
mcpz gmail list

# Filter by date range
mcpz gmail list --start_date 2024-01-01 --end_date 2024-01-31

# Filter by sender
mcpz gmail list --sender "someone@example.com"

# Filter by subject
mcpz gmail list --subject "Important"

# Filter by labels
mcpz gmail list --labels "inbox,important"

# Filter by read status
mcpz gmail list --read_status unread

# Limit results
mcpz gmail list --max_results 10
```

### Searching Emails
```bash
# Basic search
mcpz gmail search "quarterly report"

# Advanced Gmail search syntax
mcpz gmail search "from:boss@company.com subject:urgent"
mcpz gmail search "has:attachment filename:pdf"
mcpz gmail search "is:unread after:2024/01/01"
```

### Reading Emails
```bash
# Read a specific email by ID
mcpz gmail read 18c8b5d4e8f9a2b6
```

### Sending Emails
```bash
# Send a basic email
mcpz gmail send \
  --to "recipient@example.com" \
  --subject "Hello from MCPEasy" \
  --body "This is a test email sent via Gmail API."

# Send with CC and BCC
mcpz gmail send \
  --to "recipient@example.com" \
  --cc "cc@example.com" \
  --bcc "bcc@example.com" \
  --subject "Team Update" \
  --body "Weekly team update..." \
  --reply_to "noreply@example.com"
```

### Replying to Emails
```bash
# Reply to an email
mcpz gmail reply 18c8b5d4e8f9a2b6 \
  --body "Thank you for your message."

# Reply without including quoted original message
mcpz gmail reply 18c8b5d4e8f9a2b6 \
  --body "Thank you for your message." \
  --include_quoted false
```

### Email Management
```bash
# Mark as read/unread
mcpz gmail mark_read 18c8b5d4e8f9a2b6
mcpz gmail mark_unread 18c8b5d4e8f9a2b6

# Add/remove labels
mcpz gmail add_label 18c8b5d4e8f9a2b6 "important"
mcpz gmail remove_label 18c8b5d4e8f9a2b6 "important"

# Archive email (remove from inbox)
mcpz gmail archive 18c8b5d4e8f9a2b6

# Move to trash
mcpz gmail trash 18c8b5d4e8f9a2b6
```

## MCP Server Usage

### Running the Server

```bash
# Start the Gmail MCP server
mcpz gmail mcp
```

### MCP Configuration

Add to your `.mcp.json` configuration:

```json
{
  "mcpServers": {
    "gmail": {
      "command": "mcpz",
      "args": ["gmail", "mcp"]
    }
  }
}
```

### Available MCP Tools

- `test_connection` - Test Gmail API connectivity
- `list_emails` - List emails with filtering options
- `search_emails` - Search emails using Gmail syntax
- `get_email_content` - Get full email content including attachments
- `send_email` - Send new emails
- `reply_to_email` - Reply to existing emails
- `mark_as_read` / `mark_as_unread` - Change read status
- `add_label` / `remove_label` - Manage email labels
- `archive_email` - Archive emails
- `trash_email` - Move emails to trash

### Available MCP Prompts

- `check_email` - Check inbox for new messages
- `compose_email` - Compose and send emails
- `email_search` - Search through emails
- `email_management` - Manage emails (read/unread, archive, etc.)

## Gmail Search Syntax

The Gmail MCP server supports Gmail's advanced search operators:

- `from:sender@example.com` - From specific sender
- `to:recipient@example.com` - To specific recipient
- `subject:keyword` - Subject contains keyword
- `has:attachment` - Has attachments
- `filename:pdf` - Attachment filename contains "pdf"
- `is:unread` / `is:read` - Read status
- `is:important` / `is:starred` - Importance/starred
- `label:labelname` - Has specific label
- `after:2024/01/01` / `before:2024/12/31` - Date ranges
- `newer_than:7d` / `older_than:1m` - Relative dates

## API Scopes

This MCP server requires the following Gmail API scopes:

- `https://www.googleapis.com/auth/gmail.readonly` - Read access to Gmail
- `https://www.googleapis.com/auth/gmail.send` - Send emails
- `https://www.googleapis.com/auth/gmail.modify` - Modify email labels and status

## Security Notes

- **OAuth tokens are stored locally** in `~/.config/mcpeasy/`
- **Tokens are automatically refreshed** when they expire
- **Only your authenticated user** can access emails through this server
- **No emails are stored** by the MCP server - all data comes directly from Gmail

## Troubleshooting

### Authentication Issues

```bash
# Re-authenticate if you see authentication errors
mcpz gmail auth

# Check configuration status
mcpz config
```

### API Quota Errors

Gmail API has usage quotas. If you hit rate limits:
- Reduce the number of requests
- Add delays between operations
- Check your Google Cloud Console quota usage

### Common Error Messages

- **"Gmail authentication required"** - Run `mcpz gmail auth`
- **"Google API credentials not configured"** - Run `mcpz set_google_credentials <path>`
- **"Gmail API Error: Insufficient Permission"** - Re-run authentication to grant necessary scopes

## Development

The Gmail MCP server follows the same patterns as other MCPEasy services:

- `service.rb` - Core Gmail API functionality
- `cli.rb` - Thor-based CLI commands  
- `mcp.rb` - MCP server implementation
- `README.md` - Documentation

For development setup:

```bash
# Clone the repository
git clone https://github.com/your-repo/mcpeasy.git
cd mcpeasy

# Install dependencies
bundle install

# Build and install locally
gem build mcpeasy.gemspec
gem install mcpeasy-*.gem
```