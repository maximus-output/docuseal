# frozen_string_literal: true

class SamlSessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_authorization_check

  def init
    saml_config = load_saml_config
    return redirect_to root_path, alert: 'SSO is not configured' unless saml_config

    settings = build_saml_settings(saml_config)
    auth_request = OneLogin::RubySaml::Authrequest.new
    redirect_to auth_request.create(settings), allow_other_host: true
  end

  def acs
    saml_config = load_saml_config
    return redirect_to root_path, alert: 'SSO is not configured' unless saml_config

    settings = build_saml_settings(saml_config)
    saml_response = OneLogin::RubySaml::Response.new(params[:SAMLResponse], settings:)

    if saml_response.is_valid?
      email = saml_response.attributes['email'] ||
              saml_response.attributes['emailAddress'] ||
              saml_response.attributes['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'] ||
              saml_response.nameid

      user = User.active.find_by(email: email.to_s.downcase.strip)

      if user
        sign_in user
        redirect_to root_path
      else
        redirect_to new_user_session_path, alert: "No account found for #{email}. Please contact your administrator."
      end
    else
      redirect_to new_user_session_path, alert: "SSO authentication failed: #{saml_response.errors.join(', ')}"
    end
  end

  def metadata
    saml_config = load_saml_config
    return head :not_found unless saml_config

    settings = build_saml_settings(saml_config)
    meta = OneLogin::RubySaml::Metadata.new
    render xml: meta.generate(settings, true)
  end

  private

  def load_saml_config
    EncryptedConfig.find_by(key: 'saml_configs')&.value
  end

  def build_saml_settings(saml_config)
    settings = OneLogin::RubySaml::Settings.new
    settings.assertion_consumer_service_url = "#{request.base_url}/saml/acs"
    settings.sp_entity_id = "#{request.base_url}/saml/metadata"
    settings.idp_sso_target_url = saml_config['idp_sso_target_url']
    settings.idp_entity_id = saml_config['idp_entity_id']
    settings.idp_cert = saml_config['idp_cert']
    settings.name_identifier_format = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'
    settings
  end
end
