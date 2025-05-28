# frozen_string_literal: true

require "bundler/setup"
require "google/apis/drive_v3"
require "googleauth"
require "signet/oauth_2/client"
require "fileutils"
require "json"
require "time"
require "dotenv/load"
require "webrick"
require "timeout"

class GdriveTool
  SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/drive.readonly"
  ]
  SCOPE = SCOPES.join(" ")
  CREDENTIALS_PATH = ".gdrive-credentials.json"
  TOKEN_PATH = ".google-token.json"

  # MIME type mappings for Google Workspace documents
  EXPORT_FORMATS = {
    "application/vnd.google-apps.document" => {
      format: "text/markdown",
      extension: ".md"
    },
    "application/vnd.google-apps.spreadsheet" => {
      format: "text/csv",
      extension: ".csv"
    },
    "application/vnd.google-apps.presentation" => {
      format: "text/plain",
      extension: ".txt"
    },
    "application/vnd.google-apps.drawing" => {
      format: "image/png",
      extension: ".png"
    }
  }.freeze

  def initialize(skip_auth: false)
    ensure_env!
    @service = Google::Apis::DriveV3::DriveService.new
    @service.authorization = authorize unless skip_auth
  end

  def search_files(query, max_results: 10)
    results = @service.list_files(
      q: "fullText contains '#{query.gsub("'", "\\'")}' and trashed=false",
      page_size: max_results,
      fields: "files(id,name,mimeType,size,modifiedTime,webViewLink)"
    )

    files = results.files.map do |file|
      {
        id: file.id,
        name: file.name,
        mime_type: file.mime_type,
        size: file.size&.to_i,
        modified_time: file.modified_time,
        web_view_link: file.web_view_link
      }
    end

    {files: files, count: files.length}
  rescue Google::Apis::Error => e
    raise "Google Drive API Error: #{e.message}"
  rescue => e
    log_error("search_files", e)
    raise e
  end

  def get_file_content(file_id)
    # First get file metadata
    file = @service.get_file(file_id, fields: "id,name,mimeType,size")

    content = if EXPORT_FORMATS.key?(file.mime_type)
      # Export Google Workspace document
      export_format = EXPORT_FORMATS[file.mime_type][:format]
      @service.export_file(file_id, export_format)
    else
      # Download regular file
      @service.get_file(file_id, download_dest: StringIO.new)
    end

    {
      id: file.id,
      name: file.name,
      mime_type: file.mime_type,
      size: file.size&.to_i,
      content: content.is_a?(StringIO) ? content.string : content
    }
  rescue Google::Apis::Error => e
    raise "Google Drive API Error: #{e.message}"
  rescue => e
    log_error("get_file_content", e)
    raise e
  end

  def list_files(max_results: 20)
    results = @service.list_files(
      q: "trashed=false",
      page_size: max_results,
      order_by: "modifiedTime desc",
      fields: "files(id,name,mimeType,size,modifiedTime,webViewLink)"
    )

    files = results.files.map do |file|
      {
        id: file.id,
        name: file.name,
        mime_type: file.mime_type,
        size: file.size&.to_i,
        modified_time: file.modified_time,
        web_view_link: file.web_view_link
      }
    end

    {files: files, count: files.length}
  rescue Google::Apis::Error => e
    raise "Google Drive API Error: #{e.message}"
  rescue => e
    log_error("list_files", e)
    raise e
  end

  def test_connection
    about = @service.get_about(fields: "user,storageQuota")
    {
      ok: true,
      user: about.user.display_name,
      email: about.user.email_address,
      storage_used: about.storage_quota&.usage,
      storage_limit: about.storage_quota&.limit
    }
  rescue Google::Apis::Error => e
    raise "Google Drive API Error: #{e.message}"
  rescue => e
    log_error("test_connection", e)
    raise e
  end

  def perform_auth_flow
    client_id = ENV["GOOGLE_CLIENT_ID"]
    client_secret = ENV["GOOGLE_CLIENT_SECRET"]

    unless client_id && client_secret
      raise "GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET must be set in .env file"
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
    server, server_thread = start_callback_server

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
    code = wait_for_auth_code(server, server_thread)

    unless code
      raise "Failed to receive authorization code. Please try again."
    end

    puts "✅ Authorization code received!"
    client.code = code
    client.fetch_access_token!

    # Save credentials to file
    credentials_data = {
      client_id: client.client_id,
      client_secret: client.client_secret,
      scope: client.scope,
      refresh_token: client.refresh_token,
      access_token: client.access_token,
      expires_at: client.expires_at
    }

    File.write(TOKEN_PATH, JSON.pretty_generate(credentials_data))
    puts "✅ Authentication successful! Credentials saved to #{TOKEN_PATH}"

    client
  rescue => e
    log_error("perform_auth_flow", e)
    raise "Authentication flow failed: #{e.message}"
  end

  private

  def start_callback_server(port = 8080)
    server = WEBrick::HTTPServer.new(
      Port: port,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: [],
      BindAddress: "127.0.0.1"
    )

    # Store the authorization code in an instance variable accessible by the server
    @auth_code = nil
    @auth_received = false

    server.mount_proc("/") do |req, res|
      if req.query["code"]
        @auth_code = req.query["code"]
        @auth_received = true
        res.content_type = "text/html"
        res.body = <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>Authorization Successful</title>
            <style>
              body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
              .success { color: #28a745; }
            </style>
          </head>
          <body>
            <h1 class="success">✅ Authorization Successful!</h1>
            <p>You can now close this window and return to your terminal.</p>
          </body>
          </html>
        HTML

        # Schedule server shutdown after response is sent
        Thread.new do
          sleep 0.5
          server.shutdown
        end
      elsif req.query["error"]
        @auth_received = true
        res.content_type = "text/html"
        res.body = <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>Authorization Failed</title>
            <style>
              body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
              .error { color: #dc3545; }
            </style>
          </head>
          <body>
            <h1 class="error">❌ Authorization Failed</h1>
            <p>Error: #{req.query["error"]}</p>
            <p>Please try again from your terminal.</p>
          </body>
          </html>
        HTML

        Thread.new do
          sleep 0.5
          server.shutdown
        end
      else
        res.content_type = "text/html"
        res.body = <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>Waiting for Authorization</title>
            <style>
              body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
            </style>
          </head>
          <body>
            <h1>Waiting for Authorization...</h1>
            <p>Please complete the authorization process.</p>
          </body>
          </html>
        HTML
      end
    end

    # Start server in background thread
    server_thread = Thread.new do
      server.start
    rescue => e
      puts "Server error: #{e.message}" unless e.message.include?("shutdown")
    end

    # Give server a moment to start
    sleep 0.1

    [server, server_thread]
  rescue => e
    raise "Failed to start callback server: #{e.message}"
  end

  def wait_for_auth_code(server, server_thread, timeout_seconds = 60)
    begin
      Timeout.timeout(timeout_seconds) do
        until @auth_received
          sleep 0.1

          # Check if server thread died unexpectedly
          unless server_thread.alive?
            break
          end
        end
      end
    rescue Timeout::Error
      puts "\n⏰ Timeout waiting for authorization. Please try again."
      return nil
    ensure
      # Ensure server is stopped
      begin
        server&.shutdown
        server_thread&.join(2)
      rescue
        # Ignore shutdown errors
      end
    end

    @auth_code
  end

  def authorize
    unless File.exist?(TOKEN_PATH)
      raise <<~ERROR
        Google Drive authentication required!
        Run the CLI with 'auth' command first:
        ruby utilities/gdrive/cli.rb auth
      ERROR
    end

    # Load saved credentials
    credentials_data = JSON.parse(File.read(TOKEN_PATH))

    client = Signet::OAuth2::Client.new(
      client_id: credentials_data["client_id"],
      client_secret: credentials_data["client_secret"],
      scope: credentials_data["scope"],
      refresh_token: credentials_data["refresh_token"],
      access_token: credentials_data["access_token"]
    )

    # Check if token needs refresh
    if credentials_data["expires_at"]
      expires_at = if credentials_data["expires_at"].is_a?(String)
        Time.parse(credentials_data["expires_at"])
      else
        Time.at(credentials_data["expires_at"])
      end

      if Time.now >= expires_at
        client.refresh!
        # Update saved credentials with new access token
        credentials_data["access_token"] = client.access_token
        credentials_data["expires_at"] = client.expires_at
        File.write(TOKEN_PATH, JSON.pretty_generate(credentials_data))
      end
    end

    client
  rescue JSON::ParserError
    raise "Invalid credentials file. Please re-run: ruby utilities/gdrive/cli.rb auth"
  rescue => e
    log_error("authorize", e)
    raise "Authentication failed: #{e.message}"
  end

  def ensure_env!
    unless ENV["GOOGLE_CLIENT_ID"] && ENV["GOOGLE_CLIENT_SECRET"]
      raise <<~ERROR
        Google API credentials not configured!
        Please set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in your .env file.
        See README.md for setup instructions.
      ERROR
    end
  end

  def log_error(method, error)
    FileUtils.mkdir_p("./logs")
    File.write(
      "./logs/mcp_gdrive_error.log",
      "#{Time.now}: #{method} error: #{error.class}: #{error.message}\n#{error.backtrace.join("\n")}\n",
      mode: "a"
    )
  end
end
