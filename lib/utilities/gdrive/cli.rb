# frozen_string_literal: true

require "bundler/setup"
require "thor"
require_relative "gdrive_tool"

class GdriveCLI < Thor
  desc "test", "Test the Google Drive API connection"
  def test
    response = tool.test_connection

    if response[:ok]
      puts "✅ Successfully connected to Google Drive"
      puts "   User: #{response[:user]} (#{response[:email]})"
      if response[:storage_used] && response[:storage_limit]
        puts "   Storage: #{format_bytes(response[:storage_used])} / #{format_bytes(response[:storage_limit])}"
      end
    else
      warn "❌ Connection test failed"
    end
  rescue RuntimeError => e
    puts "❌ Failed to connect to Google Drive: #{e.message}"
    exit 1
  end

  desc "search QUERY", "Search for files in Google Drive"
  method_option :max_results, type: :numeric, default: 10, aliases: "-n"
  def search(query)
    result = tool.search_files(query, max_results: options[:max_results])
    files = result[:files]

    if files.empty?
      puts "🔍 No files found matching '#{query}'"
    else
      puts "🔍 Found #{result[:count]} file(s) matching '#{query}':"
      files.each_with_index do |file, index|
        puts "   #{index + 1}. #{file[:name]}"
        puts "      ID: #{file[:id]}"
        puts "      Type: #{file[:mime_type]}"
        puts "      Size: #{format_bytes(file[:size])}"
        puts "      Modified: #{file[:modified_time]}"
        puts "      Link: #{file[:web_view_link]}"
        puts
      end
    end
  rescue RuntimeError => e
    warn "❌ Failed to search files: #{e.message}"
    exit 1
  end

  desc "list", "List recent files in Google Drive"
  method_option :max_results, type: :numeric, default: 20, aliases: "-n"
  def list
    result = tool.list_files(max_results: options[:max_results])
    files = result[:files]

    if files.empty?
      puts "📂 No files found in Google Drive"
    else
      puts "📂 Recent #{result[:count]} file(s):"
      files.each_with_index do |file, index|
        puts "   #{index + 1}. #{file[:name]}"
        puts "      ID: #{file[:id]}"
        puts "      Type: #{file[:mime_type]}"
        puts "      Size: #{format_bytes(file[:size])}"
        puts "      Modified: #{file[:modified_time]}"
        puts "      Link: #{file[:web_view_link]}"
        puts
      end
    end
  rescue RuntimeError => e
    warn "❌ Failed to list files: #{e.message}"
    exit 1
  end

  desc "get FILE_ID", "Get content of a specific file"
  method_option :output, type: :string, aliases: "-o", desc: "Output file path"
  def get(file_id)
    result = tool.get_file_content(file_id)

    puts "📄 #{result[:name]}"
    puts "   Type: #{result[:mime_type]}"
    puts "   Size: #{format_bytes(result[:size])}"
    puts

    if options[:output]
      File.write(options[:output], result[:content])
      puts "✅ Content saved to #{options[:output]}"
    else
      puts "Content:"
      puts result[:content]
    end
  rescue RuntimeError => e
    warn "❌ Failed to get file content: #{e.message}"
    exit 1
  end

  private

  def tool
    @tool ||= GdriveTool.new
  end

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
