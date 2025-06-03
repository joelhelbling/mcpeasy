#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require_relative "service"

module Slack
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
          description: "List available Slack channels. When asked to list ALL channels, automatically retrieve all pages by calling this tool multiple times with the cursor parameter to get complete results.",
          inputSchema: {
            type: "object",
            properties: {
              limit: {
                type: "number",
                description: "Maximum number of channels to return (default: 100, max: 1000)"
              },
              cursor: {
                type: "string",
                description: "Cursor for pagination. Use the next_cursor from previous response to get next page"
              },
              exclude_archived: {
                type: "boolean",
                description: "Exclude archived channels from results (default: true)"
              }
            },
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
      Mcpeasy::Config.ensure_config_dirs
      File.write(Mcpeasy::Config.log_file_path("slack", "startup"), "#{Time.now}: Slack MCP Server starting on stdio\n", mode: "a")
      while (line = $stdin.gets)
        handle_request(line.strip)
      end
    rescue Interrupt
      # Silent shutdown
    rescue => e
      # Log to a file instead of stderr to avoid protocol interference
      File.write(Mcpeasy::Config.log_file_path("slack", "error"), "#{Time.now}: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
        File.write(Mcpeasy::Config.log_file_path("slack", "error"), "#{Time.now}: Error handling request: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
        File.write(Mcpeasy::Config.log_file_path("slack", "error"), "#{Time.now}: Tool error: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
      # Initialize Service only when needed
      @slack_tool ||= Service.new

      case tool_name
      when "test_connection"
        test_connection
      when "list_channels"
        list_channels(arguments)
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

    def list_channels(arguments)
      limit = [arguments["limit"]&.to_i || 100, 1000].min
      cursor = arguments["cursor"]&.to_s
      exclude_archived = arguments.key?("exclude_archived") ? arguments["exclude_archived"] : true

      # Keep track of current page for display
      @list_channels_page ||= {}
      page_key = cursor || "first"
      @list_channels_page[page_key] ||= 0
      @list_channels_page[page_key] = cursor ? @list_channels_page[page_key] + 1 : 1

      result = @slack_tool.list_channels(limit: limit, cursor: cursor&.empty? ? nil : cursor, exclude_archived: exclude_archived)
      channels = result[:channels]

      # Calculate record range
      page_num = @list_channels_page[page_key]
      start_index = (page_num - 1) * limit
      end_index = start_index + channels.count - 1

      channels_list = channels.map.with_index do |channel, i|
        "##{channel[:name]} (ID: #{channel[:id]})"
      end.join(", ")

      pagination_info = if result[:has_more]
        <<~INFO

          📄 **Page #{page_num}** | Showing channels #{start_index + 1}-#{end_index + 1}
          _More channels available. Use `cursor: "#{result[:next_cursor]}"` to get the next page._
        INFO
      else
        # Try to estimate total if we're on last page
        estimated_total = start_index + channels.count
        <<~INFO

          📄 **Page #{page_num}** | Showing channels #{start_index + 1}-#{end_index + 1} of #{estimated_total} total
        INFO
      end

      <<~OUTPUT
        📋 #{channels.count} Available channels: #{channels_list}#{pagination_info}
      OUTPUT
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
end

if __FILE__ == $0
  Slack::MCPServer.new.run
end
