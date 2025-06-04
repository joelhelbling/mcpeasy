#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require_relative "service"

module Gmail
  class MCPServer
    def initialize
      @prompts = [
        {
          name: "check_email",
          description: "Check your email inbox for new messages",
          arguments: [
            {
              name: "filter",
              description: "Optional filter (e.g., 'unread', 'from:someone@example.com', 'subject:urgent')",
              required: false
            }
          ]
        },
        {
          name: "compose_email",
          description: "Compose and send a new email",
          arguments: [
            {
              name: "to",
              description: "Recipient email address",
              required: true
            },
            {
              name: "subject",
              description: "Email subject line",
              required: true
            },
            {
              name: "body",
              description: "Email body content",
              required: true
            }
          ]
        },
        {
          name: "email_search",
          description: "Search through your emails for specific content",
          arguments: [
            {
              name: "query",
              description: "Search query (e.g., keywords, sender, subject filters)",
              required: true
            }
          ]
        },
        {
          name: "email_management",
          description: "Manage emails (mark as read/unread, archive, label, etc.)",
          arguments: [
            {
              name: "action",
              description: "Action to perform (read, unread, archive, trash, label)",
              required: true
            },
            {
              name: "email_id",
              description: "ID of the email to manage",
              required: true
            }
          ]
        }
      ]

      @tools = {
        "test_connection" => {
          name: "test_connection",
          description: "Test the Gmail API connection",
          inputSchema: {
            type: "object",
            properties: {},
            required: []
          }
        },
        "list_emails" => {
          name: "list_emails",
          description: "List emails with filtering by date range, sender, subject, labels, read/unread status",
          inputSchema: {
            type: "object",
            properties: {
              start_date: {
                type: "string",
                description: "Start date in YYYY-MM-DD format"
              },
              end_date: {
                type: "string",
                description: "End date in YYYY-MM-DD format"
              },
              max_results: {
                type: "number",
                description: "Maximum number of emails to return (default: 20)"
              },
              sender: {
                type: "string",
                description: "Filter by sender email address"
              },
              subject: {
                type: "string",
                description: "Filter by subject content"
              },
              labels: {
                type: "string",
                description: "Filter by labels (comma-separated)"
              },
              read_status: {
                type: "string",
                description: "Filter by read status (read/unread)"
              }
            },
            required: []
          }
        },
        "search_emails" => {
          name: "search_emails",
          description: "Search emails using Gmail search syntax",
          inputSchema: {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "Search query using Gmail search syntax"
              },
              max_results: {
                type: "number",
                description: "Maximum number of emails to return (default: 10)"
              }
            },
            required: ["query"]
          }
        },
        "get_email_content" => {
          name: "get_email_content",
          description: "Get full content of a specific email including body, headers, and attachments info",
          inputSchema: {
            type: "object",
            properties: {
              email_id: {
                type: "string",
                description: "Gmail message ID"
              }
            },
            required: ["email_id"]
          }
        },
        "send_email" => {
          name: "send_email",
          description: "Send a new email",
          inputSchema: {
            type: "object",
            properties: {
              to: {
                type: "string",
                description: "Recipient email address"
              },
              subject: {
                type: "string",
                description: "Email subject"
              },
              body: {
                type: "string",
                description: "Email body content"
              },
              cc: {
                type: "string",
                description: "CC email address"
              },
              bcc: {
                type: "string",
                description: "BCC email address"
              },
              reply_to: {
                type: "string",
                description: "Reply-to email address"
              }
            },
            required: ["to", "subject", "body"]
          }
        },
        "reply_to_email" => {
          name: "reply_to_email",
          description: "Reply to an existing email",
          inputSchema: {
            type: "object",
            properties: {
              email_id: {
                type: "string",
                description: "Gmail message ID to reply to"
              },
              body: {
                type: "string",
                description: "Reply body content"
              },
              include_quoted: {
                type: "boolean",
                description: "Include quoted original message (default: true)"
              }
            },
            required: ["email_id", "body"]
          }
        },
        "mark_as_read" => {
          name: "mark_as_read",
          description: "Mark an email as read",
          inputSchema: {
            type: "object",
            properties: {
              email_id: {
                type: "string",
                description: "Gmail message ID"
              }
            },
            required: ["email_id"]
          }
        },
        "mark_as_unread" => {
          name: "mark_as_unread",
          description: "Mark an email as unread",
          inputSchema: {
            type: "object",
            properties: {
              email_id: {
                type: "string",
                description: "Gmail message ID"
              }
            },
            required: ["email_id"]
          }
        },
        "add_label" => {
          name: "add_label",
          description: "Add a label to an email",
          inputSchema: {
            type: "object",
            properties: {
              email_id: {
                type: "string",
                description: "Gmail message ID"
              },
              label: {
                type: "string",
                description: "Label name to add"
              }
            },
            required: ["email_id", "label"]
          }
        },
        "remove_label" => {
          name: "remove_label",
          description: "Remove a label from an email",
          inputSchema: {
            type: "object",
            properties: {
              email_id: {
                type: "string",
                description: "Gmail message ID"
              },
              label: {
                type: "string",
                description: "Label name to remove"
              }
            },
            required: ["email_id", "label"]
          }
        },
        "archive_email" => {
          name: "archive_email",
          description: "Archive an email (remove from inbox)",
          inputSchema: {
            type: "object",
            properties: {
              email_id: {
                type: "string",
                description: "Gmail message ID"
              }
            },
            required: ["email_id"]
          }
        },
        "trash_email" => {
          name: "trash_email",
          description: "Move an email to trash",
          inputSchema: {
            type: "object",
            properties: {
              email_id: {
                type: "string",
                description: "Gmail message ID"
              }
            },
            required: ["email_id"]
          }
        }
      }
    end

    def run
      # Disable stdout buffering for immediate response
      $stdout.sync = true

      # Log startup to file instead of stdout to avoid protocol interference
      Mcpeasy::Config.ensure_config_dirs
      File.write(Mcpeasy::Config.log_file_path("gmail", "startup"), "#{Time.now}: Gmail MCP Server starting on stdio\n", mode: "a")
      while (line = $stdin.gets)
        handle_request(line.strip)
      end
    rescue Interrupt
      # Silent shutdown
    rescue => e
      # Log to a file instead of stderr to avoid protocol interference
      File.write(Mcpeasy::Config.log_file_path("gmail", "error"), "#{Time.now}: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
        File.write(Mcpeasy::Config.log_file_path("gmail", "error"), "#{Time.now}: Error handling request: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
            name: "gmail-mcp-server",
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
        File.write(Mcpeasy::Config.log_file_path("gmail", "error"), "#{Time.now}: Tool error: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
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
      when "check_email"
        filter = params["arguments"]&.dig("filter") || ""
        filter_text = filter.empty? ? "" : " with filter: #{filter}"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Check my email inbox#{filter_text}"
            }
          }
        ]
      when "compose_email"
        to = params["arguments"]&.dig("to") || "recipient@example.com"
        subject = params["arguments"]&.dig("subject") || "Subject"
        body = params["arguments"]&.dig("body") || "Email content"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Compose and send an email to #{to} with subject '#{subject}' and body: #{body}"
            }
          }
        ]
      when "email_search"
        query = params["arguments"]&.dig("query") || ""
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Search my emails for: #{query}"
            }
          }
        ]
      when "email_management"
        action = params["arguments"]&.dig("action") || "read"
        email_id = params["arguments"]&.dig("email_id") || "email_id"
        [
          {
            role: "user",
            content: {
              type: "text",
              text: "Perform #{action} action on email #{email_id}"
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
      when "list_emails"
        list_emails(arguments)
      when "search_emails"
        search_emails(arguments)
      when "get_email_content"
        get_email_content(arguments)
      when "send_email"
        send_email(arguments)
      when "reply_to_email"
        reply_to_email(arguments)
      when "mark_as_read"
        mark_as_read(arguments)
      when "mark_as_unread"
        mark_as_unread(arguments)
      when "add_label"
        add_label(arguments)
      when "remove_label"
        remove_label(arguments)
      when "archive_email"
        archive_email(arguments)
      when "trash_email"
        trash_email(arguments)
      else
        raise "Unknown tool: #{tool_name}"
      end
    end

    def test_connection
      tool = Service.new
      response = tool.test_connection
      if response[:ok]
        "✅ Successfully connected to Gmail.\n" \
        "   Email: #{response[:email]}\n" \
        "   Messages: #{response[:messages_total]}\n" \
        "   Threads: #{response[:threads_total]}"
      else
        raise "Connection test failed"
      end
    end

    def list_emails(arguments)
      start_date = arguments["start_date"]
      end_date = arguments["end_date"]
      max_results = arguments["max_results"]&.to_i || 20
      sender = arguments["sender"]
      subject = arguments["subject"]
      labels = arguments["labels"]&.split(",")&.map(&:strip)
      read_status = arguments["read_status"]

      tool = Service.new
      result = tool.list_emails(
        start_date: start_date,
        end_date: end_date,
        max_results: max_results,
        sender: sender,
        subject: subject,
        labels: labels,
        read_status: read_status
      )
      emails = result[:emails]

      if emails.empty?
        "📧 No emails found for the specified criteria"
      else
        output = "📧 Found #{result[:count]} email(s):\n\n"
        emails.each_with_index do |email, index|
          output << "#{index + 1}. **#{email[:subject] || "No subject"}**\n"
          output << "   - From: #{email[:from]}\n"
          output << "   - Date: #{email[:date]}\n"
          output << "   - Snippet: #{email[:snippet]}\n" if email[:snippet]
          output << "   - Labels: #{email[:labels].join(", ")}\n" if email[:labels]&.any?
          output << "   - ID: `#{email[:id]}`\n\n"
        end
        output
      end
    end

    def search_emails(arguments)
      unless arguments["query"]
        raise "Missing required argument: query"
      end

      query = arguments["query"].to_s
      max_results = arguments["max_results"]&.to_i || 10

      tool = Service.new
      result = tool.search_emails(query, max_results: max_results)
      emails = result[:emails]

      if emails.empty?
        "🔍 No emails found matching '#{query}'"
      else
        output = "🔍 Found #{result[:count]} email(s) matching '#{query}':\n\n"
        emails.each_with_index do |email, index|
          output << "#{index + 1}. **#{email[:subject] || "No subject"}**\n"
          output << "   - From: #{email[:from]}\n"
          output << "   - Date: #{email[:date]}\n"
          output << "   - Snippet: #{email[:snippet]}\n" if email[:snippet]
          output << "   - ID: `#{email[:id]}`\n\n"
        end
        output
      end
    end

    def get_email_content(arguments)
      unless arguments["email_id"]
        raise "Missing required argument: email_id"
      end

      email_id = arguments["email_id"].to_s
      tool = Service.new
      email = tool.get_email_content(email_id)

      output = "📧 **Email Details:**\n\n"
      output << "- **ID:** `#{email[:id]}`\n"
      output << "- **Thread ID:** `#{email[:thread_id]}`\n"
      output << "- **Subject:** #{email[:subject] || "No subject"}\n"
      output << "- **From:** #{email[:from]}\n"
      output << "- **To:** #{email[:to]}\n"
      output << "- **CC:** #{email[:cc]}\n" if email[:cc]
      output << "- **BCC:** #{email[:bcc]}\n" if email[:bcc]
      output << "- **Date:** #{email[:date]}\n"
      output << "- **Labels:** #{email[:labels].join(", ")}\n" if email[:labels]&.any?

      if email[:attachments]&.any?
        output << "- **Attachments:**\n"
        email[:attachments].each do |attachment|
          output << "  - #{attachment[:filename]} (#{attachment[:mime_type]}, #{attachment[:size]} bytes)\n"
        end
      end

      output << "\n**Body:**\n```\n#{email[:body]}\n```"
      output
    end

    def send_email(arguments)
      required_args = ["to", "subject", "body"]
      missing_args = required_args.select { |arg| arguments[arg].nil? || arguments[arg].empty? }
      unless missing_args.empty?
        raise "Missing required arguments: #{missing_args.join(", ")}"
      end

      tool = Service.new
      result = tool.send_email(
        to: arguments["to"],
        subject: arguments["subject"],
        body: arguments["body"],
        cc: arguments["cc"],
        bcc: arguments["bcc"],
        reply_to: arguments["reply_to"]
      )

      if result[:success]
        "✅ Email sent successfully\n" \
        "   Message ID: #{result[:message_id]}\n" \
        "   Thread ID: #{result[:thread_id]}"
      else
        raise "Failed to send email"
      end
    end

    def reply_to_email(arguments)
      required_args = ["email_id", "body"]
      missing_args = required_args.select { |arg| arguments[arg].nil? || arguments[arg].empty? }
      unless missing_args.empty?
        raise "Missing required arguments: #{missing_args.join(", ")}"
      end

      tool = Service.new
      result = tool.reply_to_email(
        email_id: arguments["email_id"],
        body: arguments["body"],
        include_quoted: arguments["include_quoted"] != false
      )

      if result[:success]
        "✅ Reply sent successfully\n" \
        "   Message ID: #{result[:message_id]}\n" \
        "   Thread ID: #{result[:thread_id]}"
      else
        raise "Failed to send reply"
      end
    end

    def mark_as_read(arguments)
      unless arguments["email_id"]
        raise "Missing required argument: email_id"
      end

      tool = Service.new
      result = tool.mark_as_read(arguments["email_id"])

      if result[:success]
        "✅ Email marked as read"
      else
        raise "Failed to mark email as read"
      end
    end

    def mark_as_unread(arguments)
      unless arguments["email_id"]
        raise "Missing required argument: email_id"
      end

      tool = Service.new
      result = tool.mark_as_unread(arguments["email_id"])

      if result[:success]
        "✅ Email marked as unread"
      else
        raise "Failed to mark email as unread"
      end
    end

    def add_label(arguments)
      required_args = ["email_id", "label"]
      missing_args = required_args.select { |arg| arguments[arg].nil? || arguments[arg].empty? }
      unless missing_args.empty?
        raise "Missing required arguments: #{missing_args.join(", ")}"
      end

      tool = Service.new
      result = tool.add_label(arguments["email_id"], arguments["label"])

      if result[:success]
        "✅ Label '#{arguments["label"]}' added to email"
      else
        raise "Failed to add label to email"
      end
    end

    def remove_label(arguments)
      required_args = ["email_id", "label"]
      missing_args = required_args.select { |arg| arguments[arg].nil? || arguments[arg].empty? }
      unless missing_args.empty?
        raise "Missing required arguments: #{missing_args.join(", ")}"
      end

      tool = Service.new
      result = tool.remove_label(arguments["email_id"], arguments["label"])

      if result[:success]
        "✅ Label '#{arguments["label"]}' removed from email"
      else
        raise "Failed to remove label from email"
      end
    end

    def archive_email(arguments)
      unless arguments["email_id"]
        raise "Missing required argument: email_id"
      end

      tool = Service.new
      result = tool.archive_email(arguments["email_id"])

      if result[:success]
        "✅ Email archived"
      else
        raise "Failed to archive email"
      end
    end

    def trash_email(arguments)
      unless arguments["email_id"]
        raise "Missing required argument: email_id"
      end

      tool = Service.new
      result = tool.trash_email(arguments["email_id"])

      if result[:success]
        "✅ Email moved to trash"
      else
        raise "Failed to move email to trash"
      end
    end
  end
end

if __FILE__ == $0
  Gmail::MCPServer.new.run
end
