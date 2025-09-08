# bundle install
# bundle exec ruby -Ilib examples/smoke_openai.rb

require "rbai"

simple_client = Rbai::Client.new(provider: :openai)
puts simple_client.generate_content("Name one Greek letter.")

stream_client = Rbai::Client.new(provider: :openai, stream: true, timeout: 120, retries: 0)
acc = +""
stream_client.generate_content("Stream the word 'नमस्ते' in two parts: 'नम' then 'स्ते'. Respond as plain text, no punctuation.") do |delta|
  print delta
  acc << delta
end
puts
puts "----"
puts acc