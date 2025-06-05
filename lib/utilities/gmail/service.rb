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

    def get_raw_message(email_id)
      message = @service.get_user_message("me", email_id, format: "full")

      puts "📧 Raw Message Structure:"
      puts "Message ID: #{message.id}"
      puts "Payload MIME Type: #{message.payload.mime_type}"

      print_parts_recursive(message.payload)
    end

    def print_parts_recursive(payload, indent = 0)
      prefix = "  " * indent
      puts "#{prefix}MIME Type: #{payload.mime_type}"
      puts "#{prefix}Has body data: #{!payload.body.nil? && !payload.body.data.nil?}"
      if payload.body&.data
        begin
          decoded = decode_body_data(payload.body.data)
          puts "#{prefix}Body preview (first 100 chars): #{decoded[0..100].inspect}"
          puts "#{prefix}Body bytes (first 20): #{decoded.bytes.first(20).inspect}"
        rescue
          puts "#{prefix}Failed to decode body data"
        end
      end

      if payload.headers
        content_headers = payload.headers.select { |h| h.name.downcase.include?("content") }
        content_headers.each do |header|
          puts "#{prefix}Header: #{header.name} = #{header.value}"
        end
      end

      if payload.parts
        puts "#{prefix}Parts: #{payload.parts.size}"
        payload.parts.each_with_index do |part, i|
          puts "#{prefix}Part #{i + 1}:"
          print_parts_recursive(part, indent + 1)
        end
      end
    end

    def get_email_content(email_id)
      # Try to get the message in 'metadata' format first to see if it helps
      message = @service.get_user_message("me", email_id, format: "full")

      # Extract email metadata
      headers = extract_headers(message.payload)

      # Extract email body
      body_data = extract_body(message.payload)

      # If body is still corrupted, fall back to snippet
      if body_data[:text].empty? || body_data[:text].start_with?("[Encrypted") || !body_data[:text].valid_encoding?
        body_data[:text] = message.snippet || "[Unable to decode message body]"
        body_data[:html] = ""
      end

      # Debug: Check for content encoding
      content_encoding = headers["Content-Encoding"]
      if content_encoding
        require "zlib"
        require "stringio"

        if content_encoding.downcase == "gzip"
          body_data[:text] = decompress_gzip(body_data[:text]) if body_data[:text] && !body_data[:text].empty?
          body_data[:html] = decompress_gzip(body_data[:html]) if body_data[:html] && !body_data[:html].empty?
        elsif content_encoding.downcase == "deflate"
          body_data[:text] = Zlib::Inflate.inflate(body_data[:text]) if body_data[:text] && !body_data[:text].empty?
          body_data[:html] = Zlib::Inflate.inflate(body_data[:html]) if body_data[:html] && !body_data[:html].empty?
        end
      end

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
        attachments: extract_attachments(message.payload),
        debug_info: {
          content_type: headers["Content-Type"],
          content_encoding: headers["Content-Encoding"],
          content_transfer_encoding: headers["Content-Transfer-Encoding"]
        }
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

      # Check if this is an S/MIME encrypted message
      if payload.mime_type&.include?("pkcs7-mime") || payload.mime_type&.include?("pkcs7-signature")
        body_data[:text] = "[S/MIME encrypted or signed message - decryption not supported]"
        return body_data
      end

      if payload.body&.data
        # Simple message body
        decoded_body = decode_body_data(payload.body.data)
        if payload.mime_type == "text/html"
          body_data[:html] = decoded_body
          body_data[:text] = Html2Text.convert(decoded_body)
        elsif payload.mime_type == "text/plain"
          body_data[:text] = decoded_body
        else
          # Unknown mime type with body data - might be encrypted
          body_data[:text] = if decoded_body.bytes.first(2) == [0x30, 0x82] || decoded_body.bytes.first == 0x30
            "[Encrypted or signed message - ASN.1/DER format detected]"
          else
            decoded_body
          end
        end
      elsif payload.parts
        # Multipart message
        extract_body_from_parts(payload.parts, body_data)
      end

      body_data
    end

    def extract_body_from_parts(parts, body_data)
      parts.each do |part|
        # Check for S/MIME parts
        if part.mime_type&.include?("pkcs7")
          next # Skip S/MIME parts
        end

        # Check for content-transfer-encoding header in part headers
        part_headers = {}
        (part.headers || []).each do |header|
          part_headers[header.name] = header.value
        end

        if part.mime_type == "text/plain" && part.body&.data
          decoded_content = decode_body_data(part.body.data)
          # Check if we need additional decoding
          decoded_content = handle_content_encoding(decoded_content, part_headers)
          # Check if it's actually encrypted content
          if decoded_content.bytes.first(2) == [0x30, 0x82] || decoded_content.bytes.first == 0x30
            body_data[:text] = "[Encrypted content detected in text/plain part]" if body_data[:text].empty?
          else
            body_data[:text] += decoded_content
          end
        elsif part.mime_type == "text/html" && part.body&.data
          html_content = decode_body_data(part.body.data)
          # Check if we need additional decoding
          html_content = handle_content_encoding(html_content, part_headers)
          body_data[:html] += html_content
          # If we don't have plain text yet, convert from HTML
          if body_data[:text].empty? || body_data[:text].start_with?("[Encrypted")
            body_data[:text] = Html2Text.convert(html_content)
          end
        elsif part.mime_type == "multipart/alternative" && part.parts
          # For multipart/alternative, prefer text/plain but fall back to text/html
          text_part = part.parts.find { |p| p.mime_type == "text/plain" }
          html_part = part.parts.find { |p| p.mime_type == "text/html" }

          if text_part
            extract_body_from_parts([text_part], body_data)
          elsif html_part
            extract_body_from_parts([html_part], body_data)
          else
            extract_body_from_parts(part.parts, body_data)
          end
        elsif part.parts
          # Other nested multipart types
          extract_body_from_parts(part.parts, body_data)
        end
      end
    end

    def handle_content_encoding(data, headers)
      return data if data.nil? || data.empty?

      # Check for content-transfer-encoding first (this affects the base64 decoded data)
      content_transfer_encoding = headers["Content-Transfer-Encoding"]
      if content_transfer_encoding
        begin
          case content_transfer_encoding.downcase
          when "quoted-printable"
            # Decode quoted-printable encoding
            data = data.unpack1("M*")
          when "base64"
            # Additional base64 decoding (though this should already be handled)
            data = Base64.decode64(data)
          end
        rescue => e
          # If decoding fails, continue with original data
          puts "Warning: Failed to decode content-transfer-encoding #{content_transfer_encoding}: #{e.message}" if $DEBUG
        end
      end

      # Check for content encoding (compression)
      content_encoding = headers["Content-Encoding"]
      if content_encoding
        require "zlib"
        require "stringio"

        begin
          case content_encoding.downcase
          when "gzip"
            data = decompress_gzip(data)
          when "deflate"
            data = Zlib::Inflate.inflate(data)
          end
        rescue
          # If decompression fails, continue with original data
        end
      end

      # Check character encoding - Gmail often uses UTF-8 but sometimes other encodings
      charset = nil
      if headers["Content-Type"]
        charset_match = headers["Content-Type"].match(/charset=["']?([^"';\s]+)/i)
        charset = charset_match[1] if charset_match
      end

      if charset && charset.downcase != "utf-8"
        begin
          # Force encoding to the specified charset, then convert to UTF-8
          data = data.force_encoding(charset).encode("UTF-8", invalid: :replace, undef: :replace)
        rescue
          # If encoding conversion fails, try to force UTF-8
          data = data.force_encoding("UTF-8")
        end
      elsif data.encoding != Encoding::UTF_8
        # Ensure UTF-8 encoding
        data = data.force_encoding("UTF-8")
      end

      data
    end

    def decompress_gzip(data)
      StringIO.open(data) do |io|
        gz = Zlib::GzipReader.new(io)
        gz.read
      end
    rescue
      # If decompression fails, return original data
      data
    end

    def decode_body_data(data)
      # Gmail sometimes returns base64 data without proper padding
      # Add padding if necessary
      padded_data = data
      mod = data.length % 4
      if mod > 0
        padded_data += "=" * (4 - mod)
      end
      decoded = Base64.urlsafe_decode64(padded_data)

      # Check if the decoded data is gzip compressed
      # Gzip magic number is 1f 8b
      if decoded.bytes.first(2) == [0x1f, 0x8b]
        require "zlib"
        require "stringio"
        decoded = decompress_gzip(decoded)
      end

      decoded
    rescue ArgumentError
      # If it still fails, try replacing URL-safe characters and decode as standard base64
      standard_data = data.tr("-_", "+/")
      mod = standard_data.length % 4
      if mod > 0
        standard_data += "=" * (4 - mod)
      end
      decoded = Base64.decode64(standard_data)

      # Check if the decoded data is gzip compressed
      if decoded.bytes.first(2) == [0x1f, 0x8b]
        require "zlib"
        require "stringio"
        decoded = decompress_gzip(decoded)
      end

      decoded
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
