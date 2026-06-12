module EnvironmentTestHelper
  def with_rails_env(name)
    original_env = Rails.env
    Rails.singleton_class.define_method(:env) { ActiveSupport::StringInquirer.new(name) }
    yield
  ensure
    Rails.singleton_class.define_method(:env) { original_env }
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include EnvironmentTestHelper
end
