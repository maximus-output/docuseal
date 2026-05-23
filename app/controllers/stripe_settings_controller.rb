# frozen_string_literal: true

class StripeSettingsController < ApplicationController
  before_action :authorize_admin

  def index
    @config = EncryptedConfig.find_or_initialize_by(account: current_account,
                                                    key: EncryptedConfig::STRIPE_CONFIGS_KEY)
  end

  def create
    secret_key = params[:secret_key].to_s.strip
    publishable_key = params[:publishable_key].to_s.strip

    config = EncryptedConfig.find_or_initialize_by(account: current_account,
                                                   key: EncryptedConfig::STRIPE_CONFIGS_KEY)
    current_value = config.value.is_a?(Hash) ? config.value : {}

    new_value = current_value
      .merge('secret_key' => secret_key.presence || current_value['secret_key'],
             'publishable_key' => publishable_key.presence || current_value['publishable_key'])
      .compact_blank

    if new_value.blank?
      config.destroy if config.persisted?
    else
      config.value = new_value
      config.save!
    end

    redirect_to settings_stripe_index_path, notice: I18n.t('settings_have_been_saved')
  end

  private

  def authorize_admin
    authorize!(:manage, current_account)
  end
end
