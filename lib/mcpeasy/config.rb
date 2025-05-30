# frozen_string_literal: true

require "fileutils"
require "json"
require "mother"

module Mcpeasy
  class Config
    CONFIG_DIR = File.expand_path("~/.config/mcpeasy").freeze
    GOOGLE_DIR = File.join(CONFIG_DIR, "google").freeze
    SLACK_DIR = File.join(CONFIG_DIR, "slack").freeze
    NOTION_DIR = File.join(CONFIG_DIR, "notion").freeze
    LOGS_DIR = File.expand_path("~/.local/share/mcpeasy/logs").freeze

    class << self
      def ensure_config_dirs
        FileUtils.mkdir_p(CONFIG_DIR)
        FileUtils.mkdir_p(GOOGLE_DIR)
        FileUtils.mkdir_p(SLACK_DIR)
        FileUtils.mkdir_p(NOTION_DIR)
        FileUtils.mkdir_p(LOGS_DIR)
      end

      # Google credentials management
      def google_credentials_path
        File.join(GOOGLE_DIR, "credentials.json")
      end

      def google_credentials
        return nil unless File.exist?(google_credentials_path)
        Mother.create(google_credentials_path)
      end

      def save_google_credentials(credentials_json)
        ensure_config_dirs
        File.write(google_credentials_path, credentials_json)
      end

      def google_client_id
        credentials = google_credentials
        return nil unless credentials
        credentials.installed&.client_id || credentials.web&.client_id
      end

      def google_client_secret
        credentials = google_credentials
        return nil unless credentials
        credentials.installed&.client_secret || credentials.web&.client_secret
      end

      # Google token management
      def google_token_path
        File.join(GOOGLE_DIR, "token.json")
      end

      def google_token
        return nil unless File.exist?(google_token_path)
        Mother.create(google_token_path)
      end

      def save_google_token(token_data)
        ensure_config_dirs
        File.write(google_token_path, JSON.pretty_generate(token_data))
      end

      # Slack configuration
      def slack_token_path
        File.join(SLACK_DIR, "token.json")
      end

      def slack_bot_token
        return nil unless File.exist?(slack_token_path)
        config = JSON.parse(File.read(slack_token_path))
        config["bot_token"]
      end

      def save_slack_bot_token(token)
        ensure_config_dirs
        config = File.exist?(slack_token_path) ? JSON.parse(File.read(slack_token_path)) : {}
        config["bot_token"] = token
        File.write(slack_token_path, JSON.pretty_generate(config))
      end

      # Notion configuration
      def notion_token_path
        File.join(NOTION_DIR, "token.json")
      end

      def notion_api_key
        return nil unless File.exist?(notion_token_path)
        config = JSON.parse(File.read(notion_token_path))
        config["api_key"]
      end

      def save_notion_api_key(api_key)
        ensure_config_dirs
        config = File.exist?(notion_token_path) ? JSON.parse(File.read(notion_token_path)) : {}
        config["api_key"] = api_key
        File.write(notion_token_path, JSON.pretty_generate(config))
      end

      # Logs directory
      def logs_dir
        LOGS_DIR
      end

      def log_file_path(service, type = "error")
        File.join(LOGS_DIR, "mcp_#{service}_#{type}.log")
      end

      def config_status
        {
          config_dir: CONFIG_DIR,
          logs_dir: LOGS_DIR,
          google_credentials: File.exist?(google_credentials_path),
          google_token: File.exist?(google_token_path),
          slack_config: File.exist?(slack_token_path),
          notion_config: File.exist?(notion_token_path)
        }
      end
    end
  end
end
