require "httparty"
require "json"
require "securerandom"

module Rbai
  class Client
    DEFAULT_TIMEOUT = 300           # seconds, long enough for big inputs
    DEFAULT_RETRIES = 3
    DEFAULT_BACKOFF_BASE = 0.8

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

    def initialize(provider:, api_key: nil, timeout: DEFAULT_TIMEOUT, retries: DEFAULT_RETRIES, stream: false, open_timeout: nil, read_timeout: nil)
      @provider = provider.to_sym
      config = PROVIDERS[@provider] or raise ArgumentError, "Unsupported provider: #{provider}"
      @base_uri      = config[:base_uri]
      @default_model = config[:default_model]

      @api_key =
        api_key ||
        case @provider
        when :google then ENV["GOOGLE_API_KEY"] || ENV["GOOGLE_GENAI_API_KEY"]
        when :openai then ENV["OPENAI_API_KEY"]
        when :claude then ENV["CLAUDE_API_KEY"] || ENV["ANTHROPIC_API_KEY"]
        end

      raise ArgumentError, "API key missing for #{@provider}" unless @api_key

      @timeout       = timeout
      @open_timeout  = open_timeout
      @read_timeout  = read_timeout
      @retries       = retries
      @stream        = stream
    end

    def generate_content(prompt, system_instruction: nil, generation_config: nil, model_id: nil, &on_chunk)
      model_id ||= @default_model
      raw = with_retries do
        send("#{@provider}_request", prompt, system_instruction, generation_config, model_id, stream: @stream && block_given?, &on_chunk)
      end
      return nil if block_given? # streaming path consumed via the block
      extract_text(raw)
    end

    private

    def with_retries
      attempt = 0
      begin
        attempt += 1
        yield
      rescue => e
        raise if attempt > @retries
        sleep ((DEFAULT_BACKOFF_BASE ** attempt) + rand * 0.1) # jitter
        retry
      end
    end

    def http_options(extra = {})
      opts = { headers: { "Content-Type" => "application/json" } }
      opts[:timeout]       = @timeout if @timeout
      opts[:open_timeout]  = @open_timeout if @open_timeout
      opts[:read_timeout]  = @read_timeout if @read_timeout
      opts.merge!(extra)
    end

    def google_request(prompt, system_instruction, generation_config, model_id, stream: false, &on_chunk)
      body = { contents: [ { parts: [ { text: prompt } ] } ] }
      body[:systemInstruction] = { parts: [ { text: system_instruction } ] } if system_instruction
      body[:generationConfig]  = generation_config if generation_config

      url = "#{@base_uri}/#{model_id}:generateContent"
      opts = http_options(query: { key: @api_key }, body: body.to_json)
      resp = if stream
        # HTTParty supports streaming via :stream_body and a block that receives fragments.
        HTTParty.post(url, opts.merge(stream_body: true)) { |frag| on_chunk.call(frag) }
      else
        HTTParty.post(url, opts)
      end
      handle_response(resp)
      resp.parsed_response
    end

    def openai_request(prompt, system_instruction, generation_config, model_id, stream: false, &on_chunk)
      messages = []
      messages << { role: "system", content: system_instruction } if system_instruction
      messages << { role: "user",   content: prompt }

      body = { model: model_id, messages: messages }
      body.merge!(generation_config) if generation_config
      body[:stream] = true if stream

      headers = {
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer #{@api_key}",
        # Prevent duplicate charges if we retry:
        "Idempotency-Key" => SecureRandom.uuid
      }

      url  = "#{@base_uri}/chat/completions"
      opts = http_options(headers: headers, body: body.to_json)

      if stream
        HTTParty.post(url, opts.merge(stream_body: true)) { |frag| on_chunk.call(frag) }
        return nil
      else
        resp = HTTParty.post(url, opts)
        handle_response(resp)
        resp.parsed_response
      end
    end

    def claude_request(prompt, system_instruction, generation_config, model_id, stream: false, &on_chunk)
      body = { model: model_id, messages: [ { role: "user", content: prompt } ], max_tokens: 1000 }
      body[:system] = system_instruction if system_instruction
      body.merge!(generation_config) if generation_config
      body[:stream] = true if stream

      headers = {
        "Content-Type"      => "application/json",
        "x-api-key"         => @api_key,
        "anthropic-version" => "2023-06-01"
      }

      url  = "#{@base_uri}/messages"
      opts = http_options(headers: headers, body: body.to_json)

      if stream
        HTTParty.post(url, opts.merge(stream_body: true)) { |frag| on_chunk.call(frag) }
        return nil
      else
        resp = HTTParty.post(url, opts)
        handle_response(resp)
        resp.parsed_response
      end
    end

    def handle_response(resp)
      unless resp && resp.respond_to?(:success?) && resp.success?
        code = resp&.code
        body = resp&.body
        raise "Request failed: #{code} #{body}"
      end
    end

    def extract_text(response)
      case @provider
      when :google
        cand  = Array(response["candidates"]).first
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
