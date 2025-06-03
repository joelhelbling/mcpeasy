# frozen_string_literal: true

require "bundler/setup"
require "thor"
require_relative "service"

module Slack
  class CLI < Thor
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
    method_option :limit, type: :numeric, default: 1000, desc: "Maximum number of channels to retrieve"
    method_option :include_archived, type: :boolean, default: false, desc: "Include archived channels in results"
    def list
      all_channels = []
      cursor = nil
      limit = options[:limit]
      exclude_archived = !options[:include_archived]

      loop do
        result = tool.list_channels(limit: limit, cursor: cursor, exclude_archived: exclude_archived)
        all_channels.concat(result[:channels])

        break unless result[:has_more] && all_channels.count < limit
        cursor = result[:next_cursor]
      end

      if all_channels && !all_channels.empty?
        puts "📋 Available channels (#{all_channels.count} total):"
        all_channels.each do |channel|
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
      @tool ||= Service.new
    end
  end
end
