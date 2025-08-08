require "httparty"
require "json"

module Rbai
  class Client
    PROVIDERS = {
      google: {
        base_uri:    "https://generativelanguage.googleapis.com/v1beta/models",
        default_model: "gemini-2.0-flash"
      },
      openai: {
        base_uri:    "https://api.openai.com/v1",
        default_model: "gpt-4.1-2025-04-14"
      },
      claude: {
        base_uri:    "https://api.anthropic.com/v1",
        default_model: "claude-sonnet-4-20250514"
      }
    }.freeze

    def initialize(provider:, api_key: nil)
      @provider = provider.to_sym
      config = PROVIDERS[@provider] or raise ArgumentError, "Unsupported provider: #{provider}"
      @base_uri      = config[:base_uri]
      @default_model = config[:default_model]

      @api_key =
      api_key ||
      case @provider
      when :google
        ENV["GOOGLE_API_KEY"] || ENV["GOOGLE_GENAI_API_KEY"]
      when :openai
        ENV["OPENAI_API_KEY"]
      when :claude
        ENV["CLAUDE_API_KEY"] || ENV["ANTHROPIC_API_KEY"]
      end

      raise ArgumentError, "API key missing for #{@provider}" unless @api_key
    end

    def generate_content(prompt, system_instruction: nil, generation_config: nil, model_id: nil)
      model_id ||= @default_model
      raw = send("#{@provider}_request", prompt, system_instruction, generation_config, model_id)
      extract_text(raw)
    end

    private

    def google_request(prompt, system_instruction, generation_config, model_id)
      body = {
        contents: [ { parts: [ { text: prompt } ] } ]
      }
      body[:systemInstruction] = { parts: [ { text: system_instruction } ] } if system_instruction
      body[:generationConfig] = generation_config if generation_config

      resp = HTTParty.post(
        "#{@base_uri}/#{model_id}:generateContent",
        query:   { key: @api_key },
        headers: { "Content-Type" => "application/json" },
        body:    body.to_json
      )
      handle_response(resp)
      resp.parsed_response
    end

    def openai_request(prompt, system_instruction, generation_config, model_id)
      messages = []
      messages << { role: "system", content: system_instruction } if system_instruction
      messages << { role: "user",   content: prompt          }

      body = { model: model_id, messages: messages }
      body.merge!(generation_config) if generation_config

      resp = HTTParty.post(
        "#{@base_uri}/chat/completions",
        headers: {
          "Content-Type"  => "application/json",
          "Authorization" => "Bearer #{@api_key}"
        },
        body:    body.to_json
      )
      handle_response(resp)
      resp.parsed_response
    end

    def claude_request(prompt, system_instruction, generation_config, model_id)
      body = {
        model:      model_id,
        messages:   [ { role: "user", content: prompt } ],
        max_tokens: 1000
      }
      body[:system] = system_instruction if system_instruction
      body.merge!(generation_config) if generation_config

      resp = HTTParty.post(
        "#{@base_uri}/messages",
        headers: {
          "Content-Type"        => "application/json",
          "x-api-key"           => @api_key,
          "anthropic-version"   => "2023-06-01"
        },
        body:    body.to_json
      )
      handle_response(resp)
      resp.parsed_response
    end

    def handle_response(resp)
      unless resp.success?
        raise "Request failed: #{resp.code} #{resp.body}"
      end
    end

    def extract_text(response)
      case @provider
      when :google
        cand = Array(response["candidates"]).first
        parts = cand&.dig("content", "parts")
        Array(parts).map { |p| p["text"].to_s }.join

      when :openai
        choice = Array(response["choices"]).first
        choice&.dig("message", "content").to_s

      when :claude
        Array(response["content"]).map { |c| c["text"].to_s }.join
      end
    end
  end
end