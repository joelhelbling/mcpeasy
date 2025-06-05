# frozen_string_literal: true

require "bundler/setup"
require "thor"
require_relative "service"

module Gmail
  class CLI < Thor
    desc "test", "Test the Gmail API connection"
    def test
      response = tool.test_connection

      if response[:ok]
        puts "✅ Successfully connected to Gmail"
        puts "   Email: #{response[:email]}"
        puts "   Messages: #{response[:messages_total]}"
        puts "   Threads: #{response[:threads_total]}"
      else
        warn "❌ Connection test failed"
      end
    rescue RuntimeError => e
      puts "❌ Failed to connect to Gmail: #{e.message}\n\n#{e.backtrace.join("\n")}"
      exit 1
    end

    desc "list", "List recent emails"
    method_option :start_date, type: :string, aliases: "-s", desc: "Start date (YYYY-MM-DD)"
    method_option :end_date, type: :string, aliases: "-e", desc: "End date (YYYY-MM-DD)"
    method_option :max_results, type: :numeric, default: 20, aliases: "-n", desc: "Max number of emails"
    method_option :sender, type: :string, aliases: "-f", desc: "Filter by sender email"
    method_option :subject, type: :string, aliases: "-j", desc: "Filter by subject"
    method_option :labels, type: :string, aliases: "-l", desc: "Filter by labels (comma-separated)"
    method_option :read_status, type: :string, aliases: "-r", desc: "Filter by read status (read/unread)"
    def list
      labels = options[:labels]&.split(",")&.map(&:strip)

      result = tool.list_emails(
        start_date: options[:start_date],
        end_date: options[:end_date],
        max_results: options[:max_results],
        sender: options[:sender],
        subject: options[:subject],
        labels: labels,
        read_status: options[:read_status]
      )
      emails = result[:emails]

      if emails.empty?
        puts "📧 No emails found for the specified criteria"
      else
        puts "📧 Found #{result[:count]} email(s):"
        emails.each_with_index do |email, index|
          puts "   #{index + 1}. #{email[:subject] || "No subject"}"
          puts "      From: #{email[:from]}"
          puts "      Date: #{email[:date]}"
          puts "      Snippet: #{email[:snippet]}" if email[:snippet]
          puts "      Labels: #{email[:labels].join(", ")}" if email[:labels]&.any?
          puts "      ID: #{email[:id]}"
          puts
        end
      end
    rescue RuntimeError => e
      warn "❌ Failed to list emails: #{e.message}"
      exit 1
    end

    desc "search QUERY", "Search emails by text content"
    method_option :max_results, type: :numeric, default: 10, aliases: "-n", desc: "Max number of emails"
    def search(query)
      result = tool.search_emails(
        query,
        max_results: options[:max_results]
      )
      emails = result[:emails]

      if emails.empty?
        puts "🔍 No emails found matching '#{query}'"
      else
        puts "🔍 Found #{result[:count]} email(s) matching '#{query}':"
        emails.each_with_index do |email, index|
          puts "   #{index + 1}. #{email[:subject] || "No subject"}"
          puts "      From: #{email[:from]}"
          puts "      Date: #{email[:date]}"
          puts "      Snippet: #{email[:snippet]}" if email[:snippet]
          puts "      ID: #{email[:id]}"
          puts
        end
      end
    rescue RuntimeError => e
      warn "❌ Failed to search emails: #{e.message}"
      exit 1
    end

    desc "read EMAIL_ID", "Read a specific email"
    option :debug, type: :boolean, desc: "Show debug information"
    option :raw, type: :boolean, desc: "Show raw message structure"
    def read(email_id)
      if options[:raw]
        email = tool.get_raw_message(email_id)
        return
      end
      
      email = tool.get_email_content(email_id)

      puts "📧 Email Details:"
      puts "   ID: #{email[:id]}"
      puts "   Thread ID: #{email[:thread_id]}"
      puts "   Subject: #{email[:subject] || "No subject"}"
      puts "   From: #{email[:from]}"
      puts "   To: #{email[:to]}"
      puts "   CC: #{email[:cc]}" if email[:cc]
      puts "   BCC: #{email[:bcc]}" if email[:bcc]
      puts "   Date: #{email[:date]}"
      puts "   Labels: #{email[:labels].join(", ")}" if email[:labels]&.any?

      if email[:attachments]&.any?
        puts "   Attachments:"
        email[:attachments].each do |attachment|
          puts "      - #{attachment[:filename]} (#{attachment[:mime_type]}, #{attachment[:size]} bytes)"
        end
      end

      puts "\n📄 Body:"
      if options[:debug] && email[:body]
        puts "Debug: Body encoding: #{email[:body].encoding}"
        puts "Debug: Body bytes (first 100): #{email[:body].bytes.first(100).inspect}"
        puts "Debug: Is valid UTF-8? #{email[:body].valid_encoding?}"
        puts "Debug: Snippet: #{email[:snippet]}" if email[:snippet]
        if email[:debug_info]
          puts "Debug: Content-Type: #{email[:debug_info][:content_type]}"
          puts "Debug: Content-Encoding: #{email[:debug_info][:content_encoding]}"
          puts "Debug: Content-Transfer-Encoding: #{email[:debug_info][:content_transfer_encoding]}"
        end
      end
      puts email[:body]
    rescue RuntimeError => e
      warn "❌ Failed to read email: #{e.message}"
      exit 1
    end

    desc "send", "Send a new email"
    method_option :to, type: :string, required: true, aliases: "-t", desc: "Recipient email address"
    method_option :subject, type: :string, required: true, aliases: "-s", desc: "Email subject"
    method_option :body, type: :string, required: true, aliases: "-b", desc: "Email body"
    method_option :cc, type: :string, aliases: "-c", desc: "CC email address"
    method_option :bcc, type: :string, aliases: "-B", desc: "BCC email address"
    method_option :reply_to, type: :string, aliases: "-r", desc: "Reply-to email address"
    def send
      result = tool.send_email(
        to: options[:to],
        subject: options[:subject],
        body: options[:body],
        cc: options[:cc],
        bcc: options[:bcc],
        reply_to: options[:reply_to]
      )

      if result[:success]
        puts "✅ Email sent successfully"
        puts "   Message ID: #{result[:message_id]}"
        puts "   Thread ID: #{result[:thread_id]}"
      else
        puts "❌ Failed to send email"
      end
    rescue RuntimeError => e
      warn "❌ Failed to send email: #{e.message}"
      exit 1
    end

    desc "reply EMAIL_ID", "Reply to an email"
    method_option :body, type: :string, required: true, aliases: "-b", desc: "Reply body"
    method_option :include_quoted, type: :boolean, default: true, aliases: "-q", desc: "Include quoted original message"
    def reply(email_id)
      result = tool.reply_to_email(
        email_id: email_id,
        body: options[:body],
        include_quoted: options[:include_quoted]
      )

      if result[:success]
        puts "✅ Reply sent successfully"
        puts "   Message ID: #{result[:message_id]}"
        puts "   Thread ID: #{result[:thread_id]}"
      else
        puts "❌ Failed to send reply"
      end
    rescue RuntimeError => e
      warn "❌ Failed to send reply: #{e.message}"
      exit 1
    end

    desc "mark_read EMAIL_ID", "Mark an email as read"
    def mark_read(email_id)
      result = tool.mark_as_read(email_id)

      if result[:success]
        puts "✅ Email marked as read"
      else
        puts "❌ Failed to mark email as read"
      end
    rescue RuntimeError => e
      warn "❌ Failed to mark email as read: #{e.message}"
      exit 1
    end

    desc "mark_unread EMAIL_ID", "Mark an email as unread"
    def mark_unread(email_id)
      result = tool.mark_as_unread(email_id)

      if result[:success]
        puts "✅ Email marked as unread"
      else
        puts "❌ Failed to mark email as unread"
      end
    rescue RuntimeError => e
      warn "❌ Failed to mark email as unread: #{e.message}"
      exit 1
    end

    desc "add_label EMAIL_ID LABEL", "Add a label to an email"
    def add_label(email_id, label)
      result = tool.add_label(email_id, label)

      if result[:success]
        puts "✅ Label '#{label}' added to email"
      else
        puts "❌ Failed to add label to email"
      end
    rescue RuntimeError => e
      warn "❌ Failed to add label to email: #{e.message}"
      exit 1
    end

    desc "remove_label EMAIL_ID LABEL", "Remove a label from an email"
    def remove_label(email_id, label)
      result = tool.remove_label(email_id, label)

      if result[:success]
        puts "✅ Label '#{label}' removed from email"
      else
        puts "❌ Failed to remove label from email"
      end
    rescue RuntimeError => e
      warn "❌ Failed to remove label from email: #{e.message}"
      exit 1
    end

    desc "archive EMAIL_ID", "Archive an email"
    def archive(email_id)
      result = tool.archive_email(email_id)

      if result[:success]
        puts "✅ Email archived"
      else
        puts "❌ Failed to archive email"
      end
    rescue RuntimeError => e
      warn "❌ Failed to archive email: #{e.message}"
      exit 1
    end

    desc "trash EMAIL_ID", "Move an email to trash"
    def trash(email_id)
      result = tool.trash_email(email_id)

      if result[:success]
        puts "✅ Email moved to trash"
      else
        puts "❌ Failed to move email to trash"
      end
    rescue RuntimeError => e
      warn "❌ Failed to move email to trash: #{e.message}"
      exit 1
    end

    private

    def tool
      @tool ||= Service.new
    end
  end
end
