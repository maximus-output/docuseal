# frozen_string_literal: true

class PersonalizationLogoController < ApplicationController
  before_action :authorize_logo

  def create
    if params[:logo].present?
      current_account.logo.attach(params[:logo])
      redirect_back fallback_location: settings_personalization_path,
                    notice: I18n.t('settings_have_been_saved')
    else
      redirect_back fallback_location: settings_personalization_path,
                    alert: I18n.t('unable_to_save')
    end
  end

  def destroy
    current_account.logo.purge
    redirect_back fallback_location: settings_personalization_path,
                  notice: I18n.t('settings_have_been_saved')
  end

  private

  def authorize_logo
    authorize!(:manage, current_account)
  end
end
