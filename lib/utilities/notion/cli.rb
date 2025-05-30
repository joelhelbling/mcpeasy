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
  method_option :limit, type: :numeric, default: 10, aliases: "-l", desc: "Maximum number of results"
  def query_database(database_id)
    entries = tool.query_database(database_id, page_size: options[:limit])

    if entries && !entries.empty?
      puts "🗃️  Found #{entries.count} entries:"
      entries.each do |entry|
        puts "   #{entry[:title]}"
        puts "     ID: #{entry[:id]}"
        puts "     URL: #{entry[:url]}"
        puts "     Last edited: #{entry[:last_edited_time]}"
        puts
      end
    else
      puts "🗃️  No entries found in database"
    end
  rescue RuntimeError => e
    warn "❌ Failed to query database: #{e.message}"
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
