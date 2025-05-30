#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require_relative "notion_tool"

class MCPServer
  def initialize
    # Defer NotionTool initialization until actually needed
    @notion_tool = nil
    @tools = {
      "test_connection" => {
        name: "test_connection",
        description: "Test the Notion API connection",
        inputSchema: {
          type: "object",
          properties: {},
          required: []
        }
      },
      "search_pages" => {
        name: "search_pages",
        description: "Search for pages in Notion workspace",
        inputSchema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search query to find pages (optional, searches all pages if empty)"
            },
            page_size: {
              type: "number",
              description: "Maximum number of results to return (default: 10, max: 100)"
            }
          },
          required: []
        }
      },
      "search_databases" => {
        name: "search_databases",
        description: "Search for databases in Notion workspace",
        inputSchema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search query to find databases (optional, searches all databases if empty)"
            },
            page_size: {
              type: "number",
              description: "Maximum number of results to return (default: 10, max: 100)"
            }
          },
          required: []
        }
      },
      "get_page" => {
        name: "get_page",
        description: "Get details of a specific Notion page",
        inputSchema: {
          type: "object",
          properties: {
            page_id: {
              type: "string",
              description: "The ID of the Notion page to retrieve"
            }
          },
          required: ["page_id"]
        }
      },
      "get_page_content" => {
        name: "get_page_content",
        description: "Get the text content of a Notion page",
        inputSchema: {
          type: "object",
          properties: {
            page_id: {
              type: "string",
              description: "The ID of the Notion page to get content from"
            }
          },
          required: ["page_id"]
        }
      },
      "query_database" => {
        name: "query_database",
        description: "Query entries in a Notion database",
        inputSchema: {
          type: "object",
          properties: {
            database_id: {
              type: "string",
              description: "The ID of the Notion database to query"
            },
            page_size: {
              type: "number",
              description: "Maximum number of results to return (default: 10, max: 100)"
            }
          },
          required: ["database_id"]
        }
      }
    }
  end

  def run
    # Disable stdout buffering for immediate response
    $stdout.sync = true

    # Log startup to file instead of stdout to avoid protocol interference
    Mcpeasy::Config.ensure_config_dirs
    File.write(Mcpeasy::Config.log_file_path("notion", "startup"), "#{Time.now}: Notion MCP Server starting on stdio\n", mode: "a")
    while (line = $stdin.gets)
      handle_request(line.strip)
    end
  rescue Interrupt
    # Silent shutdown
  rescue => e
    # Log to a file instead of stderr to avoid protocol interference
    File.write(Mcpeasy::Config.log_file_path("notion", "error"), "#{Time.now}: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
      File.write(Mcpeasy::Config.log_file_path("notion", "error"), "#{Time.now}: Error handling request: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
          name: "notion-mcp-server",
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
      File.write(Mcpeasy::Config.log_file_path("notion", "error"), "#{Time.now}: Tool error: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
    # Initialize NotionTool only when needed
    @notion_tool ||= NotionTool.new

    case tool_name
    when "test_connection"
      test_connection
    when "search_pages"
      search_pages(arguments)
    when "search_databases"
      search_databases(arguments)
    when "get_page"
      get_page(arguments)
    when "get_page_content"
      get_page_content(arguments)
    when "query_database"
      query_database(arguments)
    else
      raise "Unknown tool: #{tool_name}"
    end
  end

  def test_connection
    response = @notion_tool.test_connection
    if response[:ok]
      "✅ Successfully connected to Notion. User: #{response[:user]}, Type: #{response[:type]}"
    else
      raise "Authentication failed: #{response[:error]}"
    end
  end

  def search_pages(arguments)
    query = arguments["query"]&.to_s || ""
    page_size = [arguments["page_size"]&.to_i || 10, 100].min

    pages = @notion_tool.search_pages(query: query, page_size: page_size)

    query_text = query.empty? ? "" : " for query '#{query}'"
    pages_list = pages.map.with_index do |page, i|
      <<~PAGE
        #{i + 1}. **#{page[:title]}**
           - ID: `#{page[:id]}`
           - URL: #{page[:url]}
           - Last edited: #{page[:last_edited_time]}
      PAGE
    end.join("\n")

    <<~OUTPUT
      📄 Found #{pages.count} pages#{query_text}:

      #{pages_list}
    OUTPUT
  end

  def search_databases(arguments)
    query = arguments["query"]&.to_s || ""
    page_size = [arguments["page_size"]&.to_i || 10, 100].min

    databases = @notion_tool.search_databases(query: query, page_size: page_size)

    query_text = query.empty? ? "" : " for query '#{query}'"
    databases_list = databases.map.with_index do |database, i|
      <<~DATABASE
        #{i + 1}. **#{database[:title]}**
           - ID: `#{database[:id]}`
           - URL: #{database[:url]}
           - Last edited: #{database[:last_edited_time]}
      DATABASE
    end.join("\n")

    <<~OUTPUT
      🗃️ Found #{databases.count} databases#{query_text}:

      #{databases_list}
    OUTPUT
  end

  def get_page(arguments)
    unless arguments["page_id"]
      raise "Missing required argument: page_id"
    end

    page_id = arguments["page_id"].to_s
    page = @notion_tool.get_page(page_id)

    properties_section = if page[:properties]&.any?
      properties_lines = page[:properties].map do |name, prop|
        formatted_value = format_property_for_mcp(prop)
        "- **#{name}:** #{formatted_value}"
      end
      "\n**Properties:**\n#{properties_lines.join("\n")}\n"
    else
      ""
    end

    <<~OUTPUT
      📄 **Page Details**

      **Title:** #{page[:title]}
      **ID:** `#{page[:id]}`
      **URL:** #{page[:url]}
      **Created:** #{page[:created_time]}
      **Last edited:** #{page[:last_edited_time]}#{properties_section}
    OUTPUT
  end

  def get_page_content(arguments)
    unless arguments["page_id"]
      raise "Missing required argument: page_id"
    end

    page_id = arguments["page_id"].to_s
    content = @notion_tool.get_page_content(page_id)

    if content && !content.empty?
      "📝 **Page Content:**\n\n#{content}"
    else
      "📝 No content found for this page"
    end
  end

  def query_database(arguments)
    unless arguments["database_id"]
      raise "Missing required argument: database_id"
    end

    database_id = arguments["database_id"].to_s
    page_size = [arguments["page_size"]&.to_i || 10, 100].min

    entries = @notion_tool.query_database(database_id, page_size: page_size)

    entries_list = entries.map.with_index do |entry, i|
      <<~ENTRY
        #{i + 1}. **#{entry[:title]}**
           - ID: `#{entry[:id]}`
           - URL: #{entry[:url]}
           - Last edited: #{entry[:last_edited_time]}
      ENTRY
    end.join("\n")

    <<~OUTPUT
      🗃️ Found #{entries.count} entries in database:

      #{entries_list}
    OUTPUT
  end

  def format_property_for_mcp(prop)
    case prop["type"]
    when "title"
      prop["title"]&.map { |t| t["plain_text"] }&.join || ""
    when "rich_text"
      prop["rich_text"]&.map { |t| t["plain_text"] }&.join || ""
    when "number"
      prop["number"]&.to_s || ""
    when "select"
      prop["select"]&.dig("name") || ""
    when "multi_select"
      prop["multi_select"]&.map { |s| s["name"] }&.join(", ") || ""
    when "date"
      prop["date"]&.dig("start") || ""
    when "checkbox"
      prop["checkbox"] ? "☑" : "☐"
    when "url"
      prop["url"] || ""
    when "email"
      prop["email"] || ""
    when "phone_number"
      prop["phone_number"] || ""
    else
      "[#{prop["type"]}]"
    end
  end
end

if __FILE__ == $0
  MCPServer.new.run
end
