module JsonRequestTestHelper
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(api_key = "test-api-key", extra = {})
    {
      "X-Api-Key" => api_key,
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }.merge(extra)
  end

  def post_json(path, payload, headers: auth_headers)
    post path, params: payload.to_json, headers: headers
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include JsonRequestTestHelper
end
