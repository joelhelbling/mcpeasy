#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require_relative "service"

module Gcal
  class MCPServer
    def initialize
      @prompts = [
        {
          name: "check_schedule",
          description: "Check your calendar schedule for a specific time period",
          arguments: [
            {
              name: "period",
              description: "Time period to check (e.g., 'today', 'tomorrow', 'this week', 'next Monday')",
              required: true
            }
          ]
        },
        {
          name: "find_meeting",
          description: "Find a specific meeting or event by searching for keywords",
          arguments: [
            {
              name: "keywords",
              description: "Keywords to search for in event titles and descriptions",
              required: true
            }
          ]
        },
        {
          name: "check_availability",
          description: "Check if you're free at a specific time",
          arguments: [
            {
              name: "datetime",
              description: "Date and time to check (e.g., 'tomorrow at 2pm', 'next Tuesday afternoon')",
              required: true
            }
          ]
        },
        {
          name: "weekly_overview",
          description: "Get an overview of your schedule for the upcoming week",
          arguments: []
        },
        {
          name: "meeting_conflicts",
          description: "Check for any overlapping or back-to-back meetings",
          arguments: [
            {
              name: "date",
              description: "Date to check for conflicts (default: today)",
              required: false
            }
          ]
        }
      ]

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
        "list_events" => {
          name: "list_events",
          description: "List calendar events with optional date filtering",
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
                description: "Maximum number of events to return (default: 20)"
              },
              calendar_id: {
                type: "string",
                description: "Calendar ID to list events from (default: primary calendar)"
              }
            },
            required: []
          }
        },
        "list_calendars" => {
          name: "list_calendars",
          description: "List available calendars",
          inputSchema: {
            type: "object",
            properties: {},
            required: []
          }
        },
        "search_events" => {
          name: "search_events",
          description: "Search for events by text content",
          inputSchema: {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "Search query to find events"
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
                description: "Maximum number of events to return (default: 10)"
              }
            },
            required: ["query"]
          }
        }
      }
    end

    def run
      # Disable stdout buffering for immediate response
      $stdout.sync = true

      # Log startup to file instead of stdout to avoid protocol interference
      Mcpeasy::Config.ensure_config_dirs
      File.write(Mcpeasy::Config.log_file_path("gcal", "startup"), "#{Time.now}: Google Calendar MCP Server starting on stdio\n", mode: "a")
      while (line = $stdin.gets)
        handle_request(line.strip)
      end
    rescue Interrupt
      # Silent shutdown
    rescue => e
      # Log to a file instead of stderr to avoid protocol interference
      File.write(Mcpeasy::Config.log_file_path("gcal", "error"), "#{Time.now}: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
        File.write(Mcpeasy::Config.log_file_path("gcal", "error"), "#{Time.now}: Error handling request: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
            name: "gcal-mcp-server",
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
        File.write(Mcpeasy::Config.log_file_path("gcal", "error"), "#{Time.now}: Tool error: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
      when "check_schedule"
        period = params["arguments"]&.dig("period") || "today"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Check my calendar schedule for #{period}"
            }
          }
        ]
      when "find_meeting"
        keywords = params["arguments"]&.dig("keywords") || ""
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Find meetings containing: #{keywords}"
            }
          }
        ]
      when "check_availability"
        datetime = params["arguments"]&.dig("datetime") || "today"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Am I free at #{datetime}?"
            }
          }
        ]
      when "weekly_overview"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Give me an overview of my schedule for the upcoming week"
            }
          }
        ]
      when "meeting_conflicts"
        date = params["arguments"]&.dig("date") || "today"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Check for any overlapping or back-to-back meetings on #{date}"
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
      case tool_name
      when "test_connection"
        test_connection
      when "list_events"
        list_events(arguments)
      when "list_calendars"
        list_calendars(arguments)
      when "search_events"
        search_events(arguments)
      else
        raise "Unknown tool: #{tool_name}"
      end
    end

    def test_connection
      tool = Service.new
      response = tool.test_connection
      if response[:ok]
        "✅ Successfully connected to Google Calendar.\n" \
        "   User: #{response[:user]} (#{response[:email]})"
      else
        raise "Connection test failed"
      end
    end

    def list_events(arguments)
      start_date = arguments["start_date"]
      end_date = arguments["end_date"]
      max_results = arguments["max_results"]&.to_i || 20
      calendar_id = arguments["calendar_id"] || "primary"

      tool = Service.new
      result = tool.list_events(
        start_date: start_date,
        end_date: end_date,
        max_results: max_results,
        calendar_id: calendar_id
      )
      events = result[:events]

      if events.empty?
        "📅 No events found for the specified date range"
      else
        output = "📅 Found #{result[:count]} event(s):\n\n"
        events.each_with_index do |event, index|
          output << "#{index + 1}. **#{event[:summary] || "No title"}**\n"
          output << "   - Start: #{format_datetime(event[:start])}\n"
          output << "   - End: #{format_datetime(event[:end])}\n"
          output << "   - Description: #{event[:description] || "No description"}\n" if event[:description]
          output << "   - Location: #{event[:location]}\n" if event[:location]
          output << "   - Attendees: #{event[:attendees].join(", ")}\n" if event[:attendees]&.any?
          output << "   - Link: #{event[:html_link]}\n\n"
        end
        output
      end
    end

    def list_calendars(arguments)
      tool = Service.new
      result = tool.list_calendars
      calendars = result[:calendars]

      if calendars.empty?
        "📋 No calendars found"
      else
        output = "📋 Found #{result[:count]} calendar(s):\n\n"
        calendars.each_with_index do |calendar, index|
          output << "#{index + 1}. **#{calendar[:summary]}**\n"
          output << "   - ID: `#{calendar[:id]}`\n"
          output << "   - Description: #{calendar[:description]}\n" if calendar[:description]
          output << "   - Time Zone: #{calendar[:time_zone]}\n"
          output << "   - Access Role: #{calendar[:access_role]}\n"
          output << "   - Primary: Yes\n" if calendar[:primary]
          output << "\n"
        end
        output
      end
    end

    def search_events(arguments)
      unless arguments["query"]
        raise "Missing required argument: query"
      end

      query = arguments["query"].to_s
      start_date = arguments["start_date"]
      end_date = arguments["end_date"]
      max_results = arguments["max_results"]&.to_i || 10

      tool = Service.new
      result = tool.search_events(
        query,
        start_date: start_date,
        end_date: end_date,
        max_results: max_results
      )
      events = result[:events]

      if events.empty?
        "🔍 No events found matching '#{query}'"
      else
        output = "🔍 Found #{result[:count]} event(s) matching '#{query}':\n\n"
        events.each_with_index do |event, index|
          output << "#{index + 1}. **#{event[:summary] || "No title"}**\n"
          output << "   - Start: #{format_datetime(event[:start])}\n"
          output << "   - End: #{format_datetime(event[:end])}\n"
          output << "   - Description: #{event[:description] || "No description"}\n" if event[:description]
          output << "   - Location: #{event[:location]}\n" if event[:location]
          output << "   - Calendar: #{event[:calendar_id]}\n"
          output << "   - Link: #{event[:html_link]}\n\n"
        end
        output
      end
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
  Gcal::MCPServer.new.run
end
