# bundle install
# bundle exec ruby -Ilib examples/smoke_openai.rb

require "rbai"

simple_client = Rbai::Client.new(provider: :openai)
puts simple_client.generate_content("Name one Greek letter.")

buf = +""
stream_client = Rbai::Client.new(provider: :openai, stream: true)

stream_client.generate_content("Write 50 words about Kadane's algorithm.") do |frag|
  buf << frag
  # process complete lines
  while (line_end = buf.index("\n"))
    line = buf.slice!(0..line_end) # includes newline
    next unless line.start_with?("data: ")
    payload = line.sub(/\Adata:\s*/, "").strip
    break if payload == "[DONE]"
    begin
      obj = JSON.parse(payload)
      delta = obj.dig("choices", 0, "delta", "content")
      print(delta) if delta
    rescue JSON::ParserError
      # ignore keepalive/comment lines
    end
  end
end
puts