#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'slack-ruby-client'
require 'dotenv/load'
require 'json'

class SlackPoster
  def initialize
    @client = Slack::Web::Client.new(token: ENV['SLACK_BOT_TOKEN'])
  end

  def post_message(channel:, text:, username: nil, thread_ts: nil, silent: false)
    begin
      response = @client.chat_postMessage(
        channel: channel,
        text: text,
        username: username,
        thread_ts: thread_ts
      )
      
      if response['ok']
        puts "✅ Message posted successfully to ##{channel}" unless silent
        puts "   Message timestamp: #{response['ts']}" unless silent
        return response
      else
        puts "❌ Failed to post message: #{response['error']}" unless silent
        return nil
      end
      
    rescue Slack::Web::Api::Errors::SlackError => e
      puts "❌ Slack API Error: #{e.message}" unless silent
      return nil
    rescue StandardError => e
      puts "❌ Unexpected error: #{e.message}" unless silent
      return nil
    end
  end

  def list_channels(silent: false)
    begin
      response = @client.conversations_list(types: 'public_channel,private_channel')
      
      if response['ok']
        unless silent
          puts "📋 Available channels:"
          response['channels'].each do |channel|
            puts "   ##{channel['name']} (ID: #{channel['id']})"
          end
        end
        return response['channels']
      else
        puts "❌ Failed to list channels: #{response['error']}" unless silent
        return nil
      end
      
    rescue Slack::Web::Api::Errors::SlackError => e
      puts "❌ Slack API Error: #{e.message}" unless silent
      return nil
    end
  end

  def test_connection(silent: false)
    begin
      response = @client.auth_test
      
      if response['ok']
        unless silent
          puts "✅ Successfully connected to Slack"
          puts "   Bot name: #{response['user']}"
          puts "   Team: #{response['team']}"
        end
        return response
      else
        puts "❌ Authentication failed: #{response['error']}" unless silent
        return nil
      end
      
    rescue Slack::Web::Api::Errors::SlackError => e
      puts "❌ Slack API Error: #{e.message}" unless silent
      return nil
    end
  end
end

class MCPMode
  def initialize(slack_poster)
    @slack_poster = slack_poster
  end

  def run
    # Send MCP server info to stderr for debugging
    STDERR.puts "Starting Slack MCP Server..."
    
    loop do
      line = STDIN.readline.strip
      next if line.empty?
      
      request = JSON.parse(line)
      response = handle_mcp_request(request)
      puts response.to_json
      STDOUT.flush
    end
  rescue EOFError
    STDERR.puts "Client disconnected, shutting down MCP server"
  rescue => e
    STDERR.puts "MCP Server error: #{e.message}"
  end

  private

  def handle_mcp_request(request)
    case request['method']
    when 'initialize'
      handle_initialize(request)
    when 'tools/list'
      handle_tools_list(request)
    when 'tools/call'
      handle_tool_call(request)
    else
      error_response(request['id'], -32601, "Method not found: #{request['method']}")
    end
  end

  def handle_initialize(request)
    {
      jsonrpc: '2.0',
      id: request['id'],
      result: {
        protocolVersion: '2024-11-05',
        capabilities: {
          tools: {}
        },
        serverInfo: {
          name: 'slack-poster',
          version: '1.0.0'
        }
      }
    }
  end

  def handle_tools_list(request)
    {
      jsonrpc: '2.0',
      id: request['id'],
      result: {
        tools: [
          {
            name: 'post_message',
            description: 'Post a message to a Slack channel',
            inputSchema: {
              type: 'object',
              properties: {
                channel: {
                  type: 'string',
                  description: 'The Slack channel name (with or without #)'
                },
                text: {
                  type: 'string',
                  description: 'The message text to post'
                },
                username: {
                  type: 'string',
                  description: 'Optional custom username for the message'
                },
                thread_ts: {
                  type: 'string',
                  description: 'Optional timestamp of parent message to reply to'
                }
              },
              required: ['channel', 'text']
            }
          },
          {
            name: 'list_channels',
            description: 'List available Slack channels',
            inputSchema: {
              type: 'object',
              properties: {},
              required: []
            }
          },
          {
            name: 'test_connection',
            description: 'Test the Slack API connection',
            inputSchema: {
              type: 'object',
              properties: {},
              required: []
            }
          }
        ]
      }
    }
  end

  def handle_tool_call(request)
    tool_name = request.dig('params', 'name')
    arguments = request.dig('params', 'arguments') || {}
    
    case tool_name
    when 'post_message'
      handle_post_message(request, arguments)
    when 'list_channels'
      handle_list_channels(request)
    when 'test_connection'
      handle_test_connection(request)
    else
      error_response(request['id'], -32602, "Unknown tool: #{tool_name}")
    end
  end

  def handle_post_message(request, arguments)
    channel = arguments['channel']&.sub(/^#/, '')
    text = arguments['text']
    username = arguments['username']
    thread_ts = arguments['thread_ts']
    
    unless channel && text
      return error_response(request['id'], -32602, "Missing required parameters: channel and text")
    end
    
    result = @slack_poster.post_message(
      channel: channel,
      text: text,
      username: username,
      thread_ts: thread_ts,
      silent: true
    )
    
    if result
      {
        jsonrpc: '2.0',
        id: request['id'],
        result: {
          content: [
            {
              type: 'text',
              text: "Message posted successfully to ##{channel}. Timestamp: #{result['ts']}"
            }
          ]
        }
      }
    else
      error_response(request['id'], -32603, "Failed to post message to Slack")
    end
  end

  def handle_list_channels(request)
    channels = @slack_poster.list_channels(silent: true)
    
    if channels
      channel_list = channels.map { |ch| "##{ch['name']}" }.join(', ')
      {
        jsonrpc: '2.0',
        id: request['id'],
        result: {
          content: [
            {
              type: 'text',
              text: "Available channels: #{channel_list}"
            }
          ]
        }
      }
    else
      error_response(request['id'], -32603, "Failed to list channels")
    end
  end

  def handle_test_connection(request)
    result = @slack_poster.test_connection(silent: true)
    
    if result
      {
        jsonrpc: '2.0',
        id: request['id'],
        result: {
          content: [
            {
              type: 'text',
              text: "Successfully connected to Slack. Bot: #{result['user']}, Team: #{result['team']}"
            }
          ]
        }
      }
    else
      error_response(request['id'], -32603, "Failed to connect to Slack")
    end
  end

  def error_response(id, code, message)
    {
      jsonrpc: '2.0',
      id: id,
      error: {
        code: code,
        message: message
      }
    }
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
  
  # Check for MCP mode
  if ARGV.include?('--mcp')
    # Run as MCP server
    MCPMode.new(poster).run
    exit 0
  end
  
  # Test connection first
  unless poster.test_connection
    puts "❌ Unable to connect to Slack. Please check your token."
    exit 1
  end

  # Get command line arguments
  if ARGV.length < 2
    puts "Usage: ruby slack_poster.rb <channel> <message> [username]"
    puts "       ruby slack_poster.rb --mcp  (run as MCP server)"
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
