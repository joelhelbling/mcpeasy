# frozen_string_literal: true

require "bundler/setup"
require "thor"
require_relative "service"

module Gmeet
  class CLI < Thor
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

    desc "meetings", "List Google Meet meetings"
    method_option :start_date, type: :string, aliases: "-s", desc: "Start date (YYYY-MM-DD)"
    method_option :end_date, type: :string, aliases: "-e", desc: "End date (YYYY-MM-DD)"
    method_option :max_results, type: :numeric, default: 20, aliases: "-n", desc: "Max number of meetings"
    method_option :calendar_id, type: :string, aliases: "-c", desc: "Calendar ID (default: primary)"
    def meetings
      result = tool.list_meetings(
        start_date: options[:start_date],
        end_date: options[:end_date],
        max_results: options[:max_results],
        calendar_id: options[:calendar_id] || "primary"
      )
      meetings = result[:meetings]

      if meetings.empty?
        puts "🎥 No Google Meet meetings found for the specified date range"
      else
        puts "🎥 Found #{result[:count]} Google Meet meeting(s):"
        meetings.each_with_index do |meeting, index|
          puts "   #{index + 1}. #{meeting[:summary] || "No title"}"
          puts "      Start: #{format_datetime(meeting[:start])}"
          puts "      End: #{format_datetime(meeting[:end])}"
          puts "      Description: #{meeting[:description]}" if meeting[:description]
          puts "      Location: #{meeting[:location]}" if meeting[:location]
          puts "      Attendees: #{meeting[:attendees].join(", ")}" if meeting[:attendees]&.any?
          puts "      Meet Link: #{meeting[:meet_link]}"
          puts "      Calendar Link: #{meeting[:html_link]}"
          puts
        end
      end
    rescue RuntimeError => e
      warn "❌ Failed to list meetings: #{e.message}"
      exit 1
    end

    desc "upcoming", "List upcoming Google Meet meetings"
    method_option :max_results, type: :numeric, default: 10, aliases: "-n", desc: "Max number of meetings"
    method_option :calendar_id, type: :string, aliases: "-c", desc: "Calendar ID (default: primary)"
    def upcoming
      result = tool.upcoming_meetings(
        max_results: options[:max_results],
        calendar_id: options[:calendar_id] || "primary"
      )
      meetings = result[:meetings]

      if meetings.empty?
        puts "🎥 No upcoming Google Meet meetings found in the next 24 hours"
      else
        puts "🎥 Found #{result[:count]} upcoming Google Meet meeting(s):"
        meetings.each_with_index do |meeting, index|
          puts "   #{index + 1}. #{meeting[:summary] || "No title"}"
          puts "      Start: #{format_datetime(meeting[:start])} (#{meeting[:time_until_start]})"
          puts "      End: #{format_datetime(meeting[:end])}"
          puts "      Description: #{meeting[:description]}" if meeting[:description]
          puts "      Location: #{meeting[:location]}" if meeting[:location]
          puts "      Attendees: #{meeting[:attendees].join(", ")}" if meeting[:attendees]&.any?
          puts "      Meet Link: #{meeting[:meet_link]}"
          puts "      Calendar Link: #{meeting[:html_link]}"
          puts
        end
      end
    rescue RuntimeError => e
      warn "❌ Failed to list upcoming meetings: #{e.message}"
      exit 1
    end

    desc "search QUERY", "Search for Google Meet meetings by text content"
    method_option :start_date, type: :string, aliases: "-s", desc: "Start date (YYYY-MM-DD)"
    method_option :end_date, type: :string, aliases: "-e", desc: "End date (YYYY-MM-DD)"
    method_option :max_results, type: :numeric, default: 10, aliases: "-n", desc: "Max number of meetings"
    def search(query)
      result = tool.search_meetings(
        query,
        start_date: options[:start_date],
        end_date: options[:end_date],
        max_results: options[:max_results]
      )
      meetings = result[:meetings]

      if meetings.empty?
        puts "🔍 No Google Meet meetings found matching '#{query}'"
      else
        puts "🔍 Found #{result[:count]} Google Meet meeting(s) matching '#{query}':"
        meetings.each_with_index do |meeting, index|
          puts "   #{index + 1}. #{meeting[:summary] || "No title"}"
          puts "      Start: #{format_datetime(meeting[:start])}"
          puts "      End: #{format_datetime(meeting[:end])}"
          puts "      Description: #{meeting[:description]}" if meeting[:description]
          puts "      Location: #{meeting[:location]}" if meeting[:location]
          puts "      Meet Link: #{meeting[:meet_link]}"
          puts "      Calendar Link: #{meeting[:html_link]}"
          puts
        end
      end
    rescue RuntimeError => e
      warn "❌ Failed to search meetings: #{e.message}"
      exit 1
    end

    desc "url EVENT_ID", "Get the Google Meet URL for a specific event"
    method_option :calendar_id, type: :string, aliases: "-c", desc: "Calendar ID (default: primary)"
    def url(event_id)
      result = tool.get_meeting_url(event_id, calendar_id: options[:calendar_id] || "primary")

      puts "🎥 #{result[:summary] || "Meeting"}"
      puts "   Start: #{format_datetime(result[:start])}"
      puts "   End: #{format_datetime(result[:end])}"
      puts "   Meet Link: #{result[:meet_link]}"
      puts "   Event ID: #{result[:event_id]}"
    rescue RuntimeError => e
      warn "❌ Failed to get meeting URL: #{e.message}"
      exit 1
    end

    private

    def tool
      @tool ||= Service.new
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
end
