#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'slack-ruby-client'
require 'dotenv/load'

class SlackPoster
  def initialize
    @client = Slack::Web::Client.new(token: ENV['SLACK_BOT_TOKEN'])
  end

  def post_message(channel:, text:, username: nil, thread_ts: nil)
    begin
      response = @client.chat_postMessage(
        channel: channel,
        text: text,
        username: username,
        thread_ts: thread_ts
      )
      
      if response['ok']
        puts "✅ Message posted successfully to ##{channel}"
        puts "   Message timestamp: #{response['ts']}"
        return response
      else
        puts "❌ Failed to post message: #{response['error']}"
        return nil
      end
      
    rescue Slack::Web::Api::Errors::SlackError => e
      puts "❌ Slack API Error: #{e.message}"
      return nil
    rescue StandardError => e
      puts "❌ Unexpected error: #{e.message}"
      return nil
    end
  end

  def list_channels
    begin
      response = @client.conversations_list(types: 'public_channel,private_channel')
      
      if response['ok']
        puts "📋 Available channels:"
        response['channels'].each do |channel|
          puts "   ##{channel['name']} (ID: #{channel['id']})"
        end
      else
        puts "❌ Failed to list channels: #{response['error']}"
      end
      
    rescue Slack::Web::Api::Errors::SlackError => e
      puts "❌ Slack API Error: #{e.message}"
    end
  end

  def test_connection
    begin
      response = @client.auth_test
      
      if response['ok']
        puts "✅ Successfully connected to Slack"
        puts "   Bot name: #{response['user']}"
        puts "   Team: #{response['team']}"
        return true
      else
        puts "❌ Authentication failed: #{response['error']}"
        return false
      end
      
    rescue Slack::Web::Api::Errors::SlackError => e
      puts "❌ Slack API Error: #{e.message}"
      return false
    end
  end
end

# Main execution
if __FILE__ == $0
  # Check if required environment variable is set
  unless ENV['SLACK_BOT_TOKEN']
    puts "❌ SLACK_BOT_TOKEN environment variable is not set!"
    puts "   Please add your Slack bot token to the .env file"
    exit 1
  end

  poster = SlackPoster.new
  
  # Test connection first
  unless poster.test_connection
    puts "❌ Unable to connect to Slack. Please check your token."
    exit 1
  end

  # Get command line arguments
  if ARGV.length < 2
    puts "Usage: ruby slack_poster.rb <channel> <message> [username]"
    puts "Example: ruby slack_poster.rb general 'Hello from Ruby!' MyBot"
    puts ""
    puts "Available channels:"
    poster.list_channels
    exit 1
  end

  channel = ARGV[0]
  message = ARGV[1]
  username = ARGV[2] # Optional

  # Remove # from channel name if provided
  channel = channel.sub(/^#/, '')

  # Post the message
  result = poster.post_message(
    channel: channel,
    text: message,
    username: username
  )

  exit result ? 0 : 1
end
