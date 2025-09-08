require "httparty"
require "json"
require "securerandom"

module Rbai
  class Client
    DEFAULT_TIMEOUT = 300           # seconds, long enough for big inputs
    DEFAULT_RETRIES = 3
    DEFAULT_BACKOFF_BASE = 1.8
    MAX_BACKOFF_SECONDS  = 20

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
        return yield
      rescue => e
        raise if attempt > @retries
        # Optional: only retry on transient classes
        transient = e.is_a?(Net::ReadTimeout) || e.is_a?(Net::OpenTimeout) || e.is_a?(Errno::ECONNRESET)
        raise unless transient
        sleep_time = [ (DEFAULT_BACKOFF_BASE ** attempt) + rand * 0.25, MAX_BACKOFF_SECONDS ].min
        sleep sleep_time
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
      prompt = normalize_text(prompt)
      body = { contents: [ { parts: [ { text: prompt } ] } ] }
      body[:systemInstruction] = { parts: [ { text: system_instruction } ] } if system_instruction
      body[:generationConfig]  = generation_config if generation_config

      if stream
        # Use the streaming method and ask for SSE
        url  = "#{@base_uri}/#{model_id}:streamGenerateContent"
        opts = http_options(
          query:   { key: @api_key, alt: "sse" }, # alt=sse is required for REST SSE
          headers: { "Accept" => "text/event-stream" },
          body:    body.to_json
        )
        stream_post(url, opts) do |payload|
          json  = JSON.parse(payload) rescue nil
          parts = json&.dig("candidates", 0, "content", "parts")
          text  = Array(parts).map { |p| p["text"].to_s }.join
          on_chunk.call(text.to_s.unicode_normalize(:nfc)) unless text.empty?
        end
        return nil
      else
        url  = "#{@base_uri}/#{model_id}:generateContent"
        opts = http_options(query: { key: @api_key }, body: body.to_json)
        resp = HTTParty.post(url, opts)
        handle_response(resp)
        resp.parsed_response
      end
    end


    def openai_request(prompt, system_instruction, generation_config, model_id, stream: false, &on_chunk)
      prompt = normalize_text(prompt)
      messages = []
      messages << { role: "system", content: system_instruction } if system_instruction
      messages << { role: "user",   content: prompt }

      body = { model: model_id, messages: messages }
      body.merge!(generation_config) if generation_config
      body[:stream] = true if stream

      body[:max_tokens] = (generation_config && generation_config[:max_tokens]) || 1200
      if generation_config && generation_config[:response_format]
        body[:response_format] = generation_config[:response_format] # e.g., {type: "json_object"}
      end

      headers = {
        "Content-Type"    => "application/json",
        "Authorization"   => "Bearer #{@api_key}",
        "Idempotency-Key" => SecureRandom.uuid
      }

      url  = "#{@base_uri}/chat/completions"
      opts = http_options(
        headers: stream ? headers.merge("Accept" => "text/event-stream") : headers,
        body: body.to_json
      )

      if stream
        stream_post(url, opts) do |payload|
          next if payload == "[DONE]"
          json  = JSON.parse(payload) rescue nil
          delta = json&.dig("choices", 0, "delta", "content")
          on_chunk.call(delta.to_s.unicode_normalize(:nfc)) if delta && !delta.empty?
        end
        return nil
      else
        resp = HTTParty.post(url, opts)
        handle_response(resp)
        resp.parsed_response
      end
    end

    def claude_request(prompt, system_instruction, generation_config, model_id, stream: false, &on_chunk)
      prompt = normalize_text(prompt)
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
      opts = http_options(
        headers: stream ? headers.merge("Accept" => "text/event-stream") : headers,
        body:    body.to_json
      )

      if stream
        stream_post(url, opts) do |payload|
          json = JSON.parse(payload) rescue nil
          if json && json["type"] == "content_block_delta" && json.dig("delta","type") == "text_delta"
            on_chunk.call(json.dig("delta","text").to_s.unicode_normalize(:nfc))
          end
        end
        return nil
      else
        resp = HTTParty.post(url, opts)
        handle_response(resp)
        resp.parsed_response
      end
    end

    def handle_response(resp)
      unless resp && resp.respond_to?(:success?) && resp.success?
        code = resp&.code.to_i
        if code == 429
          retry_after = resp.headers["retry-after"]&.to_i
          sleep(retry_after) if retry_after && retry_after > 0
        end
        raise "Request failed: #{code} #{resp&.body}"
      end
    end

    def stream_post(url, opts)
      buffer = +""
      HTTParty.post(url, opts.merge(stream_body: true)) do |frag|
        buffer << frag
        while (cut = buffer.index("\n\n")) # SSE frames end with a blank line
          frame = buffer.slice!(0..cut+1)
          frame.lines.grep(/^data:/).each do |line|
            yield line.sub(/^data:\s*/, "")
          end
        end
      end
    end

    def normalize_text(s)
      s = s.unicode_normalize(:nfc)
      s.gsub(/\s+/, " ").strip
    end

    def http_options(extra = {})
      default_headers = {
        "Content-Type"    => "application/json",
        "Accept"          => "application/json",
        "Accept-Encoding" => "gzip"            # advertise gzip; HTTParty auto-decompresses
        # "Connection"    => "keep-alive"     # optional; Net::HTTP keeps alive by default
      }

      # deep-merge headers so callers don't overwrite defaults
      merged_headers = default_headers.merge(extra.fetch(:headers, {}))
      opts = { headers: merged_headers }

      opts[:timeout]      = @timeout      if @timeout
      opts[:open_timeout] = @open_timeout if @open_timeout
      opts[:read_timeout] = @read_timeout if @read_timeout

      # merge everything except headers (already merged)
      opts.merge!(extra.reject { |k, _| k == :headers })
      opts
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
