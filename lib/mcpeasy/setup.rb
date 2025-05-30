# frozen_string_literal: true

require "fileutils"
require_relative "config"

module Mcpeasy
  class Setup
    def self.create_config_directories
      puts "Setting up mcpeasy configuration directories..."

      # Use Config class to create all directories including logs
      Config.ensure_config_dirs

      puts "Created #{Config::CONFIG_DIR}"
      puts "Created #{Config::GOOGLE_DIR}"
      puts "Created #{Config::SLACK_DIR}"
      puts "Created #{Config::LOGS_DIR}"

      puts "mcpeasy setup complete!"
    end
  end
end
