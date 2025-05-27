#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require "dotenv"
require_relative "slack_tool"

# Load environment variables from .env file
Dotenv.load

class MCPServer
  def initialize
    # Defer SlackTool initialization until actually needed
    @slack_tool = nil
    @tools = {
      "test_connection" => {
        name: "test_connection",
        description: "Test the Slack API connection",
        inputSchema: {
          type: "object",
          properties: {},
          required: []
        }
      },
      "list_channels" => {
        name: "list_channels",
        description: "List available Slack channels",
        inputSchema: {
          type: "object",
          properties: {},
          required: []
        }
      },
      "post_message" => {
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
      }
    }
  end

  def run
    # Disable stdout buffering for immediate response
    $stdout.sync = true

    # Log startup to file instead of stdout to avoid protocol interference
    File.write("./logs/mcp_slack_startup.log", "#{Time.now}: Slack MCP Server starting on stdio\n", mode: "a")
    while (line = $stdin.gets)
      handle_request(line.strip)
    end
  rescue Interrupt
    # Silent shutdown
  rescue => e
    # Log to a file instead of stderr to avoid protocol interference
    File.write("./logs/mcp_slack_error.log", "#{Time.now}: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
  end

  private

  def handle_request(line)
    return if line.empty?

    begin
      request = JSON.parse(line)
      response = process_request(request)
      if response
        puts JSON.generate(response)
        $stdout.flush
      end
    rescue JSON::ParserError => e
      error_response = {
        jsonrpc: "2.0",
        id: nil,
        error: {
          code: -32700,
          message: "Parse error",
          data: e.message
        }
      }
      puts JSON.generate(error_response)
      $stdout.flush
    rescue => e
      File.write("./logs/mcp_slack_error.log", "#{Time.now}: Error handling request: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
      error_response = {
        jsonrpc: "2.0",
        id: request&.dig("id"),
        error: {
          code: -32603,
          message: "Internal error",
          data: e.message
        }
      }
      puts JSON.generate(error_response)
      $stdout.flush
    end
  end

  def process_request(request)
    id = request["id"]
    method = request["method"]
    params = request["params"] || {}

    case method
    when "notifications/initialized"
      # Client acknowledgment - no response needed
      nil
    when "initialize"
      initialize_response(id, params)
    when "tools/list"
      tools_list_response(id, params)
    when "tools/call"
      tools_call_response(id, params)
    else
      {
        jsonrpc: "2.0",
        id: id,
        error: {
          code: -32601,
          message: "Method not found",
          data: "Unknown method: #{method}"
        }
      }
    end
  end

  def initialize_response(id, params)
    {
      jsonrpc: "2.0",
      id: id,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: {
          tools: {}
        },
        serverInfo: {
          name: "slack-mcp-server",
          version: "1.0.0"
        }
      }
    }
  end

  def tools_list_response(id, params)
    {
      jsonrpc: "2.0",
      id: id,
      result: {
        tools: @tools.values
      }
    }
  end

  def tools_call_response(id, params)
    tool_name = params["name"]
    arguments = params["arguments"] || {}

    unless @tools.key?(tool_name)
      return {
        jsonrpc: "2.0",
        id: id,
        error: {
          code: -32602,
          message: "Unknown tool",
          data: "Tool '#{tool_name}' not found"
        }
      }
    end

    begin
      result = call_tool(tool_name, arguments)
      {
        jsonrpc: "2.0",
        id: id,
        result: {
          content: [
            {
              type: "text",
              text: result
            }
          ],
          isError: false
        }
      }
    rescue => e
      File.write("./logs/mcp_slack_error.log", "#{Time.now}: Tool error: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
      {
        jsonrpc: "2.0",
        id: id,
        result: {
          content: [
            {
              type: "text",
              text: "❌ Error: #{e.message}"
            }
          ],
          isError: true
        }
      }
    end
  end

  def call_tool(tool_name, arguments)
    # Initialize SlackTool only when needed
    @slack_tool ||= SlackTool.new

    case tool_name
    when "test_connection"
      test_connection
    when "list_channels"
      list_channels
    when "post_message"
      post_message(arguments)
    else
      raise "Unknown tool: #{tool_name}"
    end
  end

  def test_connection
    response = @slack_tool.test_connection
    if response["ok"]
      "✅ Successfully connected to Slack. Bot: #{response["user"]}, Team: #{response["team"]}"
    else
      raise "Authentication failed: #{response["error"]}"
    end
  end

  def list_channels
    channels = @slack_tool.list_channels
    output = "📋 #{channels.count} Available channels: "
    output << channels.map { |c| "##{c[:name]} (ID: #{c[:id]})" }.join(", ")
    output
  end

  def post_message(arguments)
    # Validate required arguments
    unless arguments["channel"]
      raise "Missing required argument: channel"
    end
    unless arguments["text"]
      raise "Missing required argument: text"
    end

    channel = arguments["channel"].to_s.sub(/^#/, "")
    text = arguments["text"].to_s
    username = arguments["username"]&.to_s
    thread_ts = arguments["thread_ts"]&.to_s

    response = @slack_tool.post_message(
      channel: channel,
      text: text,
      username: username&.empty? ? nil : username,
      thread_ts: thread_ts&.empty? ? nil : thread_ts
    )

    "✅ Message posted successfully to ##{channel} (Message timestamp: #{response["ts"]})"
  end
end

if __FILE__ == $0
  MCPServer.new.run
end
