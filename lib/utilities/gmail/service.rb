# frozen_string_literal: true

require "bundler/setup"
require "google/apis/gmail_v1"
require "googleauth"
require "signet/oauth_2/client"
require "fileutils"
require "json"
require "time"
require "mail"
require "html2text"
require_relative "../_google/auth_server"
require_relative "../../mcpeasy/config"

module Gmail
  class Service
    SCOPES = [
      "https://www.googleapis.com/auth/gmail.readonly",
      "https://www.googleapis.com/auth/gmail.send",
      "https://www.googleapis.com/auth/gmail.modify"
    ]
    SCOPE = SCOPES.join(" ")

    def initialize(skip_auth: false)
      ensure_env!
      @service = Google::Apis::GmailV1::GmailService.new
      @service.authorization = authorize unless skip_auth
    end

    def list_emails(start_date: nil, end_date: nil, max_results: 20, sender: nil, subject: nil, labels: nil, read_status: nil)
      query_parts = []

      # Date filtering
      if start_date
        query_parts << "after:#{start_date}"
      end
      if end_date
        query_parts << "before:#{end_date}"
      end

      # Sender filtering
      if sender
        query_parts << "from:#{sender}"
      end

      # Subject filtering
      if subject
        query_parts << "subject:\"#{subject}\""
      end

      # Labels filtering
      if labels && !labels.empty?
        if labels.is_a?(Array)
          labels.each { |label| query_parts << "label:#{label}" }
        else
          query_parts << "label:#{labels}"
        end
      end

      # Read/unread status
      case read_status&.downcase
      when "unread"
        query_parts << "is:unread"
      when "read"
        query_parts << "is:read"
      end

      query = query_parts.join(" ")

      results = @service.list_user_messages(
        "me",
        q: query.empty? ? nil : query,
        max_results: max_results
      )

      emails = (results.messages || []).map do |message|
        get_email_summary(message.id)
      end.compact

      {emails: emails, count: emails.length}
    rescue Google::Apis::Error => e
      raise "Gmail API Error: #{e.message}"
    rescue => e
      log_error("list_emails", e)
      raise e
    end

    def search_emails(query, max_results: 10)
      results = @service.list_user_messages(
        "me",
        q: query,
        max_results: max_results
      )

      emails = (results.messages || []).map do |message|
        get_email_summary(message.id)
      end.compact

      {emails: emails, count: emails.length}
    rescue Google::Apis::Error => e
      raise "Gmail API Error: #{e.message}"
    rescue => e
      log_error("search_emails", e)
      raise e
    end

    def get_email_content(email_id)
      message = @service.get_user_message("me", email_id)

      # Extract email metadata
      headers = extract_headers(message.payload)

      # Extract email body
      body_data = extract_body(message.payload)

      {
        id: message.id,
        thread_id: message.thread_id,
        subject: headers["Subject"],
        from: headers["From"],
        to: headers["To"],
        cc: headers["Cc"],
        bcc: headers["Bcc"],
        date: headers["Date"],
        body: body_data[:text],
        body_html: body_data[:html],
        snippet: message.snippet,
        labels: message.label_ids || [],
        attachments: extract_attachments(message.payload)
      }
    rescue Google::Apis::Error => e
      raise "Gmail API Error: #{e.message}"
    rescue => e
      log_error("get_email_content", e)
      raise e
    end

    def send_email(to:, subject:, body:, cc: nil, bcc: nil, reply_to: nil)
      mail = Mail.new do
        to to
        cc cc if cc
        bcc bcc if bcc
        subject subject
        body body
        reply_to reply_to if reply_to
      end

      raw_message = mail.to_s
      encoded_message = Base64.urlsafe_encode64(raw_message)

      message_object = Google::Apis::GmailV1::Message.new(raw: encoded_message)
      result = @service.send_user_message("me", message_object)

      {
        success: true,
        message_id: result.id,
        thread_id: result.thread_id
      }
    rescue Google::Apis::Error => e
      raise "Gmail API Error: #{e.message}"
    rescue => e
      log_error("send_email", e)
      raise e
    end

    def reply_to_email(email_id:, body:, include_quoted: true)
      # Get the original message to extract reply information
      original = @service.get_user_message("me", email_id)
      headers = extract_headers(original.payload)

      # Build reply headers
      original_subject = headers["Subject"] || ""
      reply_subject = original_subject.start_with?("Re:") ? original_subject : "Re: #{original_subject}"

      reply_to = headers["Reply-To"] || headers["From"]
      message_id = headers["Message-ID"]

      # Prepare reply body
      reply_body = body
      if include_quoted
        original_body = extract_body(original.payload)[:text]
        date_str = headers["Date"]
        from_str = headers["From"]

        reply_body += "\n\n"
        reply_body += "On #{date_str}, #{from_str} wrote:\n"
        reply_body += original_body.split("\n").map { |line| "> #{line}" }.join("\n")
      end

      mail = Mail.new do
        to reply_to
        subject reply_subject
        body reply_body
        in_reply_to message_id if message_id
        references message_id if message_id
      end

      raw_message = mail.to_s
      encoded_message = Base64.urlsafe_encode64(raw_message)

      message_object = Google::Apis::GmailV1::Message.new(
        raw: encoded_message,
        thread_id: original.thread_id
      )

      result = @service.send_user_message("me", message_object)

      {
        success: true,
        message_id: result.id,
        thread_id: result.thread_id
      }
    rescue Google::Apis::Error => e
      raise "Gmail API Error: #{e.message}"
    rescue => e
      log_error("reply_to_email", e)
      raise e
    end

    def mark_as_read(email_id)
      modify_message(email_id, remove_label_ids: ["UNREAD"])
    end

    def mark_as_unread(email_id)
      modify_message(email_id, add_label_ids: ["UNREAD"])
    end

    def add_label(email_id, label)
      label_id = resolve_label_id(label)
      modify_message(email_id, add_label_ids: [label_id])
    end

    def remove_label(email_id, label)
      label_id = resolve_label_id(label)
      modify_message(email_id, remove_label_ids: [label_id])
    end

    def archive_email(email_id)
      modify_message(email_id, remove_label_ids: ["INBOX"])
    end

    def trash_email(email_id)
      @service.trash_user_message("me", email_id)
      {success: true}
    rescue Google::Apis::Error => e
      raise "Gmail API Error: #{e.message}"
    rescue => e
      log_error("trash_email", e)
      raise e
    end

    def test_connection
      profile = @service.get_user_profile("me")
      {
        ok: true,
        email: profile.email_address,
        messages_total: profile.messages_total,
        threads_total: profile.threads_total
      }
    rescue Google::Apis::Error => e
      raise "Gmail API Error: #{e.message}"
    rescue => e
      log_error("test_connection", e)
      raise e
    end

    def authenticate
      perform_auth_flow
      {success: true}
    rescue => e
      {success: false, error: e.message}
    end

    def perform_auth_flow
      client_id = Mcpeasy::Config.google_client_id
      client_secret = Mcpeasy::Config.google_client_secret

      unless client_id && client_secret
        raise "Google credentials not found. Please save your credentials.json file using: mcpz config set_google_credentials <path_to_credentials.json>"
      end

      # Create credentials using OAuth2 flow with localhost redirect
      redirect_uri = "http://localhost:8080"
      client = Signet::OAuth2::Client.new(
        client_id: client_id,
        client_secret: client_secret,
        scope: SCOPE,
        redirect_uri: redirect_uri,
        authorization_uri: "https://accounts.google.com/o/oauth2/auth",
        token_credential_uri: "https://oauth2.googleapis.com/token"
      )

      # Generate authorization URL
      url = client.authorization_uri.to_s

      puts "DEBUG: Client ID: #{client_id[0..20]}..."
      puts "DEBUG: Scope: #{SCOPE}"
      puts "DEBUG: Redirect URI: #{redirect_uri}"
      puts

      # Start callback server to capture OAuth code
      puts "Starting temporary web server to capture OAuth callback..."
      puts "Opening authorization URL in your default browser..."
      puts url
      puts

      # Automatically open URL in default browser on macOS/Unix
      if system("which open > /dev/null 2>&1")
        system("open", url)
      else
        puts "Could not automatically open browser. Please copy the URL above manually."
      end
      puts
      puts "Waiting for OAuth callback... (will timeout in 60 seconds)"

      # Wait for the authorization code with timeout
      code = GoogleAuthServer.capture_auth_code

      unless code
        raise "Failed to receive authorization code. Please try again."
      end

      puts "✅ Authorization code received!"
      client.code = code
      client.fetch_access_token!

      # Save credentials to config
      credentials_data = {
        client_id: client.client_id,
        client_secret: client.client_secret,
        scope: client.scope,
        refresh_token: client.refresh_token,
        access_token: client.access_token,
        expires_at: client.expires_at
      }

      Mcpeasy::Config.save_google_token(credentials_data)
      puts "✅ Authentication successful! Token saved to config"

      client
    rescue => e
      log_error("perform_auth_flow", e)
      raise "Authentication flow failed: #{e.message}"
    end

    private

    def authorize
      credentials_data = Mcpeasy::Config.google_token
      unless credentials_data
        raise <<~ERROR
          Gmail authentication required!
          Run the auth command first:
          mcpz gmail auth
        ERROR
      end

      client = Signet::OAuth2::Client.new(
        client_id: credentials_data.client_id,
        client_secret: credentials_data.client_secret,
        scope: credentials_data.scope.respond_to?(:to_a) ? credentials_data.scope.to_a.join(" ") : credentials_data.scope.to_s,
        refresh_token: credentials_data.refresh_token,
        access_token: credentials_data.access_token,
        token_credential_uri: "https://oauth2.googleapis.com/token"
      )

      # Check if token needs refresh
      if credentials_data.expires_at
        expires_at = if credentials_data.expires_at.is_a?(String)
          Time.parse(credentials_data.expires_at)
        else
          Time.at(credentials_data.expires_at)
        end

        if Time.now >= expires_at
          client.refresh!
          # Update saved credentials with new access token
          updated_data = {
            client_id: credentials_data.client_id,
            client_secret: credentials_data.client_secret,
            scope: credentials_data.scope.respond_to?(:to_a) ? credentials_data.scope.to_a.join(" ") : credentials_data.scope.to_s,
            refresh_token: credentials_data.refresh_token,
            access_token: client.access_token,
            expires_at: client.expires_at
          }
          Mcpeasy::Config.save_google_token(updated_data)
        end
      end

      client
    rescue JSON::ParserError
      raise "Invalid token data. Please re-run: mcpz gmail auth"
    rescue => e
      log_error("authorize", e)
      raise "Authentication failed: #{e.message}"
    end

    def ensure_env!
      unless Mcpeasy::Config.google_client_id && Mcpeasy::Config.google_client_secret
        raise <<~ERROR
          Google API credentials not configured!
          Please save your Google credentials.json file using:
          mcpz config set_google_credentials <path_to_credentials.json>
        ERROR
      end
    end

    def get_email_summary(message_id)
      message = @service.get_user_message("me", message_id, format: "metadata")
      headers = extract_headers(message.payload)

      {
        id: message.id,
        thread_id: message.thread_id,
        subject: headers["Subject"],
        from: headers["From"],
        date: headers["Date"],
        snippet: message.snippet,
        labels: message.label_ids || []
      }
    rescue => e
      log_error("get_email_summary", e)
      nil
    end

    def extract_headers(payload)
      headers = {}
      (payload.headers || []).each do |header|
        headers[header.name] = header.value
      end
      headers
    end

    def extract_body(payload)
      body_data = {text: "", html: ""}

      if payload.body&.data
        # Simple message body
        decoded_body = Base64.urlsafe_decode64(payload.body.data)
        if payload.mime_type == "text/html"
          body_data[:html] = decoded_body
          body_data[:text] = Html2Text.convert(decoded_body)
        else
          body_data[:text] = decoded_body
        end
      elsif payload.parts
        # Multipart message
        extract_body_from_parts(payload.parts, body_data)
      end

      body_data
    end

    def extract_body_from_parts(parts, body_data)
      parts.each do |part|
        if part.mime_type == "text/plain" && part.body&.data
          body_data[:text] += Base64.urlsafe_decode64(part.body.data)
        elsif part.mime_type == "text/html" && part.body&.data
          html_content = Base64.urlsafe_decode64(part.body.data)
          body_data[:html] += html_content
          # If we don't have plain text yet, convert from HTML
          if body_data[:text].empty?
            body_data[:text] = Html2Text.convert(html_content)
          end
        elsif part.parts
          # Nested multipart
          extract_body_from_parts(part.parts, body_data)
        end
      end
    end

    def extract_attachments(payload)
      attachments = []

      if payload.parts
        extract_attachments_from_parts(payload.parts, attachments)
      end

      attachments
    end

    def extract_attachments_from_parts(parts, attachments)
      parts.each do |part|
        if part.filename && !part.filename.empty?
          attachments << {
            filename: part.filename,
            mime_type: part.mime_type,
            size: part.body&.size,
            attachment_id: part.body&.attachment_id
          }
        elsif part.parts
          extract_attachments_from_parts(part.parts, attachments)
        end
      end
    end

    def modify_message(email_id, add_label_ids: [], remove_label_ids: [])
      request = Google::Apis::GmailV1::ModifyMessageRequest.new(
        add_label_ids: add_label_ids,
        remove_label_ids: remove_label_ids
      )

      @service.modify_message("me", email_id, request)
      {success: true}
    rescue Google::Apis::Error => e
      raise "Gmail API Error: #{e.message}"
    rescue => e
      log_error("modify_message", e)
      raise e
    end

    def resolve_label_id(label)
      # Handle common label names
      case label.upcase
      when "INBOX"
        "INBOX"
      when "SENT"
        "SENT"
      when "DRAFT"
        "DRAFT"
      when "SPAM"
        "SPAM"
      when "TRASH"
        "TRASH"
      when "UNREAD"
        "UNREAD"
      when "STARRED"
        "STARRED"
      when "IMPORTANT"
        "IMPORTANT"
      else
        # For custom labels, we'd need to fetch the labels list
        # For now, return the label as-is and let the API handle it
        label
      end
    end

    def log_error(method, error)
      Mcpeasy::Config.ensure_config_dirs
      File.write(
        Mcpeasy::Config.log_file_path("gmail", "error"),
        "#{Time.now}: #{method} error: #{error.class}: #{error.message}\n#{error.backtrace.join("\n")}\n",
        mode: "a"
      )
    end
  end
end
