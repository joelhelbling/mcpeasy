# frozen_string_literal: true

require "webrick"
require "timeout"

class GoogleAuthServer
  def self.capture_auth_code(port: 8080, timeout: 60)
    new(port: port, timeout: timeout).capture_auth_code
  end

  def initialize(port: 8080, timeout: 60)
    @port = port
    @timeout = timeout
    @auth_code = nil
    @auth_received = false
  end

  def capture_auth_code
    server, server_thread = start_callback_server
    wait_for_auth_code(server, server_thread)
  end

  private

  def start_callback_server
    server = WEBrick::HTTPServer.new(
      Port: @port,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: [],
      BindAddress: "127.0.0.1"
    )

    server.mount_proc("/") do |req, res|
      if req.query["code"]
        @auth_code = req.query["code"]
        @auth_received = true
        res.content_type = "text/html"
        res.body = success_html
        schedule_shutdown(server)
      elsif req.query["error"]
        @auth_received = true
        res.content_type = "text/html"
        res.body = error_html(req.query["error"])
        schedule_shutdown(server)
      else
        res.content_type = "text/html"
        res.body = waiting_html
      end
    end

    server_thread = Thread.new do
      server.start
    rescue => e
      puts "Server error: #{e.message}" unless e.message.include?("shutdown")
    end

    sleep 0.1
    [server, server_thread]
  rescue => e
    raise "Failed to start callback server: #{e.message}"
  end

  def wait_for_auth_code(server, server_thread)
    begin
      Timeout.timeout(@timeout) do
        until @auth_received
          sleep 0.1
          break unless server_thread.alive?
        end
      end
    rescue Timeout::Error
      puts "\n⏰ Timeout waiting for authorization. Please try again."
      return nil
    ensure
      begin
        server&.shutdown
        server_thread&.join(2)
      rescue
        # Ignore shutdown errors
      end
    end

    @auth_code
  end

  def schedule_shutdown(server)
    Thread.new do
      sleep 0.5
      server.shutdown
    end
  end

  def success_html
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Authorization Successful</title>
        <style>
          body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
          .success { color: #28a745; }
        </style>
      </head>
      <body>
        <h1 class="success">&#x2713; Authorization Successful!</h1>
        <p>You can now close this window and return to your terminal.</p>
      </body>
      </html>
    HTML
  end

  def error_html(error)
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Authorization Failed</title>
        <style>
          body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
          .error { color: #dc3545; }
        </style>
      </head>
      <body>
        <h1 class="error">&#x2717; Authorization Failed</h1>
        <p>Error: #{error}</p>
        <p>Please try again from your terminal.</p>
      </body>
      </html>
    HTML
  end

  def waiting_html
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Waiting for Authorization</title>
        <style>
          body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        </style>
      </head>
      <body>
        <h1>Waiting for Authorization...</h1>
        <p>Please complete the authorization process.</p>
      </body>
      </html>
    HTML
  end
end
