# frozen_string_literal: true

require "json"

module MCPServer
  def run_mcp_server
    warn "Starting #{mcp_server_info[:name]} MCP Server..."

    loop do
      line = $stdin.readline.strip
      next if line.empty?

      request = JSON.parse(line)
      response = handle_mcp_request(request)
      puts response.to_json
      $stdout.flush
    end
  rescue EOFError
    warn "Client disconnected, shutting down MCP server"
  rescue => e
    warn "MCP Server error: #{e.message}"
  end

  private

  def handle_mcp_request(request)
    case request["method"]
    when "initialize"
      handle_mcp_initialize(request)
    when "tools/list"
      handle_mcp_tools_list(request)
    when "tools/call"
      handle_mcp_tool_call(request)
    else
      mcp_error_response(request["id"], -32601, "Method not found: #{request["method"]}")
    end
  end

  def handle_mcp_initialize(request)
    {
      jsonrpc: "2.0",
      id: request["id"],
      result: {
        protocolVersion: "2024-11-05",
        capabilities: {
          tools: {}
        },
        serverInfo: mcp_server_info
      }
    }
  end

  def handle_mcp_tools_list(request)
    {
      jsonrpc: "2.0",
      id: request["id"],
      result: {
        tools: mcp_tools
      }
    }
  end

  def handle_mcp_tool_call(request)
    tool_name = request.dig("params", "name")
    arguments = request.dig("params", "arguments") || {}

    begin
      result = mcp_call_tool(tool_name, arguments)
      {
        jsonrpc: "2.0",
        id: request["id"],
        result: {
          content: [
            {
              type: "text",
              text: result
            }
          ]
        }
      }
    rescue => e
      mcp_error_response(request["id"], -32603, e.message)
    end
  end

  def mcp_error_response(id, code, message)
    {
      jsonrpc: "2.0",
      id: id,
      error: {
        code: code,
        message: message
      }
    }
  end

  # Abstract methods - must be implemented by includer
  def mcp_tools
    raise NotImplementedError, "#{self.class} must implement #mcp_tools"
  end

  def mcp_call_tool(tool_name, arguments)
    raise NotImplementedError, "#{self.class} must implement #mcp_call_tool"
  end

  def mcp_server_info
    {name: "mcp-server", version: "1.0.0"}
  end
end
