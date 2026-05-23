# frozen_string_literal: true

module Api
  class StripePaymentsController < ApiBaseController
    skip_authorization_check

    def show
      stripe_key = load_stripe_key
      return render json: { error: 'Stripe not configured' }, status: :unprocessable_content unless stripe_key

      session = Stripe::Checkout::Session.retrieve(params[:id], { api_key: stripe_key })

      render json: {
        id: session.id,
        status: session.status,
        payment_status: session.payment_status
      }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    def create
      stripe_key = load_stripe_key
      return render json: { error: 'Stripe not configured' }, status: :unprocessable_content unless stripe_key

      return render json: { error: 'success_url is required' }, status: :unprocessable_content if params[:success_url].blank?

      submitter = current_account.submitters.find_by(slug: params[:submitter_slug])
      return render json: { error: 'Not found' }, status: :not_found unless submitter

      authorize!(:manage, submitter)

      field = submitter.submission.template.fields.find { |f| f['uuid'] == params[:field_uuid] }
      return render json: { error: 'Field not found' }, status: :not_found unless field

      session_params = build_session_params(field, submitter, params[:success_url])
      if session_params[:line_items].first[:price_data][:unit_amount] <= 0
        return render json: { error: 'Invalid payment amount' }, status: :unprocessable_content
      end

      session = Stripe::Checkout::Session.create(session_params.merge(api_key: stripe_key))

      render json: { url: session.url, id: session.id }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    def load_stripe_key
      EncryptedConfig.find_by(account: current_account, key: EncryptedConfig::STRIPE_CONFIGS_KEY)&.value&.dig('secret_key')
    end

    def build_session_params(field, submitter, success_url)
      preferences = field['preferences'] || {}
      amount_cents = (preferences['price'].to_f * 100).to_i
      currency = (preferences['currency'] || 'USD').downcase

      {
        mode: 'payment',
        success_url: "#{success_url}?stripe_session_id={CHECKOUT_SESSION_ID}",
        cancel_url: success_url.to_s,
        line_items: [{
          quantity: 1,
          price_data: {
            currency:,
            unit_amount: amount_cents,
            product_data: {
              name: field['name'].presence || 'Payment'
            }
          }
        }],
        metadata: {
          submitter_slug: submitter.slug,
          field_uuid: field['uuid']
        }
      }
    end
  end
end
