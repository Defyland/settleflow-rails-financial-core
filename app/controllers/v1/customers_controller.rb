module V1
  class CustomersController < BaseController
    def index
      render_success PagedCollectionSerializer.render(
        current_organization.customers.order(created_at: :desc),
        params:,
        item_serializer: CustomerSerializer
      )
    end

    def show
      render_success data: CustomerSerializer.render(customer)
    end

    def create
      render_idempotent(status: :created) do
        created = current_organization.customers.create!(
          customer_params.merge(metadata: metadata_param)
        )
        { data: CustomerSerializer.render(created) }
      end
    end

    private

    def customer
      @customer ||= find_by_public_id!(current_organization.customers, params[:id])
    end

    def customer_params
      params.permit(:external_id, :legal_name, :document_kind, :document_number)
    end
  end
end
