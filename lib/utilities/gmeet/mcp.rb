#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require_relative "service"

module Gmeet
  class MCPServer
    def initialize
      # Defer Service initialization until actually needed
      @gmeet_tool = nil
      @tools = {
        "test_connection" => {
          name: "test_connection",
          description: "Test the Google Calendar API connection",
          inputSchema: {
            type: "object",
            properties: {},
            required: []
          }
        },
        "list_meetings" => {
          name: "list_meetings",
          description: "List Google Meet meetings with optional date filtering",
          inputSchema: {
            type: "object",
            properties: {
              start_date: {
                type: "string",
                description: "Start date in YYYY-MM-DD format (default: today)"
              },
              end_date: {
                type: "string",
                description: "End date in YYYY-MM-DD format (default: 7 days from start)"
              },
              max_results: {
                type: "number",
                description: "Maximum number of meetings to return (default: 20)"
              },
              calendar_id: {
                type: "string",
                description: "Calendar ID to list meetings from (default: primary calendar)"
              }
            },
            required: []
          }
        },
        "upcoming_meetings" => {
          name: "upcoming_meetings",
          description: "List upcoming Google Meet meetings in the next 24 hours",
          inputSchema: {
            type: "object",
            properties: {
              max_results: {
                type: "number",
                description: "Maximum number of meetings to return (default: 10)"
              },
              calendar_id: {
                type: "string",
                description: "Calendar ID to list meetings from (default: primary calendar)"
              }
            },
            required: []
          }
        },
        "search_meetings" => {
          name: "search_meetings",
          description: "Search for Google Meet meetings by text content",
          inputSchema: {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "Search query to find meetings"
              },
              start_date: {
                type: "string",
                description: "Start date in YYYY-MM-DD format (default: today)"
              },
              end_date: {
                type: "string",
                description: "End date in YYYY-MM-DD format (default: 30 days from start)"
              },
              max_results: {
                type: "number",
                description: "Maximum number of meetings to return (default: 10)"
              }
            },
            required: ["query"]
          }
        },
        "get_meeting_url" => {
          name: "get_meeting_url",
          description: "Get the Google Meet URL for a specific event",
          inputSchema: {
            type: "object",
            properties: {
              event_id: {
                type: "string",
                description: "Calendar event ID"
              },
              calendar_id: {
                type: "string",
                description: "Calendar ID (default: primary calendar)"
              }
            },
            required: ["event_id"]
          }
        }
      }
    end

    def run
      # Disable stdout buffering for immediate response
      $stdout.sync = true

      # Log startup to file instead of stdout to avoid protocol interference
      Mcpeasy::Config.ensure_config_dirs
      File.write(Mcpeasy::Config.log_file_path("gmeet", "startup"), "#{Time.now}: Google Meet MCP Server starting on stdio\n", mode: "a")
      while (line = $stdin.gets)
        handle_request(line.strip)
      end
    rescue Interrupt
      # Silent shutdown
    rescue => e
      # Log to a file instead of stderr to avoid protocol interference
      File.write(Mcpeasy::Config.log_file_path("gmeet", "error"), "#{Time.now}: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
        File.write(Mcpeasy::Config.log_file_path("gmeet", "error"), "#{Time.now}: Error handling request: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
            name: "gmeet-mcp-server",
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
        File.write(Mcpeasy::Config.log_file_path("gmeet", "error"), "#{Time.now}: Tool error: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
      # Initialize Service only when needed
      @gmeet_tool ||= Service.new

      case tool_name
      when "test_connection"
        test_connection
      when "list_meetings"
        list_meetings(arguments)
      when "upcoming_meetings"
        upcoming_meetings(arguments)
      when "search_meetings"
        search_meetings(arguments)
      when "get_meeting_url"
        get_meeting_url(arguments)
      else
        raise "Unknown tool: #{tool_name}"
      end
    end

    def test_connection
      response = @gmeet_tool.test_connection
      if response[:ok]
        "✅ Successfully connected to Google Calendar.\n" \
        "   User: #{response[:user]} (#{response[:email]})"
      else
        raise "Connection test failed"
      end
    end

    def list_meetings(arguments)
      start_date = arguments["start_date"]
      end_date = arguments["end_date"]
      max_results = arguments["max_results"]&.to_i || 20
      calendar_id = arguments["calendar_id"] || "primary"

      result = @gmeet_tool.list_meetings(
        start_date: start_date,
        end_date: end_date,
        max_results: max_results,
        calendar_id: calendar_id
      )
      meetings = result[:meetings]

      if meetings.empty?
        "🎥 No Google Meet meetings found for the specified date range"
      else
        output = "🎥 Found #{result[:count]} Google Meet meeting(s):\n\n"
        meetings.each_with_index do |meeting, index|
          output << "#{index + 1}. **#{meeting[:summary] || "No title"}**\n"
          output << "   - Start: #{format_datetime(meeting[:start])}\n"
          output << "   - End: #{format_datetime(meeting[:end])}\n"
          output << "   - Description: #{meeting[:description] || "No description"}\n" if meeting[:description]
          output << "   - Location: #{meeting[:location]}\n" if meeting[:location]
          output << "   - Attendees: #{meeting[:attendees].join(", ")}\n" if meeting[:attendees]&.any?
          output << "   - **Meet Link: #{meeting[:meet_link]}**\n"
          output << "   - Calendar Link: #{meeting[:html_link]}\n\n"
        end
        output
      end
    end

    def upcoming_meetings(arguments)
      max_results = arguments["max_results"]&.to_i || 10
      calendar_id = arguments["calendar_id"] || "primary"

      result = @gmeet_tool.upcoming_meetings(
        max_results: max_results,
        calendar_id: calendar_id
      )
      meetings = result[:meetings]

      if meetings.empty?
        "🎥 No upcoming Google Meet meetings found in the next 24 hours"
      else
        output = "🎥 Found #{result[:count]} upcoming Google Meet meeting(s):\n\n"
        meetings.each_with_index do |meeting, index|
          output << "#{index + 1}. **#{meeting[:summary] || "No title"}**\n"
          output << "   - Start: #{format_datetime(meeting[:start])} (#{meeting[:time_until_start]})\n"
          output << "   - End: #{format_datetime(meeting[:end])}\n"
          output << "   - Description: #{meeting[:description] || "No description"}\n" if meeting[:description]
          output << "   - Location: #{meeting[:location]}\n" if meeting[:location]
          output << "   - Attendees: #{meeting[:attendees].join(", ")}\n" if meeting[:attendees]&.any?
          output << "   - **Meet Link: #{meeting[:meet_link]}**\n"
          output << "   - Calendar Link: #{meeting[:html_link]}\n\n"
        end
        output
      end
    end

    def search_meetings(arguments)
      unless arguments["query"]
        raise "Missing required argument: query"
      end

      query = arguments["query"].to_s
      start_date = arguments["start_date"]
      end_date = arguments["end_date"]
      max_results = arguments["max_results"]&.to_i || 10

      result = @gmeet_tool.search_meetings(
        query,
        start_date: start_date,
        end_date: end_date,
        max_results: max_results
      )
      meetings = result[:meetings]

      if meetings.empty?
        "🔍 No Google Meet meetings found matching '#{query}'"
      else
        output = "🔍 Found #{result[:count]} Google Meet meeting(s) matching '#{query}':\n\n"
        meetings.each_with_index do |meeting, index|
          output << "#{index + 1}. **#{meeting[:summary] || "No title"}**\n"
          output << "   - Start: #{format_datetime(meeting[:start])}\n"
          output << "   - End: #{format_datetime(meeting[:end])}\n"
          output << "   - Description: #{meeting[:description] || "No description"}\n" if meeting[:description]
          output << "   - Location: #{meeting[:location]}\n" if meeting[:location]
          output << "   - **Meet Link: #{meeting[:meet_link]}**\n"
          output << "   - Calendar Link: #{meeting[:html_link]}\n\n"
        end
        output
      end
    end

    def get_meeting_url(arguments)
      unless arguments["event_id"]
        raise "Missing required argument: event_id"
      end

      event_id = arguments["event_id"].to_s
      calendar_id = arguments["calendar_id"] || "primary"

      result = @gmeet_tool.get_meeting_url(event_id, calendar_id: calendar_id)

      output = "🎥 **#{result[:summary] || "Meeting"}**\n"
      output << "   - Start: #{format_datetime(result[:start])}\n"
      output << "   - End: #{format_datetime(result[:end])}\n"
      output << "   - **Meet Link: #{result[:meet_link]}**\n"
      output << "   - Event ID: #{result[:event_id]}\n"

      output
    end

    private

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

if __FILE__ == $0
  Gmeet::MCPServer.new.run
end
