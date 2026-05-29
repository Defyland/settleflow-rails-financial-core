class PagedCollectionSerializer
  DEFAULT_LIMIT = 50
  MAX_LIMIT = 100

  def self.render(scope, params:, item_serializer:)
    limit = [[params.fetch(:limit, DEFAULT_LIMIT).to_i, 1].max, MAX_LIMIT].min
    records = scope.limit(limit)
    {
      data: records.map { |record| item_serializer.render(record) },
      meta: {
        limit:,
        returned: records.size
      }
    }
  end
end
