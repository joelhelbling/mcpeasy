# frozen_string_literal: true

require "fileutils"

module Mcpeasy
  class Setup
    CONFIG_DIR = File.expand_path("~/.config/mcpeasy")
    SUBDIRS = %w[google slack].freeze

    def self.create_config_directories
      puts "Setting up mcpeasy configuration directories..."
      
      # Create main config directory
      FileUtils.mkdir_p(CONFIG_DIR)
      puts "Created #{CONFIG_DIR}"
      
      # Create subdirectories
      SUBDIRS.each do |subdir|
        dir_path = File.join(CONFIG_DIR, subdir)
        FileUtils.mkdir_p(dir_path)
        puts "Created #{dir_path}"
      end
      
      puts "mcpeasy setup complete!"
    end
  end
end