# frozen_string_literal: true

require "bundler/setup"
require "slack-ruby-client"
require "mcpeasy/config"

module Slack
  class Service
    def initialize
      ensure_env!
      @client = ::Slack::Web::Client.new(
        token: Mcpeasy::Config.slack_bot_token,
        timeout: 10, # 10 second timeout
        open_timeout: 5 # 5 second connection timeout
      )
    end

    def post_message(channel:, text:, username: nil, thread_ts: nil)
      # Clean up parameters
      clean_channel = channel.to_s.sub(/^#/, "").strip
      clean_text = text.to_s.strip

      # Validate inputs
      raise "Channel cannot be empty" if clean_channel.empty?
      raise "Text cannot be empty" if clean_text.empty?

      # Build request parameters
      params = {
        channel: clean_channel,
        text: clean_text
      }
      params[:username] = username if username && !username.to_s.strip.empty?
      params[:thread_ts] = thread_ts if thread_ts && !thread_ts.to_s.strip.empty?

      # Retry logic for reliability
      max_retries = 3
      retry_count = 0

      begin
        response = @client.chat_postMessage(params)

        if response["ok"]
          response
        else
          raise "Failed to post message: #{response["error"]} (#{response.inspect})"
        end
      rescue ::Slack::Web::Api::Errors::TooManyRequestsError => e
        retry_count += 1
        if retry_count <= max_retries
          sleep_time = e.retry_after || 1
          sleep(sleep_time)
          retry
        else
          raise "Slack API Error: #{e.message}"
        end
      rescue ::Slack::Web::Api::Errors::SlackError => e
        retry_count += 1
        if retry_count <= max_retries && retryable_error?(e)
          sleep(0.5 * retry_count) # Exponential backoff
          retry
        else
          raise "Slack API Error: #{e.message}"
        end
      rescue => e
        Mcpeasy::Config.ensure_config_dirs
        File.write(Mcpeasy::Config.log_file_path("slack", "error"), "#{Time.now}: Slack::Service error: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}\n", mode: "a")
        raise e
      end
    end

    def list_channels(limit: 100, cursor: nil, exclude_archived: true)
      params = {
        types: "public_channel,private_channel",
        limit: [limit.to_i, 1000].min,
        exclude_archived: exclude_archived
      }
      params[:cursor] = cursor if cursor && !cursor.to_s.strip.empty?

      response = @client.conversations_list(params)

      if response["ok"]
        channels = response["channels"].to_a.map do |channel|
          {
            name: channel["name"],
            id: channel["id"]
          }
        end

        {
          channels: channels,
          has_more: response.dig("response_metadata", "next_cursor") ? true : false,
          next_cursor: response.dig("response_metadata", "next_cursor")
        }
      else
        raise "Failed to list channels: #{response["error"]}"
      end
    rescue ::Slack::Web::Api::Errors::SlackError => e
      raise "Slack API Error: #{e.message}"
    end

    def test_connection
      response = @client.auth_test

      if response["ok"]
        response
      else
        raise "Authentication failed: #{response["error"]}"
      end
    rescue ::Slack::Web::Api::Errors::SlackError => e
      raise "Slack API Error: #{e.message}"
    end

    def tool_definitions
    end

    private

    def retryable_error?(error)
      # Network-related errors that might be temporary
      error.is_a?(::Slack::Web::Api::Errors::TimeoutError) ||
        error.is_a?(::Slack::Web::Api::Errors::UnavailableError) ||
        (error.respond_to?(:message) && error.message.include?("timeout"))
    end

    def ensure_env!
      unless Mcpeasy::Config.slack_bot_token
        raise <<~ERROR
          Slack bot token is not configured!
          Please run: mcp set slack_bot_token YOUR_TOKEN
        ERROR
      end
    end
  end
end
