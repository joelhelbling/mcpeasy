# frozen_string_literal: true

require "bundler/setup"
require "google/apis/calendar_v3"
require "googleauth"
require "signet/oauth_2/client"
require "fileutils"
require "json"
require "time"
require_relative "../_google/auth_server"
require_relative "../../mcpeasy/config"

module Gcal
  class Service
    SCOPES = [
      "https://www.googleapis.com/auth/calendar.readonly",
      "https://www.googleapis.com/auth/drive.readonly"
    ]
    SCOPE = SCOPES.join(" ")

    def initialize(skip_auth: false)
      ensure_env!
      @service = Google::Apis::CalendarV3::CalendarService.new
      @service.authorization = authorize unless skip_auth
    end

    def list_events(start_date: nil, end_date: nil, max_results: 20, calendar_id: "primary")
      # Default to today if no start date provided
      now = Time.now
      start_time = start_date ? Time.parse("#{start_date} 00:00:00") : Time.new(now.year, now.month, now.day, 0, 0, 0)
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
      now = Time.now
      start_time = start_date ? Time.parse("#{start_date} 00:00:00") : Time.new(now.year, now.month, now.day, 0, 0, 0)
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
          Google Calendar authentication required!
          Run the auth command first:
          mcpz gcal auth
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
      raise "Invalid token data. Please re-run: mcpz gcal auth"
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
      Mcpeasy::Config.ensure_config_dirs
      File.write(
        Mcpeasy::Config.log_file_path("gcal", "error"),
        "#{Time.now}: #{method} error: #{error.class}: #{error.message}\n#{error.backtrace.join("\n")}\n",
        mode: "a"
      )
    end
  end
end
