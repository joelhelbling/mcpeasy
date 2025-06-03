# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-06-03

### Added
- Notion MCP server integration with comprehensive API support
- Pagination support for Slack channels listing
- Pagination support for Notion user listings and database queries
- Google Meet MCP server with meeting search and URL retrieval
- Setup command (`mcpz setup`) for initializing configuration directories
- Post-install message in gemspec for better user onboarding
- Shared authentication server for Google services OAuth flow
- MCP server mode for all services (Slack, Google Calendar, Drive, Meet, Notion)
- CLI interface with `mcpz` command for all services
- Configuration management system storing credentials in `~/.config/mcpeasy/`
- Logging system with logs stored in `~/.local/share/mcpeasy/logs/`

### Changed
- Refactored project structure for better consistency and namespacing
- Converted project from standalone scripts to Ruby gem
- Moved from individual MCP servers to unified gem architecture
- Refactored Google services to share authentication token capture server
- Improved MCP server implementation with fresh tool instances per call
- Standardized service structure with consistent cli.rb, mcp.rb, service.rb pattern

### Fixed
- Emoji rendering in Google token capture service
- Ruby code style compliance with standardrb

### Removed
- Unused project files and dependencies
- Git submodules for external MCP servers
- Direct dependency on ruby-sdk in favor of hand-rolled implementation

## [0.1.0] - Initial Release

### Added
- Initial gem structure with Thor-based CLI
- Slack integration with message posting and channel listing
- Google Calendar integration with event listing and search
- Google Drive integration with file search and content retrieval
- Basic MCP server implementations for all services
- Development tooling with standardrb for code quality
