# frozen_string_literal: true

require_relative "rbai/version"
require_relative "rbai/client.rb"

module Rbai
  class Error < StandardError; end

  ::GenaiClient = Client

end
