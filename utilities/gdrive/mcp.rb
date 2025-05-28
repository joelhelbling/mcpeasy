#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require "dotenv"
require_relative "gdrive_tool"

# Load environment variables from .env file
Dotenv.load

class MCPServer
  def initialize
    # Defer GdriveTool initialization until actually needed
    @gdrive_tool = nil
    @tools = {
      "test_connection" => {
        name: "test_connection",
        description: "Test the Google Drive API connection",
        inputSchema: {
          type: "object",
          properties: {},
          required: []
        }
      },
      "search_files" => {
        name: "search_files",
        description: "Search for files in Google Drive by content or name",
        inputSchema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search query to find files"
            },
            max_results: {
              type: "number",
              description: "Maximum number of results to return (default: 10)"
            }
          },
          required: ["query"]
        }
      },
      "get_file_content" => {
        name: "get_file_content",
        description: "Get the content of a specific Google Drive file",
        inputSchema: {
          type: "object",
          properties: {
            file_id: {
              type: "string",
              description: "The Google Drive file ID"
            }
          },
          required: ["file_id"]
        }
      },
      "list_files" => {
        name: "list_files",
        description: "List recent files in Google Drive",
        inputSchema: {
          type: "object",
          properties: {
            max_results: {
              type: "number",
              description: "Maximum number of files to return (default: 20)"
            }
          },
          required: []
        }
      }
    }
  end

  def run
    # Disable stdout buffering for immediate response
    $stdout.sync = true

    # Log startup to file instead of stdout to avoid protocol interference
    File.write("./logs/mcp_gdrive_startup.log", "#{Time.now}: Google Drive MCP Server starting on stdio\n", mode: "a")
    while (line = $stdin.gets)
      handle_request(line.strip)
    end
  rescue Interrupt
    # Silent shutdown
  rescue => e
    # Log to a file instead of stderr to avoid protocol interference
    File.write("./logs/mcp_gdrive_error.log", "#{Time.now}: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
      File.write("./logs/mcp_gdrive_error.log", "#{Time.now}: Error handling request: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
          name: "gdrive-mcp-server",
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
      File.write("./logs/mcp_gdrive_error.log", "#{Time.now}: Tool error: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
    # Initialize GdriveTool only when needed
    @gdrive_tool ||= GdriveTool.new

    case tool_name
    when "test_connection"
      test_connection
    when "search_files"
      search_files(arguments)
    when "get_file_content"
      get_file_content(arguments)
    when "list_files"
      list_files(arguments)
    else
      raise "Unknown tool: #{tool_name}"
    end
  end

  def test_connection
    response = @gdrive_tool.test_connection
    if response[:ok]
      "✅ Successfully connected to Google Drive.\n" \
      "   User: #{response[:user]} (#{response[:email]})\n" \
      "   Storage: #{format_bytes(response[:storage_used])} / #{format_bytes(response[:storage_limit])}"
    else
      raise "Connection test failed"
    end
  end

  def search_files(arguments)
    unless arguments["query"]
      raise "Missing required argument: query"
    end

    query = arguments["query"].to_s
    max_results = arguments["max_results"]&.to_i || 10

    result = @gdrive_tool.search_files(query, max_results: max_results)
    files = result[:files]

    if files.empty?
      "🔍 No files found matching '#{query}'"
    else
      output = "🔍 Found #{result[:count]} file(s) matching '#{query}':\n\n"
      files.each_with_index do |file, index|
        output << "#{index + 1}. **#{file[:name]}**\n"
        output << "   - ID: `#{file[:id]}`\n"
        output << "   - Type: #{file[:mime_type]}\n"
        output << "   - Size: #{format_bytes(file[:size])}\n"
        output << "   - Modified: #{file[:modified_time]}\n"
        output << "   - Link: #{file[:web_view_link]}\n\n"
      end
      output
    end
  end

  def get_file_content(arguments)
    unless arguments["file_id"]
      raise "Missing required argument: file_id"
    end

    file_id = arguments["file_id"].to_s
    result = @gdrive_tool.get_file_content(file_id)

    output = "📄 **#{result[:name]}**\n"
    output << "   - Type: #{result[:mime_type]}\n"
    output << "   - Size: #{format_bytes(result[:size])}\n\n"
    output << "**Content:**\n"
    output << "```\n#{result[:content]}\n```"
    output
  end

  def list_files(arguments)
    max_results = arguments["max_results"]&.to_i || 20
    result = @gdrive_tool.list_files(max_results: max_results)
    files = result[:files]

    if files.empty?
      "📂 No files found in Google Drive"
    else
      output = "📂 Recent #{result[:count]} file(s):\n\n"
      files.each_with_index do |file, index|
        output << "#{index + 1}. **#{file[:name]}**\n"
        output << "   - ID: `#{file[:id]}`\n"
        output << "   - Type: #{file[:mime_type]}\n"
        output << "   - Size: #{format_bytes(file[:size])}\n"
        output << "   - Modified: #{file[:modified_time]}\n"
        output << "   - Link: #{file[:web_view_link]}\n\n"
      end
      output
    end
  end

  private

  def format_bytes(bytes)
    return "Unknown" unless bytes

    units = %w[B KB MB GB TB]
    size = bytes.to_f
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end

    "#{size.round(1)} #{units[unit_index]}"
  end
end

if __FILE__ == $0
  MCPServer.new.run
end
