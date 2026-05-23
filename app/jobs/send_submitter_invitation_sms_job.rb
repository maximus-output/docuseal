# frozen_string_literal: true

class SendSubmitterInvitationSmsJob
  include Sidekiq::Job

  def perform(params = {})
    submitter = Submitter.find_by(id: params['submitter_id'])

    return unless submitter
    return if submitter.phone.blank?
    return if submitter.completed_at?
    return if submitter.declined_at?
    return if submitter.submission.archived_at?

    sms_config = EncryptedConfig.find_by(account: submitter.account, key: EncryptedConfig::SMS_CONFIGS_KEY)&.value

    return if sms_config.blank?

    message = build_sms_message(submitter)
    send_sms(sms_config, to: submitter.phone, body: message)

    submitter.submission_events.create!(
      event_type: 'send_sms',
      account_id: submitter.account_id,
      data: {}
    )

    submitter.update_columns(sent_at: Time.current) if submitter.sent_at.nil?
  end

  private

  def build_sms_message(submitter)
    template_name = submitter.submission.template&.name || 'document'
    url_options = ReplaceEmailVariables.build_url_options_for(submitter, is_email: false)

    link = Rails.application.routes.url_helpers.submit_form_url(
      slug: submitter.slug,
      c: SubmissionEvents.build_tracking_param(submitter, 'click_sms'),
      **url_options
    )

    "You have been invited to sign #{template_name}. Open the link: #{link}"
  end

  def send_sms(config, to:, body:)
    case config['provider']
    when 'twilio'
      send_via_twilio(config, to:, body:)
    when 'vonage'
      send_via_vonage(config, to:, body:)
    else
      raise "Unknown SMS provider: #{config['provider']}"
    end
  end

  def send_via_twilio(config, to:, body:)
    require 'net/http'

    uri = URI("https://api.twilio.com/2010-04-01/Accounts/#{config['account_sid']}/Messages.json")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri)
    request.basic_auth(config['account_sid'], config['auth_token'])
    request.set_form_data('To' => to, 'From' => config['from_number'], 'Body' => body)

    response = http.request(request)
    raise "Twilio error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
  end

  def send_via_vonage(config, to:, body:)
    require 'net/http'
    require 'json'

    uri = URI('https://rest.nexmo.com/sms/json')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = {
      api_key: config['account_sid'],
      api_secret: config['auth_token'],
      to: to.gsub(/\D/, ''),
      from: config['from_number'],
      text: body
    }.to_json

    response = http.request(request)
    parsed = JSON.parse(response.body)
    status = parsed.dig('messages', 0, 'status')
    raise "Vonage error #{status}: #{parsed.dig('messages', 0, 'error-text')}" unless status == '0'
  end
end
