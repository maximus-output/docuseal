# frozen_string_literal: true

module Api
  class StripePaymentsController < ApiBaseController
    skip_authorization_check

    def show
      stripe_key = load_stripe_key
      return render json: { error: 'Stripe not configured' }, status: :unprocessable_content unless stripe_key

      if params[:id].start_with?('in_')
        invoice = Stripe::Invoice.retrieve(params[:id], { api_key: stripe_key })
        render json: {
          id: invoice.id,
          status: invoice.status,
          payment_status: invoice.status == 'paid' ? 'paid' : 'unpaid'
        }
      else
        session = Stripe::Checkout::Session.retrieve(params[:id], { api_key: stripe_key })
        render json: {
          id: session.id,
          status: session.status,
          payment_status: session.payment_status
        }
      end
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    def create
      stripe_key = load_stripe_key
      return render json: { error: 'Stripe not configured' }, status: :unprocessable_content unless stripe_key

      submitter = current_account.submitters.find_by(slug: params[:submitter_slug])
      return render json: { error: 'Not found' }, status: :not_found unless submitter

      authorize!(:manage, submitter)

      field = submitter.submission.template.fields.find { |f| f['uuid'] == params[:field_uuid] }
      return render json: { error: 'Field not found' }, status: :not_found unless field

      preferences = field['preferences'] || {}
      amount_cents = (preferences['price'].to_f * 100).to_i

      return render json: { error: 'Invalid payment amount' }, status: :unprocessable_content if amount_cents <= 0

      currency = (preferences['currency'] || 'USD').downcase
      payment_mode = preferences['payment_mode'].presence || 'blocking'

      if payment_mode == 'after_signing'
        create_invoice(field, submitter, stripe_key, preferences, amount_cents, currency)
      else
        create_checkout_session(field, submitter, stripe_key, amount_cents, currency)
      end
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    # Called by frontend after returning from Stripe with ?stripe_session_id=
    def update
      stripe_key = load_stripe_key
      return render json: { error: 'Stripe not configured' }, status: :unprocessable_content unless stripe_key

      session = Stripe::Checkout::Session.retrieve(params[:id], { api_key: stripe_key })

      unless session.payment_status == 'paid'
        return render json: { error: 'Payment not completed' }, status: :unprocessable_content
      end

      render json: { uuid: session.id }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    def create_checkout_session(field, submitter, stripe_key, amount_cents, currency)
      base_url = params[:referer].presence || request.base_url
      session = Stripe::Checkout::Session.create({
                                                   mode: 'payment',
                                                   success_url: "#{base_url}?stripe_session_id={CHECKOUT_SESSION_ID}",
                                                   cancel_url: base_url,
                                                   customer_email: submitter.email.presence,
                                                   line_items: [{
                                                     quantity: 1,
                                                     price_data: {
                                                       currency:,
                                                       unit_amount: amount_cents,
                                                       product_data: { name: field['name'].presence || 'Payment' }
                                                     }
                                                   }],
                                                   metadata: { submitter_slug: submitter.slug,
                                                               field_uuid: field['uuid'] }
                                                 }, { api_key: stripe_key })

      render json: { url: session.url, id: session.id }
    end

    def create_invoice(field, submitter, stripe_key, preferences, amount_cents, currency)
      payment_terms = preferences['payment_terms'].presence || 'due_on_receipt'
      days_until_due = preferences['days_until_due'].to_i.positive? ? preferences['days_until_due'].to_i : 30

      customer = find_or_create_customer(submitter, stripe_key)

      invoice = Stripe::Invoice.create({
                                         customer: customer.id,
                                         collection_method: 'send_invoice',
                                         days_until_due: payment_terms == 'net_x' ? days_until_due : 0,
                                         metadata: { submitter_slug: submitter.slug, field_uuid: field['uuid'] }
                                       }, { api_key: stripe_key })

      Stripe::InvoiceItem.create({
                                   customer: customer.id,
                                   invoice: invoice.id,
                                   amount: amount_cents,
                                   currency:,
                                   description: field['name'].presence || 'Payment'
                                 }, { api_key: stripe_key })

      invoice = Stripe::Invoice.finalize_invoice(invoice.id, {}, { api_key: stripe_key })
      Stripe::Invoice.send_invoice(invoice.id, {}, { api_key: stripe_key })

      render json: { id: invoice.id, non_blocking: true }
    end

    def find_or_create_customer(submitter, stripe_key)
      email = submitter.email.presence

      if email.present?
        existing = Stripe::Customer.search({ query: "email:'#{email}'" }, { api_key: stripe_key })
        return existing.data.first if existing.data.any?
      end

      Stripe::Customer.create({
        email:,
        name: submitter.name.presence,
        metadata: { submitter_slug: submitter.slug }
      }.compact, { api_key: stripe_key })
    end

    def load_stripe_key
      EncryptedConfig.find_by(account: current_account, key: EncryptedConfig::STRIPE_CONFIGS_KEY)&.value&.dig('secret_key')
    end
  end
end
