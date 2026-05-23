# frozen_string_literal: true

module Api
  class StripeConnectController < ApiBaseController
    skip_authorization_check

    def show
      configured = EncryptedConfig.exists?(account: current_account, key: EncryptedConfig::STRIPE_CONFIGS_KEY)
      render json: { status: configured ? 'connected' : 'disconnected' }
    end
  end
end
