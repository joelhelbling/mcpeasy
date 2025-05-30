# frozen_string_literal: true

require "bundler/setup"
require "thor"
require_relative "slack_tool"

class SlackCLI < Thor
  desc "test", "Test the Slack API connection"
  def test
    response = tool.test_connection

    if response["ok"]
      puts "✅ Successfully connected to Slack"
      puts "   Bot name: #{response["user"]}"
      puts "   Team: #{response["team"]}"
    else
      warn "❌ Authentication failed: #{response["error"]}"
    end
  rescue RuntimeError => e
    puts "❌ Failed to connect to Slack: #{e.message}"
    exit 1
  end

  desc "list", "List available Slack channels"
  def list
    channels = tool.list_channels

    if channels && !channels.empty?
      puts "📋 Available channels:"
      channels.each do |channel|
        puts "   ##{channel[:name]} (ID: #{channel[:id]})"
      end
    end
  rescue RuntimeError => e
    warn "❌ Failed to list channels: #{e.message}"
    exit 1
  end

  desc "post", "Post a message to a Slack channel"
  method_option :channel, required: true, type: :string, aliases: "-c"
  method_option :message, required: true, type: :string, aliases: "-m"
  method_option :username, type: :string, aliases: "-u"
  method_option :timestamp, type: :string, aliases: "-t"
  def post
    channel = options[:channel]
    text = options[:message]
    username = options[:username]
    thread_ts = options[:timestamp]

    response = tool.post_message(
      channel: channel,
      text: text,
      username: username,
      thread_ts: thread_ts
    )

    if response["ok"]
      puts "✅ Message posted successfully to ##{channel}"
      puts "   Message timestamp: #{response["ts"]}"
    else
      warn "❌ Failed to post message: #{response["error"]}"
      exit 1
    end
  rescue RuntimeError => e
    warn "❌ Unexpected error: #{e.message}"
    exit 1
  end

  private

  def tool
    @tool ||= SlackTool.new
  end
end
