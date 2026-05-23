# frozen_string_literal: true

class SsoSettingsController < ApplicationController
  before_action :load_encrypted_config
  authorize_resource :encrypted_config, only: :index
  authorize_resource :encrypted_config, parent: false, except: :index

  def index; end

  def create
    value = @encrypted_config.value || {}
    value['idp_sso_target_url'] = params[:idp_sso_target_url].to_s.strip
    value['idp_entity_id'] = params[:idp_entity_id].to_s.strip
    value['idp_cert'] = params[:idp_cert].to_s.strip if params[:idp_cert].present?

    @encrypted_config.value = value

    if @encrypted_config.save
      redirect_to settings_sso_index_path, notice: I18n.t('settings_have_been_saved')
    else
      redirect_to settings_sso_index_path, alert: I18n.t('unable_to_save')
    end
  end

  private

  def load_encrypted_config
    @encrypted_config =
      EncryptedConfig.find_or_initialize_by(account: current_account, key: 'saml_configs')
  end
end
