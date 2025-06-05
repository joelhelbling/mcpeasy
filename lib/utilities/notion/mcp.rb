#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require_relative "service"

module Notion
  class MCPServer
    def initialize
      # Defer Service initialization until actually needed
      @notion_tool = nil
      @prompts = [
        {
          name: "find_page",
          description: "Find a specific page or document in Notion",
          arguments: [
            {
              name: "search_terms",
              description: "Keywords to search for in page titles and content",
              required: true
            }
          ]
        },
        {
          name: "open_page",
          description: "Open and read the contents of a Notion page",
          arguments: [
            {
              name: "page_identifier",
              description: "Page title, ID, or keywords to identify the page",
              required: true
            }
          ]
        },
        {
          name: "browse_database",
          description: "Browse entries in a Notion database",
          arguments: [
            {
              name: "database_name",
              description: "Name or keywords to identify the database",
              required: true
            }
          ]
        },
        {
          name: "find_notes",
          description: "Search for notes or documentation on a specific topic",
          arguments: [
            {
              name: "topic",
              description: "Topic or subject to search for in notes",
              required: true
            }
          ]
        },
        {
          name: "project_info",
          description: "Find information about a specific project",
          arguments: [
            {
              name: "project_name",
              description: "Name or keywords related to the project",
              required: true
            }
          ]
        },
        {
          name: "team_pages",
          description: "Find pages or content related to team members",
          arguments: [
            {
              name: "team_or_person",
              description: "Team name or person's name to find related content",
              required: true
            }
          ]
        },
        {
          name: "recent_updates",
          description: "See recently updated pages and content in Notion",
          arguments: []
        },
        {
          name: "workspace_overview",
          description: "Get an overview of the Notion workspace structure",
          arguments: []
        }
      ]
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
                description: "Maximum number of results to return (default: 100, max: 100)"
              },
              start_cursor: {
                type: "string",
                description: "Cursor for pagination. Use the next_cursor from previous response to get next page"
              }
            },
            required: ["database_id"]
          }
        },
        "list_users" => {
          name: "list_users",
          description: "List all users in the Notion workspace",
          inputSchema: {
            type: "object",
            properties: {
              page_size: {
                type: "number",
                description: "Maximum number of results to return (default: 100, max: 100)"
              },
              start_cursor: {
                type: "string",
                description: "Cursor for pagination. Use the next_cursor from previous response to get next page"
              }
            },
            required: []
          }
        },
        "get_user" => {
          name: "get_user",
          description: "Get details of a specific Notion user",
          inputSchema: {
            type: "object",
            properties: {
              user_id: {
                type: "string",
                description: "The ID of the Notion user to retrieve"
              }
            },
            required: ["user_id"]
          }
        },
        "get_bot_user" => {
          name: "get_bot_user",
          description: "Get information about the integration bot user",
          inputSchema: {
            type: "object",
            properties: {},
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
      when "find_page"
        search_terms = params["arguments"]&.dig("search_terms") || "project documentation"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Find Notion pages containing: #{search_terms}"
            }
          }
        ]
      when "open_page"
        page_identifier = params["arguments"]&.dig("page_identifier") || "meeting notes"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Open and show me the content of Notion page: #{page_identifier}"
            }
          }
        ]
      when "browse_database"
        database_name = params["arguments"]&.dig("database_name") || "project tracker"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Browse entries in Notion database: #{database_name}"
            }
          }
        ]
      when "find_notes"
        topic = params["arguments"]&.dig("topic") || "API documentation"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Find notes and documentation about: #{topic}"
            }
          }
        ]
      when "project_info"
        project_name = params["arguments"]&.dig("project_name") || "website redesign"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Find information about project: #{project_name}"
            }
          }
        ]
      when "team_pages"
        team_or_person = params["arguments"]&.dig("team_or_person") || "engineering team"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Find Notion pages related to: #{team_or_person}"
            }
          }
        ]
      when "recent_updates"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Show me recently updated pages in Notion"
            }
          }
        ]
      when "workspace_overview"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Give me an overview of the Notion workspace structure"
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
      @notion_tool ||= Service.new

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
      when "list_users"
        list_users(arguments)
      when "get_user"
        get_user(arguments)
      when "get_bot_user"
        get_bot_user
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
      page_size = [arguments["page_size"]&.to_i || 100, 100].min
      start_cursor = arguments["start_cursor"]

      # Keep track of current page for display
      @query_database_page ||= {}
      @query_database_page[database_id] ||= 0
      @query_database_page[database_id] = start_cursor ? @query_database_page[database_id] + 1 : 1

      result = @notion_tool.query_database(database_id, page_size: page_size, start_cursor: start_cursor)
      entries = result[:entries]

      # Calculate record range
      page_num = @query_database_page[database_id]
      start_index = (page_num - 1) * page_size
      end_index = start_index + entries.count - 1

      entries_list = entries.map.with_index do |entry, i|
        <<~ENTRY
          #{start_index + i + 1}. **#{entry[:title]}**
             - ID: `#{entry[:id]}`
             - URL: #{entry[:url]}
             - Last edited: #{entry[:last_edited_time]}
        ENTRY
      end.join("\n")

      pagination_info = if result[:has_more]
        <<~INFO
          
          📄 **Page #{page_num}** | Showing records #{start_index + 1}-#{end_index + 1}
          _More entries available. Use `start_cursor: "#{result[:next_cursor]}"` to get the next page._
        INFO
      else
        # Try to estimate total if we're on last page
        estimated_total = start_index + entries.count
        <<~INFO
          
          📄 **Page #{page_num}** | Showing records #{start_index + 1}-#{end_index + 1} of #{estimated_total} total
        INFO
      end

      <<~OUTPUT
        🗃️ Found #{entries.count} entries in database:

        #{entries_list}#{pagination_info}
      OUTPUT
    end

    def list_users(arguments)
      page_size = [arguments["page_size"]&.to_i || 100, 100].min
      start_cursor = arguments["start_cursor"]

      # Keep track of current page for display
      @list_users_page ||= 0
      @list_users_page = start_cursor ? @list_users_page + 1 : 1

      result = @notion_tool.list_users(page_size: page_size, start_cursor: start_cursor)
      users = result[:users]

      # Calculate record range
      start_index = (@list_users_page - 1) * page_size
      end_index = start_index + users.count - 1

      users_list = users.map.with_index do |user, i|
        email_line = user[:email] ? "\n           - Email: #{user[:email]}" : ""
        avatar_line = user[:avatar_url] ? "\n           - Avatar: #{user[:avatar_url]}" : ""

        <<~USER
          #{start_index + i + 1}. **#{user[:name] || "Unnamed"}** (#{user[:type]})
             - ID: `#{user[:id]}`#{email_line}#{avatar_line}
        USER
      end.join("\n")

      pagination_info = if result[:has_more]
        <<~INFO
          
          📄 **Page #{@list_users_page}** | Showing records #{start_index + 1}-#{end_index + 1}
          _More users available. Use `start_cursor: "#{result[:next_cursor]}"` to get the next page._
        INFO
      else
        # Try to estimate total if we're on last page
        estimated_total = start_index + users.count
        <<~INFO
          
          📄 **Page #{@list_users_page}** | Showing records #{start_index + 1}-#{end_index + 1} of #{estimated_total} total
        INFO
      end

      <<~OUTPUT
        👥 Found #{users.count} users in workspace:
        
        #{users_list}#{pagination_info}
      OUTPUT
    end

    def get_user(arguments)
      unless arguments["user_id"]
        raise "Missing required argument: user_id"
      end

      user_id = arguments["user_id"].to_s
      user = @notion_tool.get_user(user_id)

      email_line = user[:email] ? "\n**Email:** #{user[:email]}" : ""
      avatar_line = user[:avatar_url] ? "\n**Avatar:** #{user[:avatar_url]}" : ""

      <<~OUTPUT
        👤 **User Details**
        
        **Name:** #{user[:name] || "Unnamed"}
        **Type:** #{user[:type]}
        **ID:** `#{user[:id]}`#{email_line}#{avatar_line}
      OUTPUT
    end

    def get_bot_user
      bot = @notion_tool.get_bot_user

      workspace_line = bot[:bot][:workspace_name] ? "\n**Workspace:** #{bot[:bot][:workspace_name]}" : ""
      owner_line = bot[:bot][:owner] ? "\n**Owner:** #{bot[:bot][:owner]}" : ""

      <<~OUTPUT
        🤖 **Bot User Details**
        
        **Name:** #{bot[:name] || "Unnamed"}
        **Type:** #{bot[:type]}
        **ID:** `#{bot[:id]}`#{workspace_line}#{owner_line}
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
end

if __FILE__ == $0
  Notion::MCPServer.new.run
end
