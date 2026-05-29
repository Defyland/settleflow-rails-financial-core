module RequestHelpers
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(api_key = "test_api_key", extra = {})
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
