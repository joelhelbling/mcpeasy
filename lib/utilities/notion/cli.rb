# frozen_string_literal: true

require "bundler/setup"
require "thor"
require_relative "notion_tool"

class NotionCLI < Thor
  desc "test", "Test the Notion API connection"
  def test
    response = tool.test_connection

    if response[:ok]
      puts "✅ Successfully connected to Notion"
      puts "   User: #{response[:user]}"
      puts "   Type: #{response[:type]}"
    else
      warn "❌ Authentication failed: #{response[:error]}"
    end
  rescue RuntimeError => e
    puts "❌ Failed to connect to Notion: #{e.message}"
    exit 1
  end

  desc "search_pages QUERY", "Search for pages in Notion"
  method_option :limit, type: :numeric, default: 10, aliases: "-l", desc: "Maximum number of results"
  def search_pages(query = "")
    pages = tool.search_pages(query: query, page_size: options[:limit])

    if pages && !pages.empty?
      puts "📄 Found #{pages.count} pages:"
      pages.each do |page|
        puts "   #{page[:title]}"
        puts "     ID: #{page[:id]}"
        puts "     URL: #{page[:url]}"
        puts "     Last edited: #{page[:last_edited_time]}"
        puts
      end
    else
      puts "📄 No pages found for query: '#{query}'"
    end
  rescue RuntimeError => e
    warn "❌ Failed to search pages: #{e.message}"
    exit 1
  end

  desc "search_databases QUERY", "Search for databases in Notion"
  method_option :limit, type: :numeric, default: 10, aliases: "-l", desc: "Maximum number of results"
  def search_databases(query = "")
    databases = tool.search_databases(query: query, page_size: options[:limit])

    if databases && !databases.empty?
      puts "🗃️  Found #{databases.count} databases:"
      databases.each do |database|
        puts "   #{database[:title]}"
        puts "     ID: #{database[:id]}"
        puts "     URL: #{database[:url]}"
        puts "     Last edited: #{database[:last_edited_time]}"
        puts
      end
    else
      puts "🗃️  No databases found for query: '#{query}'"
    end
  rescue RuntimeError => e
    warn "❌ Failed to search databases: #{e.message}"
    exit 1
  end

  desc "get_page PAGE_ID", "Get details of a specific page"
  def get_page(page_id)
    page = tool.get_page(page_id)

    puts "📄 Page Details:"
    puts "   Title: #{page[:title]}"
    puts "   ID: #{page[:id]}"
    puts "   URL: #{page[:url]}"
    puts "   Created: #{page[:created_time]}"
    puts "   Last edited: #{page[:last_edited_time]}"
    puts
    puts "🏷️  Properties:"
    page[:properties].each do |name, prop|
      puts "   #{name}: #{format_property(prop)}"
    end
  rescue RuntimeError => e
    warn "❌ Failed to get page: #{e.message}"
    exit 1
  end

  desc "get_content PAGE_ID", "Get text content of a page"
  def get_content(page_id)
    content = tool.get_page_content(page_id)

    if content && !content.empty?
      puts "📝 Page Content:"
      puts content
    else
      puts "📝 No content found for this page"
    end
  rescue RuntimeError => e
    warn "❌ Failed to get page content: #{e.message}"
    exit 1
  end

  desc "query_database DATABASE_ID", "Query entries in a database"
  method_option :limit, type: :numeric, default: 100, aliases: "-l", desc: "Maximum number of results"
  method_option :cursor, type: :string, aliases: "-c", desc: "Pagination cursor from previous request"
  method_option :page, type: :numeric, default: 1, aliases: "-p", desc: "Page number (for calculating item numbers)"
  def query_database(database_id)
    page_size = options[:limit]
    start_cursor = options[:cursor]
    page_num = options[:page]

    result = tool.query_database(database_id, page_size: page_size, start_cursor: start_cursor)
    entries = result[:entries]

    if entries && !entries.empty?
      # Calculate starting index based on page number
      start_index = (page_num - 1) * page_size

      puts "🗃️  Found #{entries.count} entries (Page #{page_num}):"
      entries.each_with_index do |entry, i|
        puts "   #{start_index + i + 1}. #{entry[:title]}"
        puts "      ID: #{entry[:id]}"
        puts "      URL: #{entry[:url]}"
        puts "      Last edited: #{entry[:last_edited_time]}"
        puts
      end

      if result[:has_more]
        puts "📄 More entries available. To see next page, use:"
        puts "   mcpz notion query_database #{database_id} --cursor '#{result[:next_cursor]}' --page #{page_num + 1}"
      else
        puts "📄 End of database entries"
      end
    else
      puts "🗃️  No entries found in database"
    end
  rescue RuntimeError => e
    warn "❌ Failed to query database: #{e.message}"
    exit 1
  end

  desc "list_users", "List all users in the workspace"
  method_option :limit, type: :numeric, default: 100, aliases: "-l", desc: "Maximum number of results"
  method_option :cursor, type: :string, aliases: "-c", desc: "Pagination cursor from previous request"
  method_option :page, type: :numeric, default: 1, aliases: "-p", desc: "Page number (for calculating item numbers)"
  def list_users
    page_size = options[:limit]
    start_cursor = options[:cursor]
    page_num = options[:page]

    result = tool.list_users(page_size: page_size, start_cursor: start_cursor)
    users = result[:users]

    if users && !users.empty?
      # Calculate starting index based on page number
      start_index = (page_num - 1) * page_size

      puts "👥 Found #{users.count} users (Page #{page_num}):"
      users.each_with_index do |user, i|
        puts "   #{start_index + i + 1}. #{user[:name] || "Unnamed"} (#{user[:type]})"
        puts "      ID: #{user[:id]}"
        puts "      Email: #{user[:email]}" if user[:email]
        puts "      Avatar: #{user[:avatar_url]}" if user[:avatar_url]
        puts
      end

      if result[:has_more]
        puts "📄 More users available. To see next page, use:"
        puts "   mcpz notion list_users --cursor '#{result[:next_cursor]}' --page #{page_num + 1}"
      else
        puts "📄 End of user list"
      end
    else
      puts "👥 No users found"
    end
  rescue RuntimeError => e
    warn "❌ Failed to list users: #{e.message}"
    exit 1
  end

  desc "get_user USER_ID", "Get details of a specific user"
  def get_user(user_id)
    user = tool.get_user(user_id)

    puts "👤 User Details:"
    puts "   Name: #{user[:name] || "Unnamed"}"
    puts "   Type: #{user[:type]}"
    puts "   ID: #{user[:id]}"
    puts "   Email: #{user[:email]}" if user[:email]
    puts "   Avatar: #{user[:avatar_url]}" if user[:avatar_url]
  rescue RuntimeError => e
    warn "❌ Failed to get user: #{e.message}"
    exit 1
  end

  desc "bot_info", "Get information about the integration bot user"
  def bot_info
    bot = tool.get_bot_user

    puts "🤖 Bot User Details:"
    puts "   Name: #{bot[:name] || "Unnamed"}"
    puts "   Type: #{bot[:type]}"
    puts "   ID: #{bot[:id]}"
    puts "   Workspace: #{bot[:bot][:workspace_name]}" if bot[:bot][:workspace_name]
    puts "   Owner: #{bot[:bot][:owner]}" if bot[:bot][:owner]
  rescue RuntimeError => e
    warn "❌ Failed to get bot info: #{e.message}"
    exit 1
  end

  private

  def tool
    @tool ||= NotionTool.new
  end

  def format_property(prop)
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
