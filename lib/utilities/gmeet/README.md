# Google Meet MCP Server

A Model Context Protocol (MCP) server for Google Meet integration. This tool allows you to list, search, and get direct links to Google Meet meetings from your Google Calendar.

## Features

- **List Google Meet meetings** with date filtering
- **Search for meetings** by title or description
- **Get upcoming meetings** in the next 24 hours
- **Extract Google Meet URLs** for direct browser access
- **CLI and MCP server modes** for flexible usage

## Setup

### 1. Google API Credentials

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the Google Calendar API
4. Create credentials (OAuth 2.0 Client ID) for a "Desktop application"
5. Download the credentials and note the Client ID and Client Secret

### 2. Environment Configuration

Create a `.env` file in the project root with your Google API credentials:

```bash
GOOGLE_CLIENT_ID=your_client_id_here
GOOGLE_CLIENT_SECRET=your_client_secret_here
```

### 3. Install Dependencies

```bash
bundle install
```

### 4. Authentication

Run the authentication flow to get access to your Google Calendar:

```bash
ruby utilities/gmeet/cli.rb auth
```

This will:
- Open your browser for Google OAuth authorization
- Save authentication tokens to `.gcal-token.json`
- Allow the tool to access your calendar data

## Usage

### CLI Mode

**Test connection:**
```bash
ruby utilities/gmeet/cli.rb test
```

**List Google Meet meetings:**
```bash
ruby utilities/gmeet/cli.rb meetings
ruby utilities/gmeet/cli.rb meetings --start_date 2024-01-01 --end_date 2024-01-07
ruby utilities/gmeet/cli.rb meetings --max_results 10
```

**List upcoming meetings:**
```bash
ruby utilities/gmeet/cli.rb upcoming
ruby utilities/gmeet/cli.rb upcoming --max_results 5
```

**Search for meetings:**
```bash
ruby utilities/gmeet/cli.rb search "standup"
ruby utilities/gmeet/cli.rb search "team meeting" --start_date 2024-01-01
```

**Get meeting URL by event ID:**
```bash
ruby utilities/gmeet/cli.rb url event_id_here
```

### MCP Server Mode

Configure in your `.mcp.json`:

```json
{
  "servers": {
    "gmeet": {
      "command": "ruby",
      "args": ["utilities/gmeet/mcp.rb"],
      "cwd": "/path/to/claude-code-utilities"
    }
  }
}
```

Available MCP tools:
- `test_connection` - Test Google Calendar API connection
- `list_meetings` - List Google Meet meetings with date filtering
- `upcoming_meetings` - List upcoming meetings in next 24 hours
- `search_meetings` - Search meetings by text content
- `get_meeting_url` - Get Google Meet URL for specific event

## How It Works

The tool uses the Google Calendar API to:

1. **Fetch calendar events** from your Google Calendar
2. **Filter for Google Meet meetings** by detecting:
   - Conference data with Google Meet
   - Hangout links (legacy)
   - Meet.google.com URLs in descriptions
   - Meet.google.com URLs in location fields
3. **Extract meeting URLs** for direct browser access
4. **Format and present** meeting information

## Troubleshooting

**Authentication Issues:**
- Ensure `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are set in `.env`
- Re-run the auth flow: `ruby utilities/gmeet/cli.rb auth`
- Check that the Google Calendar API is enabled in your Google Cloud project

**No meetings found:**
- Verify you have Google Meet meetings in your calendar
- Check the date range (default is 7 days from today)
- Ensure meetings have Google Meet links attached

**MCP Server Issues:**
- Check logs in `./logs/mcp_gmeet_error.log`
- Verify the server path in `.mcp.json` is correct
- Ensure all dependencies are installed with `bundle install`

## API Permissions

This tool requires:
- `https://www.googleapis.com/auth/calendar.readonly` - Read access to your Google Calendar

The tool only reads calendar data and never modifies your calendar or meetings.