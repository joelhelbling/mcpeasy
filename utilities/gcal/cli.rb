# frozen_string_literal: true

require "bundler/setup"
require "thor"
require_relative "gcal_tool"

class GcalCLI < Thor
  desc "auth", "Authenticate with Google Calendar API"
  def auth
    tool = GcalTool.new(skip_auth: true)
    puts "🔐 Starting Google Calendar authentication flow..."
    tool.perform_auth_flow
  rescue => e
    puts "❌ Authentication failed: #{e.message}"
    exit 1
  end

  desc "test", "Test the Google Calendar API connection"
  def test
    response = tool.test_connection

    if response[:ok]
      puts "✅ Successfully connected to Google Calendar"
      puts "   User: #{response[:user]} (#{response[:email]})"
    else
      warn "❌ Connection test failed"
    end
  rescue RuntimeError => e
    puts "❌ Failed to connect to Google Calendar: #{e.message}"
    exit 1
  end

  desc "events", "List calendar events"
  method_option :start_date, type: :string, aliases: "-s", desc: "Start date (YYYY-MM-DD)"
  method_option :end_date, type: :string, aliases: "-e", desc: "End date (YYYY-MM-DD)"
  method_option :max_results, type: :numeric, default: 20, aliases: "-n", desc: "Max number of events"
  method_option :calendar_id, type: :string, aliases: "-c", desc: "Calendar ID (default: primary)"
  def events
    result = tool.list_events(
      start_date: options[:start_date],
      end_date: options[:end_date],
      max_results: options[:max_results],
      calendar_id: options[:calendar_id] || "primary"
    )
    events = result[:events]

    if events.empty?
      puts "📅 No events found for the specified date range"
    else
      puts "📅 Found #{result[:count]} event(s):"
      events.each_with_index do |event, index|
        puts "   #{index + 1}. #{event[:summary] || "No title"}"
        puts "      Start: #{format_datetime(event[:start])}"
        puts "      End: #{format_datetime(event[:end])}"
        puts "      Description: #{event[:description]}" if event[:description]
        puts "      Location: #{event[:location]}" if event[:location]
        puts "      Attendees: #{event[:attendees].join(", ")}" if event[:attendees]&.any?
        puts "      Link: #{event[:html_link]}"
        puts
      end
    end
  rescue RuntimeError => e
    warn "❌ Failed to list events: #{e.message}"
    exit 1
  end

  desc "calendars", "List available calendars"
  def calendars
    result = tool.list_calendars
    calendars = result[:calendars]

    if calendars.empty?
      puts "📋 No calendars found"
    else
      puts "📋 Found #{result[:count]} calendar(s):"
      calendars.each_with_index do |calendar, index|
        puts "   #{index + 1}. #{calendar[:summary]}"
        puts "      ID: #{calendar[:id]}"
        puts "      Description: #{calendar[:description]}" if calendar[:description]
        puts "      Time Zone: #{calendar[:time_zone]}"
        puts "      Access Role: #{calendar[:access_role]}"
        puts "      Primary: Yes" if calendar[:primary]
        puts
      end
    end
  rescue RuntimeError => e
    warn "❌ Failed to list calendars: #{e.message}"
    exit 1
  end

  desc "search QUERY", "Search for events by text content"
  method_option :start_date, type: :string, aliases: "-s", desc: "Start date (YYYY-MM-DD)"
  method_option :end_date, type: :string, aliases: "-e", desc: "End date (YYYY-MM-DD)"
  method_option :max_results, type: :numeric, default: 10, aliases: "-n", desc: "Max number of events"
  def search(query)
    result = tool.search_events(
      query,
      start_date: options[:start_date],
      end_date: options[:end_date],
      max_results: options[:max_results]
    )
    events = result[:events]

    if events.empty?
      puts "🔍 No events found matching '#{query}'"
    else
      puts "🔍 Found #{result[:count]} event(s) matching '#{query}':"
      events.each_with_index do |event, index|
        puts "   #{index + 1}. #{event[:summary] || "No title"}"
        puts "      Start: #{format_datetime(event[:start])}"
        puts "      End: #{format_datetime(event[:end])}"
        puts "      Description: #{event[:description]}" if event[:description]
        puts "      Location: #{event[:location]}" if event[:location]
        puts "      Calendar: #{event[:calendar_id]}"
        puts "      Link: #{event[:html_link]}"
        puts
      end
    end
  rescue RuntimeError => e
    warn "❌ Failed to search events: #{e.message}"
    exit 1
  end

  private

  def tool
    @tool ||= GcalTool.new
  end

  def format_datetime(datetime_info)
    return "Unknown" unless datetime_info

    if datetime_info[:date]
      # All-day event
      datetime_info[:date]
    elsif datetime_info[:date_time]
      # Specific time event
      time = Time.parse(datetime_info[:date_time])
      time.strftime("%Y-%m-%d %H:%M")
    else
      "Unknown"
    end
  end
end

GcalCLI.start(ARGV)