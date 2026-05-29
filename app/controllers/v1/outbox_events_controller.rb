module V1
  class OutboxEventsController < BaseController
    def index
      scope = current_organization.outbox_events.order(created_at: :desc)
      scope = scope.where(status: params[:status]) if params[:status].present?
      render_success PagedCollectionSerializer.render(scope, params:, item_serializer: OutboxEventSerializer)
    end
  end
end
