# frozen_string_literal: true

require_relative "lib/mcpeasy/version"

Gem::Specification.new do |spec|
  spec.name = "mcpeasy"
  spec.version = Mcpeasy::VERSION
  spec.authors = ["Joel Helbling"]
  spec.email = ["joel@joelhelbling.com"]

  spec.summary = "MCP servers made easy"
  spec.description = "mcpeasy, LM squeezy - Easy-to-use MCP servers for Google Calendar, Google Drive, Google Meet, and Slack"
  spec.homepage = "https://github.com/joelhelbling/mcpeasy"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/joelhelbling/mcpeasy"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end

  spec.bindir = "bin"
  spec.executables = ["mcpz"]
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "google-apis-calendar_v3", "~> 0.35"
  spec.add_dependency "google-apis-drive_v3", "~> 0.45"
  spec.add_dependency "googleauth", "~> 1.8"
  spec.add_dependency "slack-ruby-client", "~> 2.1"
  spec.add_dependency "webrick", "~> 1.8"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "mother", "~> 0.1"

  # Development dependencies
  spec.add_development_dependency "standard", "~> 1.50"

  # Post-install message and setup
  spec.post_install_message = "Setting up mcpeasy configuration directories..."

  # Run setup after installation
  spec.extensions = ["ext/setup.rb"]
end
