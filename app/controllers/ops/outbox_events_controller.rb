module Ops
  class OutboxEventsController < BaseController
    before_action -> { require_capability!(:retry_outbox_event) }, only: :retry

    def index
      @status = params[:status].presence
      scope = OutboxEvent.includes(:organization).order(created_at: :desc)
      scope = scope.where(status: @status) if @status.present?
      scope = search_like(scope.joins(:organization), %w[outbox_events.event_type outbox_events.aggregate_type outbox_events.correlation_id organizations.slug]) if params[:q].present?
      @outbox_events = paginate(scope)
    end

    def retry
      event = find_public!(OutboxEvent.includes(:organization), params[:id])
      if event.reset_for_retry!
        OutboxPublishJob.perform_later(event.id)
        operator_audit!(action: "ops.outbox.retry", subject: event, metadata: { event_type: event.event_type })
        redirect_to ops_outbox_events_path(status: "pending"), notice: "Outbox event queued for retry."
      else
        redirect_to ops_outbox_events_path(status: event.status), alert: "Outbox event cannot be retried from its current state."
      end
    end
  end
end
