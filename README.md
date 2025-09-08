# Rbai

Rbai is a lightweight Ruby client that provides a unified interface to major LLM/AI vendors: **Google Gemini**, **OpenAI GPT**, and **Anthropic Claude**.
It abstracts over different REST APIs and response formats, making it easier to send prompts and retrieve text responses with minimal setup.

---

## Features

- Support for **Google Generative Language API (Gemini)**
- Support for **OpenAI Chat Completions API**
- Support for **Anthropic Claude Messages API**
- Unified `generate_content` method for prompts
- Automatic response parsing and text extraction
- Configurable system instructions and generation parameters

---

## Installation

Add this line to your application's Gemfile:

```ruby
gem "rbai", github: "your-username/rbai"
````

And then execute:

```sh
bundle install
```

Or install manually:

```sh
gem install rbai
```

---

## Usage

### 1. Set up API Keys

Export your API keys as environment variables:

```sh
# Google Gemini
export GOOGLE_API_KEY="your-google-api-key"

# or alternative
export GOOGLE_GENAI_API_KEY="your-google-genai-api-key"

# OpenAI
export OPENAI_API_KEY="your-openai-api-key"

# Anthropic Claude
export CLAUDE_API_KEY="your-claude-api-key"

# or alternative
export ANTHROPIC_API_KEY="your-anthropic-api-key"
```

### 2. Basic Example

```ruby
require "rbai"

# Initialize client
client = Rbai::Client.new(provider: :openai)

# Send a prompt
response = client.generate_content("Write a haiku about Ruby programming.")
puts response
```

### 3. With System Instruction

```ruby
client = Rbai::Client.new(provider: :claude)

response = client.generate_content(
  "Explain quantum entanglement simply.",
  system_instruction: "You are a physics tutor who uses plain language."
)

puts response
```

### 4. With Generation Config

```ruby
client = Rbai::Client.new(provider: :google)

response = client.generate_content(
  "List three benefits of functional programming.",
  generation_config: { temperature: 0.7, maxOutputTokens: 200 }
)

puts response
```

---

## Providers

| Provider  | Default Model              | Base URI                                                  |
| --------- | -------------------------- | --------------------------------------------------------- |
| Google    | `gemini-2.0-flash`         | `https://generativelanguage.googleapis.com/v1beta/models` |
| OpenAI    | `gpt-4.1-2025-04-14`       | `https://api.openai.com/v1`                               |
| Anthropic | `claude-sonnet-4-20250514` | `https://api.anthropic.com/v1`                            |

---

## API Reference

### `Rbai::Client.new(provider:, api_key: nil)`

Initialize a client for a given provider.
If `api_key` is not supplied, it will be read from environment variables.

* `provider` — one of `:google`, `:openai`, `:claude`
* `api_key` (optional) — explicit API key

### `#generate_content(prompt, system_instruction: nil, generation_config: nil, model_id: nil)`

Send a prompt to the selected provider and return the response text.

* `prompt` — user input (string)
* `system_instruction` — optional system role content
* `generation_config` — provider-specific config (hash)
* `model_id` — override default model (string)

Returns: plain text string response.

---

## Error Handling

If the HTTP request fails or the provider returns an error, an exception is raised:

```ruby
begin
  response = client.generate_content("Hello world")
rescue => e
  warn "Error: #{e.message}"
end
```

---

## Development

To run tests and lint:

```sh
bundle exec rake test
bundle exec rubocop
```

---

## License

MIT