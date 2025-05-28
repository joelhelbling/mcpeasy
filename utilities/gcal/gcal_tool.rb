# frozen_string_literal: true

require "bundler/setup"
require "google/apis/calendar_v3"
require "googleauth"
require "signet/oauth_2/client"
require "fileutils"
require "json"
require "time"
require "dotenv/load"
require "webrick"
require "timeout"

class GcalTool
  SCOPE = "https://www.googleapis.com/auth/calendar.readonly"
  TOKEN_PATH = ".gcal-token.json"

  def initialize(skip_auth: false)
    ensure_env!
    @service = Google::Apis::CalendarV3::CalendarService.new
    @service.authorization = authorize unless skip_auth
  end

  def list_events(start_date: nil, end_date: nil, max_results: 20, calendar_id: "primary")
    # Default to today if no start date provided
    start_time = start_date ? Time.parse("#{start_date} 00:00:00") : Time.now.beginning_of_day
    # Default to 7 days from start if no end date provided
    end_time = end_date ? Time.parse("#{end_date} 23:59:59") : start_time + 7 * 24 * 60 * 60

    results = @service.list_events(
      calendar_id,
      max_results: max_results,
      single_events: true,
      order_by: "startTime",
      time_min: start_time.utc.iso8601,
      time_max: end_time.utc.iso8601
    )

    events = results.items.map do |event|
      {
        id: event.id,
        summary: event.summary,
        description: event.description,
        location: event.location,
        start: format_event_time(event.start),
        end: format_event_time(event.end),
        attendees: format_attendees(event.attendees),
        html_link: event.html_link,
        calendar_id: calendar_id
      }
    end

    {events: events, count: events.length}
  rescue Google::Apis::Error => e
    raise "Google Calendar API Error: #{e.message}"
  rescue => e
    log_error("list_events", e)
    raise e
  end

  def list_calendars
    results = @service.list_calendar_lists

    calendars = results.items.map do |calendar|
      {
        id: calendar.id,
        summary: calendar.summary,
        description: calendar.description,
        time_zone: calendar.time_zone,
        access_role: calendar.access_role,
        primary: calendar.primary
      }
    end

    {calendars: calendars, count: calendars.length}
  rescue Google::Apis::Error => e
    raise "Google Calendar API Error: #{e.message}"
  rescue => e
    log_error("list_calendars", e)
    raise e
  end

  def search_events(query, start_date: nil, end_date: nil, max_results: 10)
    # Default to today if no start date provided
    start_time = start_date ? Time.parse("#{start_date} 00:00:00") : Time.now.beginning_of_day
    # Default to 30 days from start if no end date provided
    end_time = end_date ? Time.parse("#{end_date} 23:59:59") : start_time + 30 * 24 * 60 * 60

    results = @service.list_events(
      "primary",
      q: query,
      max_results: max_results,
      single_events: true,
      order_by: "startTime",
      time_min: start_time.utc.iso8601,
      time_max: end_time.utc.iso8601
    )

    events = results.items.map do |event|
      {
        id: event.id,
        summary: event.summary,
        description: event.description,
        location: event.location,
        start: format_event_time(event.start),
        end: format_event_time(event.end),
        attendees: format_attendees(event.attendees),
        html_link: event.html_link,
        calendar_id: "primary"
      }
    end

    {events: events, count: events.length}
  rescue Google::Apis::Error => e
    raise "Google Calendar API Error: #{e.message}"
  rescue => e
    log_error("search_events", e)
    raise e
  end

  def test_connection
    calendar = @service.get_calendar("primary")
    {
      ok: true,
      user: calendar.summary,
      email: calendar.id
    }
  rescue Google::Apis::Error => e
    raise "Google Calendar API Error: #{e.message}"
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
        Google Calendar authentication required!
        Run the CLI with 'auth' command first:
        ruby utilities/gcal/cli.rb auth
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
    raise "Invalid credentials file. Please re-run: ruby utilities/gcal/cli.rb auth"
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

  def format_event_time(event_time)
    return nil unless event_time

    if event_time.date
      # All-day event
      {date: event_time.date}
    elsif event_time.date_time
      # Specific time event
      {date_time: event_time.date_time.iso8601}
    else
      nil
    end
  end

  def format_attendees(attendees)
    return [] unless attendees

    attendees.map do |attendee|
      attendee.email
    end.compact
  end

  def log_error(method, error)
    FileUtils.mkdir_p("./logs")
    File.write(
      "./logs/mcp_gcal_error.log",
      "#{Time.now}: #{method} error: #{error.class}: #{error.message}\n#{error.backtrace.join("\n")}\n",
      mode: "a"
    )
  end
end
