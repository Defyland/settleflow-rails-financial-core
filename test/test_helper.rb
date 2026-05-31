ENV["RAILS_ENV"] ||= "test"

if ENV["COVERAGE"]
  require "simplecov"

  SimpleCov.start "rails" do
    enable_coverage :branch
    add_filter "/test/"
    minimum_coverage 85
  end
end

require_relative "../config/environment"
require "rails/test_help"

Dir[Rails.root.join("test/test_helpers/**/*.rb")].each { |file| require file }

class ActiveSupport::TestCase
  fixtures :all
  include ActiveJob::TestHelper

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    Rack::Attack.cache.store.clear if defined?(Rack::Attack)
  end
end

class ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
end
