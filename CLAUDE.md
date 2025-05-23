# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby utility repository containing a Slack posting script (`slack_poster.rb`) that provides programmatic access to Slack's Web API for posting messages to channels.

## Dependencies and Setup

Install dependencies:
```bash
bundle install
```

The project requires:
- A Slack bot token (stored in `.env` file as `SLACK_BOT_TOKEN`)
- Ruby gems: `slack-ruby-client` and `dotenv`

## Common Commands

Run the Slack poster:
```bash
ruby slack_poster.rb <channel> <message> [username]
```

List available Slack channels:
```bash
ruby slack_poster.rb
```

Make script executable:
```bash
chmod +x slack_poster.rb
```

## Architecture

The main component is the `SlackPoster` class which:
- Wraps the Slack Web API client
- Provides error handling for API failures
- Tests authentication before operations
- Supports posting messages with optional custom usernames
- Can list available channels when no arguments provided

The script follows a simple pattern: authenticate, validate connection, then perform the requested operation (post message or list channels).