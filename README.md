I'll create a Ruby script that posts messages to Slack using the Slack Web API. Here are the files you'll need:

## Setup Instructions

### 1. Install Dependencies

First, run `bundle install` to install the required gems:

```bash
bundle install
```

### 2. Create a Slack App and Get API Token

To get your Slack bot token:

1. Go to https://api.slack.com/apps
2. Click "Create New App" → "From scratch"
3. Give your app a name and select your workspace
4. Go to "OAuth & Permissions" in the sidebar
5. Under "Scopes" → "Bot Token Scopes", add these permissions:
   - `chat:write` (to post messages)
   - `channels:read` (to list public channels)
   - `groups:read` (to list private channels, optional)
6. Click "Install to Workspace" at the top
7. Copy the "Bot User OAuth Token" (starts with `xoxb-`)

### 3. Configure Environment Variables

1. Copy `.env.template` to `.env`:
   ```bash
   cp .env.template .env
   ```

2. Edit `.env` and replace `xoxb-your-bot-token-here` with your actual bot token

### 4. Usage Examples

Make the script executable:
```bash
chmod +x slack_poster.rb
```

Post a simple message:
```bash
ruby slack_poster.rb general "Hello from Ruby!"
```

Post with a custom username:
```bash
ruby slack_poster.rb general "Deployment completed successfully!" "DeployBot"
```

List available channels:
```bash
ruby slack_poster.rb
```

## Features

- **Error handling**: Comprehensive error handling for API failures
- **Connection testing**: Verifies authentication before posting
- **Channel listing**: Shows available channels if no arguments provided
- **Flexible usage**: Supports custom usernames and channel names with or without `#`
- **Environment variables**: Secure token storage using dotenv

## Required Slack Permissions

Your Slack app needs these OAuth scopes:
- `chat:write` - Required to post messages
- `channels:read` - Optional, for listing public channels
- `groups:read` - Optional, for listing private channels

The script will work with just `chat:write` if you know your channel names, but the other permissions enable the channel listing feature.
