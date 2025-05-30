# frozen_string_literal: true

require "bundler/setup"
require "net/http"
require "json"
require "uri"
require "mcpeasy/config"

class NotionTool
  BASE_URI = "https://api.notion.com/v1"

  def initialize
    ensure_env!
  end

  def search_pages(query: "", page_size: 10)
    body = {
      query: query.to_s.strip,
      page_size: [page_size.to_i, 100].min,
      filter: {
        value: "page",
        property: "object"
      }
    }

    response = post_request("/search", body)
    parse_search_results(response, "page")
  rescue => e
    log_error("search_pages", e)
    raise e
  end

  def search_databases(query: "", page_size: 10)
    body = {
      query: query.to_s.strip,
      page_size: [page_size.to_i, 100].min,
      filter: {
        value: "database",
        property: "object"
      }
    }

    response = post_request("/search", body)
    parse_search_results(response, "database")
  rescue => e
    log_error("search_databases", e)
    raise e
  end

  def get_page(page_id)
    clean_id = clean_notion_id(page_id)
    response = get_request("/pages/#{clean_id}")

    {
      id: response["id"],
      title: extract_title(response),
      url: response["url"],
      created_time: response["created_time"],
      last_edited_time: response["last_edited_time"],
      properties: response["properties"]
    }
  rescue => e
    log_error("get_page", e)
    raise e
  end

  def get_page_content(page_id)
    clean_id = clean_notion_id(page_id)
    response = get_request("/blocks/#{clean_id}/children")

    blocks = response["results"] || []
    extract_text_content(blocks)
  rescue => e
    log_error("get_page_content", e)
    raise e
  end

  def query_database(database_id, filters: {}, sorts: [], page_size: 100, start_cursor: nil)
    clean_id = clean_notion_id(database_id)

    body = {
      page_size: [page_size.to_i, 100].min
    }
    body[:filter] = filters unless filters.empty?
    body[:sorts] = sorts unless sorts.empty?
    body[:start_cursor] = start_cursor if start_cursor

    response = post_request("/databases/#{clean_id}/query", body)

    entries = response["results"].map do |page|
      {
        id: page["id"],
        title: extract_title(page),
        url: page["url"],
        created_time: page["created_time"],
        last_edited_time: page["last_edited_time"],
        properties: page["properties"]
      }
    end

    {
      entries: entries,
      has_more: response["has_more"],
      next_cursor: response["next_cursor"]
    }
  rescue => e
    log_error("query_database", e)
    raise e
  end

  def test_connection
    response = get_request("/users/me")
    {
      ok: true,
      user: response["name"] || response["id"],
      type: response["type"]
    }
  rescue => e
    log_error("test_connection", e)
    {ok: false, error: e.message}
  end

  def list_users(page_size: 100, start_cursor: nil)
    params = {page_size: [page_size.to_i, 100].min}
    params[:start_cursor] = start_cursor if start_cursor

    response = get_request("/users", params)

    users = response["results"].map do |user|
      {
        id: user["id"],
        type: user["type"],
        name: user["name"],
        avatar_url: user["avatar_url"],
        email: user.dig("person", "email")
      }
    end

    {
      users: users,
      has_more: response["has_more"],
      next_cursor: response["next_cursor"]
    }
  rescue => e
    log_error("list_users", e)
    raise e
  end

  def get_user(user_id)
    response = get_request("/users/#{user_id}")

    {
      id: response["id"],
      type: response["type"],
      name: response["name"],
      avatar_url: response["avatar_url"],
      email: response.dig("person", "email")
    }
  rescue => e
    log_error("get_user", e)
    raise e
  end

  def get_bot_user
    response = get_request("/users/me")

    {
      id: response["id"],
      type: response["type"],
      name: response["name"],
      bot: {
        owner: response.dig("bot", "owner"),
        workspace_name: response.dig("bot", "workspace_name")
      }
    }
  rescue => e
    log_error("get_bot_user", e)
    raise e
  end

  private

  def get_request(path, params = {})
    uri = URI("#{BASE_URI}#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10
    http.open_timeout = 5

    request = Net::HTTP::Get.new(uri)
    add_headers(request)

    response = http.request(request)
    handle_response(response)
  end

  def post_request(path, body)
    uri = URI("#{BASE_URI}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10
    http.open_timeout = 5

    request = Net::HTTP::Post.new(uri)
    add_headers(request)
    request.body = body.to_json

    response = http.request(request)
    handle_response(response)
  end

  def add_headers(request)
    request["Authorization"] = "Bearer #{Mcpeasy::Config.notion_api_key}"
    request["Content-Type"] = "application/json"
    request["Notion-Version"] = "2022-06-28"
  end

  def handle_response(response)
    case response.code.to_i
    when 200..299
      JSON.parse(response.body)
    when 401
      raise "Authentication failed. Please check your Notion API key."
    when 403
      raise "Access forbidden. Check your integration permissions."
    when 404
      raise "Resource not found. Check the ID and ensure the integration has access."
    when 429
      raise "Rate limit exceeded. Please try again later."
    else
      error_data = begin
        JSON.parse(response.body)
      rescue
        {}
      end
      error_msg = error_data["message"] || "Unknown error"
      raise "Notion API Error (#{response.code}): #{error_msg}"
    end
  end

  def parse_search_results(response, type)
    response["results"].map do |item|
      {
        id: item["id"],
        title: extract_title(item),
        url: item["url"],
        created_time: item["created_time"],
        last_edited_time: item["last_edited_time"]
      }
    end
  end

  def extract_title(object)
    return "Untitled" unless object["properties"]

    # Try to find title property
    title_prop = object["properties"].find { |_, prop| prop["type"] == "title" }
    if title_prop
      title_content = title_prop[1]["title"]
      return title_content.map { |t| t["plain_text"] }.join if title_content&.any?
    end

    # Fallback: look for any text in properties
    object["properties"].each do |_, prop|
      case prop["type"]
      when "rich_text"
        text = prop["rich_text"]&.map { |t| t["plain_text"] }&.join
        return text if text && !text.empty?
      end
    end

    "Untitled"
  end

  def extract_text_content(blocks)
    text_content = []

    blocks.each do |block|
      case block["type"]
      when "paragraph"
        text = block["paragraph"]["rich_text"]&.map { |t| t["plain_text"] }&.join
        text_content << text if text && !text.empty?
      when "heading_1", "heading_2", "heading_3"
        heading_type = block["type"]
        text = block[heading_type]["rich_text"]&.map { |t| t["plain_text"] }&.join
        text_content << text if text && !text.empty?
      when "bulleted_list_item", "numbered_list_item"
        list_type = block["type"]
        text = block[list_type]["rich_text"]&.map { |t| t["plain_text"] }&.join
        text_content << "• #{text}" if text && !text.empty?
      when "to_do"
        text = block["to_do"]["rich_text"]&.map { |t| t["plain_text"] }&.join
        checked = block["to_do"]["checked"] ? "☑" : "☐"
        text_content << "#{checked} #{text}" if text && !text.empty?
      end
    end

    text_content.join("\n\n")
  end

  def clean_notion_id(id)
    # Remove hyphens and ensure it's a valid UUID format
    id.to_s.delete("-")
  end

  def log_error(method, error)
    Mcpeasy::Config.ensure_config_dirs
    File.write(
      Mcpeasy::Config.log_file_path("notion", "error"),
      "#{Time.now}: NotionTool##{method} error: #{error.class}: #{error.message}\n#{error.backtrace.join("\n")}\n",
      mode: "a"
    )
  end

  def ensure_env!
    unless Mcpeasy::Config.notion_api_key
      raise <<~ERROR
        Notion API key is not configured!
        Please run: mcpz notion set_api_key YOUR_API_KEY
      ERROR
    end
  end
end
