# frozen_string_literal: true

class SmsSettingsController < ApplicationController
  before_action :load_encrypted_config
  authorize_resource :encrypted_config, only: :index
  authorize_resource :encrypted_config, parent: false, only: :create

  def index; end

  def create
    value = @encrypted_config.value || {}
    value['provider'] = params[:provider].to_s.strip if params[:provider].present?
    value['account_sid'] = params[:account_sid].to_s.strip if params[:account_sid].present?
    value['auth_token'] = params[:auth_token].to_s.strip if params[:auth_token].present?
    value['from_number'] = params[:from_number].to_s.strip if params[:from_number].present?

    @encrypted_config.value = value

    if @encrypted_config.save
      redirect_to settings_sms_index_path, notice: I18n.t('settings_have_been_saved')
    else
      redirect_to settings_sms_index_path, alert: I18n.t('unable_to_save')
    end
  end

  private

  def load_encrypted_config
    @encrypted_config =
      EncryptedConfig.find_or_initialize_by(account: current_account, key: EncryptedConfig::SMS_CONFIGS_KEY)
  end
end
