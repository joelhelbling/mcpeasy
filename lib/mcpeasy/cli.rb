# frozen_string_literal: true

require "thor"
require_relative "config"

module Mcpeasy
  class GoogleCommands < Thor
    desc "auth", "Authenticate with Google services (Calendar, Drive, Meet)"
    def auth
      require_relative "../utilities/gcal/gcal_tool"
      tool = GcalTool.new(skip_auth: true)
      result = tool.authenticate
      if result[:success]
        puts "✅ Successfully authenticated with Google services"
        puts "   This enables access to Calendar, Drive, and Meet"
      else
        puts "❌ Authentication failed: #{result[:error]}"
        exit 1
      end
    end
  end

  # Load the existing GcalCLI and extend it with MCP functionality
  require_relative "../utilities/gcal/cli"

  class GcalCommands < GcalCLI
    namespace "gcal"

    desc "mcp", "Run Google Calendar MCP server"
    def mcp
      require_relative "../utilities/gcal/mcp"
      MCPServer.new.run
    end
  end

  # Load the existing GdriveCLI and extend it with MCP functionality
  require_relative "../utilities/gdrive/cli"

  class GdriveCommands < GdriveCLI
    namespace "gdrive"

    desc "mcp", "Run Google Drive MCP server"
    def mcp
      require_relative "../utilities/gdrive/mcp"
      MCPServer.new.run
    end
  end

  # Load the existing GmeetCLI and extend it with MCP functionality
  require_relative "../utilities/gmeet/cli"

  class GmeetCommands < GmeetCLI
    namespace "gmeet"

    desc "mcp", "Run Google Meet MCP server"
    def mcp
      require_relative "../utilities/gmeet/mcp"
      MCPServer.new.run
    end
  end

  # Load the existing SlackCLI and extend it with MCP functionality
  require_relative "../utilities/slack/cli"

  class SlackCommands < SlackCLI
    namespace "slack"

    desc "mcp", "Run Slack MCP server"
    def mcp
      require_relative "../utilities/slack/mcp"
      MCPServer.new.run
    end

    desc "set_bot_token TOKEN", "Set Slack bot token"
    def set_bot_token(token)
      Config.save_slack_bot_token(token)
      puts "✅ Slack bot token saved successfully"
    end

    # Alias the inherited 'list' command as 'channels' for consistency
    desc "channels", "List Slack channels"
    def channels
      list
    end
  end

  # Load the existing NotionCLI and extend it with MCP functionality
  require_relative "../utilities/notion/cli"

  class NotionCommands < NotionCLI
    namespace "notion"

    desc "mcp", "Run Notion MCP server"
    def mcp
      require_relative "../utilities/notion/mcp"
      MCPServer.new.run
    end

    desc "set_api_key API_KEY", "Set Notion API key"
    def set_api_key(api_key)
      Config.save_notion_api_key(api_key)
      puts "✅ Notion API key saved successfully"
    end
  end

  class CLI < Thor
    desc "version", "Show mcpeasy version"
    def version
      puts "mcpeasy #{Mcpeasy::VERSION}"
      puts "mcpeasy, LM squeezy! 🤖"
    end

    desc "setup", "Create configuration directories"
    def setup
      require_relative "setup"
      Setup.create_config_directories
    end

    desc "config", "Show configuration status"
    def config
      status = Config.config_status
      puts "📁 Config directory: #{status[:config_dir]}"
      puts "📄 Logs directory: #{status[:logs_dir]}"
      puts "🔑 Google credentials: #{status[:google_credentials] ? "✅" : "❌"}"
      puts "🎫 Google token: #{status[:google_token] ? "✅" : "❌"}"
      puts "💬 Slack config: #{status[:slack_config] ? "✅" : "❌"}"
      puts "📝 Notion config: #{status[:notion_config] ? "✅" : "❌"}"
    end

    desc "set_google_credentials PATH", "Save Google credentials from downloaded JSON file"
    def set_google_credentials(path)
      unless File.exist?(path)
        puts "❌ File not found: #{path}"
        exit 1
      end

      begin
        credentials_json = File.read(path)
        JSON.parse(credentials_json) # Validate it's valid JSON
        Config.save_google_credentials(credentials_json)
        puts "✅ Google credentials saved successfully"
      rescue JSON::ParserError
        puts "❌ Invalid JSON file"
        exit 1
      rescue => e
        puts "❌ Error saving credentials: #{e.message}"
        exit 1
      end
    end

    desc "google COMMAND", "Google services authentication"
    subcommand "google", GoogleCommands

    desc "gcal COMMAND", "Google Calendar commands"
    subcommand "gcal", GcalCommands

    desc "gdrive COMMAND", "Google Drive commands"
    subcommand "gdrive", GdriveCommands

    desc "gmeet COMMAND", "Google Meet commands"
    subcommand "gmeet", GmeetCommands

    desc "slack COMMAND", "Slack commands"
    subcommand "slack", SlackCommands

    desc "notion COMMAND", "Notion commands"
    subcommand "notion", NotionCommands

    class << self
      private

      def exit_on_failure?
        true
      end
    end
  end
end
