#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require_relative "service"

module Gdrive
  class MCPServer
    def initialize
      @prompts = [
        {
          name: "find_document",
          description: "Find a specific document or file in Google Drive",
          arguments: [
            {
              name: "search_terms",
              description: "Keywords to search for in file names and content (e.g., 'quarterly report', 'budget 2024')",
              required: true
            }
          ]
        },
        {
          name: "open_file",
          description: "Open and read the contents of a file from Google Drive",
          arguments: [
            {
              name: "file_identifier",
              description: "File name, ID, or search terms to identify the file",
              required: true
            }
          ]
        },
        {
          name: "browse_recent_files",
          description: "See your recently modified files in Google Drive",
          arguments: [
            {
              name: "count",
              description: "Number of recent files to show (default: 10)",
              required: false
            }
          ]
        },
        {
          name: "search_by_type",
          description: "Find files of a specific type in Google Drive",
          arguments: [
            {
              name: "file_type",
              description: "Type of files to search for (e.g., 'spreadsheet', 'presentation', 'PDF', 'document')",
              required: true
            },
            {
              name: "keywords",
              description: "Optional keywords to refine the search",
              required: false
            }
          ]
        },
        {
          name: "get_project_files",
          description: "Find all files related to a specific project or topic",
          arguments: [
            {
              name: "project_name",
              description: "Name or keywords related to the project",
              required: true
            }
          ]
        }
      ]
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
      Mcpeasy::Config.ensure_config_dirs
      File.write(Mcpeasy::Config.log_file_path("gdrive", "startup"), "#{Time.now}: Google Drive MCP Server starting on stdio\n", mode: "a")
      while (line = $stdin.gets)
        handle_request(line.strip)
      end
    rescue Interrupt
      # Silent shutdown
    rescue => e
      # Log to a file instead of stderr to avoid protocol interference
      File.write(Mcpeasy::Config.log_file_path("gdrive", "error"), "#{Time.now}: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
        File.write(Mcpeasy::Config.log_file_path("gdrive", "error"), "#{Time.now}: Error handling request: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
        File.write(Mcpeasy::Config.log_file_path("gdrive", "error"), "#{Time.now}: Tool error: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
      when "find_document"
        search_terms = params["arguments"]&.dig("search_terms") || "quarterly report"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Find documents in Google Drive containing: #{search_terms}"
            }
          }
        ]
      when "open_file"
        file_identifier = params["arguments"]&.dig("file_identifier") || "project_plan.docx"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Open and show me the contents of: #{file_identifier}"
            }
          }
        ]
      when "browse_recent_files"
        count = params["arguments"]&.dig("count") || "10"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Show me my #{count} most recently modified files in Google Drive"
            }
          }
        ]
      when "search_by_type"
        file_type = params["arguments"]&.dig("file_type") || "spreadsheet"
        keywords = params["arguments"]&.dig("keywords")
        search_text = (keywords.nil? || keywords.empty?) ?
          "Find all #{file_type} files in Google Drive" :
          "Find #{file_type} files in Google Drive containing: #{keywords}"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: search_text
            }
          }
        ]
      when "get_project_files"
        project_name = params["arguments"]&.dig("project_name") || "website redesign"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Find all files related to project: #{project_name}"
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
      @gdrive_tool ||= Service.new

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
      tool = Service.new
      response = tool.test_connection
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

      tool = Service.new
      result = tool.search_files(query, max_results: max_results)
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
      tool = Service.new
      result = tool.get_file_content(file_id)

      output = "📄 **#{result[:name]}**\n"
      output << "   - Type: #{result[:mime_type]}\n"
      output << "   - Size: #{format_bytes(result[:size])}\n\n"
      output << "**Content:**\n"
      output << "```\n#{result[:content]}\n```"
      output
    end

    def list_files(arguments)
      max_results = arguments["max_results"]&.to_i || 20
      tool = Service.new
      result = tool.list_files(max_results: max_results)
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
end

if __FILE__ == $0
  Gdrive::MCPServer.new.run
end
