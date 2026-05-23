# frozen_string_literal: true

class PersonalizationStripeController < ApplicationController
  def create
    authorize!(:manage, current_account)

    config = EncryptedConfig.find_or_initialize_by(account: current_account, key: 'stripe_configs')

    secret_key = params[:secret_key].to_s.strip
    config.value = config.value&.merge('secret_key' => secret_key) || { 'secret_key' => secret_key }
    config.save!

    redirect_back fallback_location: settings_personalization_path,
                  notice: I18n.t('settings_have_been_saved')
  end
end
