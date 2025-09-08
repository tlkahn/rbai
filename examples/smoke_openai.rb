# bundle install
# bundle exec ruby -Ilib examples/smoke_openai.rb

require "rbai"

# OpenAI
simple_client = Rbai::Client.new(provider: :openai)
puts simple_client.generate_content("Name one Greek letter.")

stream_client = Rbai::Client.new(provider: :openai, stream: true, timeout: 120, retries: 0)
acc = +""
stream_client.generate_content("Stream the word 'नमस्ते' in two parts: 'नम' then 'स्ते'. Respond as plain text, no punctuation.") do |delta|
  print delta
  acc << delta
end
puts
puts "---- OpenAI ----"
puts acc

# Google
simple_client_google = Rbai::Client.new(provider: :google)
puts simple_client_google.generate_content("Name one Greek letter.")

stream_client_google = Rbai::Client.new(provider: :google, stream: true, timeout: 120, retries: 0)
acc_google = +""
stream_client_google.generate_content("Stream the word 'नमस्ते' in two parts: 'नम' then 'स्ते'. Respond as plain text, no punctuation.") do |delta|
  print delta
  acc_google << delta
end
puts
puts "---- Google ----"
puts acc_google

# Claude
simple_client_claude = Rbai::Client.new(provider: :claude)
puts simple_client_claude.generate_content("Name one Greek letter.")

stream_client_claude = Rbai::Client.new(provider: :claude, stream: true, timeout: 120, retries: 0)
acc_claude = +""
stream_client_claude.generate_content("Stream the word 'नमस्ते' in two parts: 'नम' then 'स्ते'. Respond as plain text, no punctuation.") do |delta|
  print delta
  acc_claude << delta
end
puts
puts "---- Claude ----"
puts acc_claude
