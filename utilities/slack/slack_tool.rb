# frozen_string_literal: true

require "bundler/setup"
require "slack-ruby-client"
require "dotenv/load"

class SlackTool
  def initialize
    ensure_env!
    @client = Slack::Web::Client.new(token: ENV["SLACK_BOT_TOKEN"])
  end

  def post_message(channel:, text:, username: nil, thread_ts: nil)
    response = @client.chat_postMessage(
      channel: channel.sub(/^#/, ""),
      text: text,
      username: username,
      thread_ts: thread_ts
    )

    if response["ok"]
      response
    else
      raise "Failed to post message: #{response["error"]}"
    end
  rescue Slack::Web::Api::Errors::SlackError => e
    raise "Slack API Error: #{e.message}"
  end

  def list_channels
    response = @client.conversations_list(types: "public_channel,private_channel")

    if response["ok"]
      response["channels"].to_a.map do |channel|
        {
          name: channel["name"],
          id: channel["id"]
        }
      end
    else
      raise "Failed to list channels: #{response["error"]}"
    end
  rescue Slack::Web::Api::Errors::SlackError => e
    raise "Slack API Error: #{e.message}"
  end

  def test_connection
    response = @client.auth_test

    if response["ok"]
      response
    else
      raise "Authentication failed: #{response["error"]}"
    end
  rescue Slack::Web::Api::Errors::SlackError => e
    raise "Slack API Error: #{e.message}"
  end

  def tool_definitions

  end

  private

  def ensure_env!
    unless ENV["SLACK_BOT_TOKEN"]
      raise <<~ERROR
        SLACK_BOT_TOKEN environment variable is not set!"
        Please add your Slack bot token to the .env file
      ERROR
    end
  end
end
