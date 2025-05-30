# frozen_string_literal: true

require "bundler/setup"
require "google/apis/drive_v3"
require "googleauth"
require "signet/oauth_2/client"
require "fileutils"
require "json"
require "time"
require_relative "../_google/auth_server"
require_relative "../../mcpeasy/config"

class GdriveTool
  SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/drive.readonly"
  ]
  SCOPE = SCOPES.join(" ")

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
        Google Drive authentication required!
        Run the auth command first:
        mcpz gdrive auth
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
    raise "Invalid token data. Please re-run: mcpz gdrive auth"
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

  def log_error(method, error)
    Mcpeasy::Config.ensure_config_dirs
    File.write(
      Mcpeasy::Config.log_file_path("gdrive", "error"),
      "#{Time.now}: #{method} error: #{error.class}: #{error.message}\n#{error.backtrace.join("\n")}\n",
      mode: "a"
    )
  end
end
