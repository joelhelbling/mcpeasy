require "bundler/setup"
require "model_context_protocol"
require "model_context_protocol/transports/stdio"
require_relative "slack_tool"

class SlackServer
  class TestConnection < ModelContextProtocol::Tool
    description "Test the Slack API connection"

    input_schema(
      properties: {},
      required: []
    )

    class << self
      def call(server_context:)
        response = server_context[:slack_tool].test_connection

        if response["ok"]
          ModelContextProtocol::Tool::Response.new([{
            type: "text",
            text: "✅ Successfully connected to Slack. Bot: #{response["user"]}, Team: #{response["team"]}"
          }])
        else
          ModelContextProtocol::Tool::Response.new([{
            type: "error",
            text: "❌ Authention failed: #{response["error"]}"
          }])
        end
      end
    end
  end

  class ListChannels < ModelContextProtocol::Tool
    description "List available Slack channels"

    input_schema(
      properties: {},
      required: []
    )

    class << self
      def call(server_context:)
        channels = server_context[:slack_tool].list_channels

        output = "📋 #{channels.count} Available channels: " 
        output << channels.map {|c|
          "##{c[:name]} (ID: #{c[:id]})"
        }.join(", ")
        ModelContextProtocol::Tool::Response.new([{
          type: "text",
          text: output
        }])
      end
    end
  end

  class PostMessage < ModelContextProtocol::Tool
    description "Post a message to a Slack channel"

    input_schema(
      properties: {
        channel: {
          type: "string",
          description: "The Slack channel name (with or without #)"
        },
        text: {
          type: "string",
          description: "The message text to post"
        },
        username: {
          type: "string",
          description: "Optional custom username for the message"
        },
        thread_ts: {
          type: "string",
          description: "Optional timestamp of parent message to reply to"
        }
      },
      required: ["channel", "text"]
    )

    class << self
      def call(message:, server_context:)
        channel = message["channel"].sub(/^#/, "")
        text = message["text"]
        username = message["username"]
        thread_ts = message["thread_ts"]

        response = server_context[:slack_tool].post_message(
          channel: channel,
          text: text,
          username: username,
          thread_ts: thread_ts
        )

        puts response.inspect

        ModelContextProtocol::Tool::Response.new([{
          type: "text",
          text: "✅ Message posted successfully to ##{channel} (Message timestamp: #{response['ts']})"
        }])
      end
    end
  end

  class << self
    def run
      @server = ModelContextProtocol::Server.new(
        name: "slack",
        tools: [TestConnection, ListChannels, PostMessage],
        server_context: {slack_tool: SlackTool.new}
      )
      ModelContextProtocol::Transports::StdioTransport
        .new(@server)
        .open
    end
  end
end

if __FILE__ == $0
  ModelContextProtocol.configure do |config|
    config.exception_reporter = ->(exception, server_context) {
      puts server_context.inspect
      raise exception
    }
  end
  SlackServer.run
end
