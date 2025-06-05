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
      @prompts = [
        {
          name: "post_message",
          description: "Send a message to a Slack channel",
          arguments: [
            {
              name: "channel",
              description: "Channel to post to (e.g., 'general', 'random', or '#team-updates')",
              required: true
            },
            {
              name: "message",
              description: "Message text to send",
              required: true
            }
          ]
        },
        {
          name: "post_announcement",
          description: "Send an announcement or important message to a Slack channel",
          arguments: [
            {
              name: "channel",
              description: "Channel to post announcement to (e.g., 'general', 'announcements')",
              required: true
            },
            {
              name: "message",
              description: "Announcement text to send",
              required: true
            }
          ]
        },
        {
          name: "list_channels",
          description: "See what Slack channels are available",
          arguments: []
        },
        {
          name: "reply_in_thread",
          description: "Reply to a message in a Slack thread",
          arguments: [
            {
              name: "channel",
              description: "Channel where the original message is",
              required: true
            },
            {
              name: "thread_ts",
              description: "Timestamp of the original message to reply to",
              required: true
            },
            {
              name: "reply",
              description: "Reply message text",
              required: true
            }
          ]
        },
        {
          name: "team_update",
          description: "Send a team status update or standup message",
          arguments: [
            {
              name: "channel",
              description: "Team channel to post update to",
              required: true
            },
            {
              name: "update",
              description: "Status update or standup message",
              required: true
            }
          ]
        }
      ]
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
      when "prompts/list"
        prompts_list_response(id, params)
      when "prompts/get"
        prompts_get_response(id, params)
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
            tools: {},
            prompts: {}
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

    def prompts_list_response(id, params)
      {
        jsonrpc: "2.0",
        id: id,
        result: {
          prompts: @prompts
        }
      }
    end

    def prompts_get_response(id, params)
      prompt_name = params["name"]
      prompt = @prompts.find { |p| p[:name] == prompt_name }

      unless prompt
        return {
          jsonrpc: "2.0",
          id: id,
          error: {
            code: -32602,
            message: "Unknown prompt",
            data: "Prompt '#{prompt_name}' not found"
          }
        }
      end

      # Generate messages based on the prompt
      messages = case prompt_name
      when "post_message"
        channel = params["arguments"]&.dig("channel") || "general"
        message = params["arguments"]&.dig("message") || "Hello team!"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Post a message to ##{channel}: #{message}"
            }
          }
        ]
      when "post_announcement"
        channel = params["arguments"]&.dig("channel") || "general"
        message = params["arguments"]&.dig("message") || "Important announcement"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Post an announcement to ##{channel}: #{message}"
            }
          }
        ]
      when "list_channels"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Show me what Slack channels are available"
            }
          }
        ]
      when "reply_in_thread"
        channel = params["arguments"]&.dig("channel") || "general"
        thread_ts = params["arguments"]&.dig("thread_ts") || "1234567890.123456"
        reply = params["arguments"]&.dig("reply") || "Thanks for the update!"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Reply to thread #{thread_ts} in ##{channel}: #{reply}"
            }
          }
        ]
      when "team_update"
        channel = params["arguments"]&.dig("channel") || "team-updates"
        update = params["arguments"]&.dig("update") || "Daily standup update"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Post team update to ##{channel}: #{update}"
            }
          }
        ]
      else
        []
      end

      {
        jsonrpc: "2.0",
        id: id,
        result: {
          description: prompt[:description],
          messages: messages
        }
      }
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
