#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "slack-ruby-client"
require "dotenv/load"
require "json"
require_relative "mcp_server"

class SlackPoster
  include MCPServer

  def initialize
    @client = Slack::Web::Client.new(token: ENV["SLACK_BOT_TOKEN"])
  end

  def post_message(channel:, text:, username: nil, thread_ts: nil, silent: false)
    response = @client.chat_postMessage(
      channel: channel.sub(/^#/, ""),
      text: text,
      username: username,
      thread_ts: thread_ts
    )

    if response["ok"]
      puts "✅ Message posted successfully to ##{channel}" unless silent
      puts "   Message timestamp: #{response["ts"]}" unless silent
      response
    else
      puts "❌ Failed to post message: #{response["error"]}" unless silent
    end
  rescue Slack::Web::Api::Errors::SlackError => e
    puts "❌ Slack API Error: #{e.message}" unless silent
    nil
  rescue => e
    puts "❌ Unexpected error: #{e.message}" unless silent
    nil
  end

  def list_channels(silent: false)
    response = @client.conversations_list(types: "public_channel,private_channel")

    if response["ok"]
      unless silent
        puts "📋 Available channels:"
        response["channels"].each do |channel|
          puts "   ##{channel["name"]} (ID: #{channel["id"]})"
        end
      end
      response["channels"]
    else
      puts "❌ Failed to list channels: #{response["error"]}" unless silent
      nil
    end
  rescue Slack::Web::Api::Errors::SlackError => e
    puts "❌ Slack API Error: #{e.message}" unless silent
    nil
  end

  def test_connection(silent: false)
    response = @client.auth_test

    if response["ok"]
      unless silent
        puts "✅ Successfully connected to Slack"
        puts "   Bot name: #{response["user"]}"
        puts "   Team: #{response["team"]}"
      end
      response
    else
      puts "❌ Authentication failed: #{response["error"]}" unless silent
      nil
    end
  rescue Slack::Web::Api::Errors::SlackError => e
    puts "❌ Slack API Error: #{e.message}" unless silent
    nil
  end

  # MCP Server implementation
  def mcp_tools
    [
      {
        name: "post_message",
        description: "Post a message to a Slack channel",
        inputSchema: {
          type: "object",
          properties: {
            channel: {
              type: "string",
              description: "The Slack channel name (with or without #)"
            },
            text: {
              type: "string",
              description: "The message text to post"
            },
            username: {
              type: "string",
              description: "Optional custom username for the message"
            },
            thread_ts: {
              type: "string",
              description: "Optional timestamp of parent message to reply to"
            }
          },
          required: ["channel", "text"]
        }
      },
      {
        name: "list_channels",
        description: "List available Slack channels",
        inputSchema: {
          type: "object",
          properties: {},
          required: []
        }
      },
      {
        name: "test_connection",
        description: "Test the Slack API connection",
        inputSchema: {
          type: "object",
          properties: {},
          required: []
        }
      }
    ]
  end

  def mcp_call_tool(tool_name, arguments)
    case tool_name
    when "post_message"
      handle_mcp_post_message(arguments)
    when "list_channels"
      handle_mcp_list_channels
    when "test_connection"
      handle_mcp_test_connection
    else
      raise "Unknown tool: #{tool_name}"
    end
  end

  def mcp_server_info
    {name: "slack-poster", version: "1.0.0"}
  end

  private

  def handle_mcp_post_message(arguments)
    channel = arguments["channel"]
    text = arguments["text"]
    username = arguments["username"]
    thread_ts = arguments["thread_ts"]

    unless channel && text
      raise "Missing required parameters: channel and text"
    end

    result = post_message(
      channel: channel,
      text: text,
      username: username,
      thread_ts: thread_ts,
      silent: true
    )

    if result
      "Message posted successfully to ##{channel}. Timestamp: #{result["ts"]}"
    else
      raise "Failed to post message to Slack"
    end
  end

  def handle_mcp_list_channels
    channels = list_channels(silent: true)

    if channels
      channel_list = channels.map { |ch| "##{ch["name"]}" }.join(", ")
      "Available channels: #{channel_list}"
    else
      raise "Failed to list channels"
    end
  end

  def handle_mcp_test_connection
    result = test_connection(silent: true)

    if result
      "Successfully connected to Slack. Bot: #{result["user"]}, Team: #{result["team"]}"
    else
      raise "Failed to connect to Slack"
    end
  end
end

# Main execution
if __FILE__ == $0
  # Check if required environment variable is set
  unless ENV["SLACK_BOT_TOKEN"]
    puts "❌ SLACK_BOT_TOKEN environment variable is not set!"
    puts "   Please add your Slack bot token to the .env file"
    exit 1
  end

  poster = SlackPoster.new

  # Check for MCP mode
  if ARGV.include?("--mcp")
    # Run as MCP server
    poster.run_mcp_server
    exit 0
  end

  # Test connection first
  unless poster.test_connection
    puts "❌ Unable to connect to Slack. Please check your token."
    exit 1
  end

  # Get command line arguments
  if ARGV.length < 2
    puts "Usage: ruby slack_poster.rb <channel> <message> [username]"
    puts "       ruby slack_poster.rb --mcp  (run as MCP server)"
    puts "Example: ruby slack_poster.rb general 'Hello from Ruby!' MyBot"
    puts ""
    puts "Available channels:"
    poster.list_channels
    exit 1
  end

  channel = ARGV[0]
  message = ARGV[1]
  username = ARGV[2] # Optional

  # Post the message
  result = poster.post_message(
    channel: channel,
    text: message,
    username: username
  )

  exit result ? 0 : 1
end
