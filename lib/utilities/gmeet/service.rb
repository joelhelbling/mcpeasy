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

module Gmeet
  class Service
    SCOPE = "https://www.googleapis.com/auth/calendar.readonly"

    def initialize(skip_auth: false)
      ensure_env!
      @service = Google::Apis::CalendarV3::CalendarService.new
      @service.authorization = authorize unless skip_auth
    end

    def list_meetings(start_date: nil, end_date: nil, max_results: 20, calendar_id: "primary")
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

      # Filter for events that have Google Meet links
      meetings = results.items.filter_map do |event|
        meet_link = extract_meet_link(event)
        next unless meet_link

        {
          id: event.id,
          summary: event.summary,
          description: event.description,
          location: event.location,
          start: format_event_time(event.start),
          end: format_event_time(event.end),
          attendees: format_attendees(event.attendees),
          html_link: event.html_link,
          meet_link: meet_link,
          calendar_id: calendar_id
        }
      end

      {meetings: meetings, count: meetings.length}
    rescue Google::Apis::Error => e
      raise "Google Calendar API Error: #{e.message}"
    rescue => e
      log_error("list_meetings", e)
      raise e
    end

    def upcoming_meetings(max_results: 10, calendar_id: "primary")
      # Get meetings starting from now
      start_time = Time.now
      # Look ahead 24 hours by default
      end_time = start_time + 24 * 60 * 60

      results = @service.list_events(
        calendar_id,
        max_results: max_results,
        single_events: true,
        order_by: "startTime",
        time_min: start_time.utc.iso8601,
        time_max: end_time.utc.iso8601
      )

      # Filter for events that have Google Meet links and are upcoming
      meetings = results.items.filter_map do |event|
        meet_link = extract_meet_link(event)
        next unless meet_link

        event_start_time = event.start.date_time&.to_time || (event.start.date ? Time.parse(event.start.date) : nil)
        next unless event_start_time && event_start_time >= start_time

        {
          id: event.id,
          summary: event.summary,
          description: event.description,
          location: event.location,
          start: format_event_time(event.start),
          end: format_event_time(event.end),
          attendees: format_attendees(event.attendees),
          html_link: event.html_link,
          meet_link: meet_link,
          calendar_id: calendar_id,
          time_until_start: time_until_event(event_start_time)
        }
      end

      {meetings: meetings, count: meetings.length}
    rescue Google::Apis::Error => e
      raise "Google Calendar API Error: #{e.message}"
    rescue => e
      log_error("upcoming_meetings", e)
      raise e
    end

    def search_meetings(query, start_date: nil, end_date: nil, max_results: 10)
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

      # Filter for events that have Google Meet links
      meetings = results.items.filter_map do |event|
        meet_link = extract_meet_link(event)
        next unless meet_link

        {
          id: event.id,
          summary: event.summary,
          description: event.description,
          location: event.location,
          start: format_event_time(event.start),
          end: format_event_time(event.end),
          attendees: format_attendees(event.attendees),
          html_link: event.html_link,
          meet_link: meet_link,
          calendar_id: "primary"
        }
      end

      {meetings: meetings, count: meetings.length}
    rescue Google::Apis::Error => e
      raise "Google Calendar API Error: #{e.message}"
    rescue => e
      log_error("search_meetings", e)
      raise e
    end

    def get_meeting_url(event_id, calendar_id: "primary")
      event = @service.get_event(calendar_id, event_id)
      meet_link = extract_meet_link(event)

      unless meet_link
        raise "No Google Meet link found for this event"
      end

      {
        event_id: event_id,
        summary: event.summary,
        meet_link: meet_link,
        start: format_event_time(event.start),
        end: format_event_time(event.end)
      }
    rescue Google::Apis::Error => e
      raise "Google Calendar API Error: #{e.message}"
    rescue => e
      log_error("get_meeting_url", e)
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
          mcpz gmeet auth
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
      raise "Invalid token data. Please re-run: mcpz gmeet auth"
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

    def extract_meet_link(event)
      # Check various places where Google Meet links might be stored

      # 1. Check conference data (most reliable)
      if event.conference_data&.conference_solution&.name == "Google Meet"
        return event.conference_data.entry_points&.find { |ep| ep.entry_point_type == "video" }&.uri
      end

      # 2. Check hangout link (legacy)
      return event.hangout_link if event.hangout_link

      # 3. Check description for meet.google.com links
      if event.description
        meet_match = event.description.match(/https:\/\/meet\.google\.com\/[a-z-]+/)
        return meet_match[0] if meet_match
      end

      # 4. Check location field
      if event.location
        meet_match = event.location.match(/https:\/\/meet\.google\.com\/[a-z-]+/)
        return meet_match[0] if meet_match
      end

      nil
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

    def time_until_event(event_time)
      now = Time.now
      event_time = event_time.is_a?(String) ? Time.parse(event_time) : event_time

      diff_seconds = (event_time - now).to_i
      return "started" if diff_seconds < 0

      if diff_seconds < 60
        "#{diff_seconds} seconds"
      elsif diff_seconds < 3600
        "#{diff_seconds / 60} minutes"
      elsif diff_seconds < 86400
        hours = diff_seconds / 3600
        minutes = (diff_seconds % 3600) / 60
        "#{hours}h #{minutes}m"
      else
        days = diff_seconds / 86400
        "#{days} days"
      end
    end

    def log_error(method, error)
      Mcpeasy::Config.ensure_config_dirs
      File.write(
        Mcpeasy::Config.log_file_path("gmeet", "error"),
        "#{Time.now}: #{method} error: #{error.class}: #{error.message}\n#{error.backtrace.join("\n")}\n",
        mode: "a"
      )
    end
  end
end
