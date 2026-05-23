# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.on(:startup) do
    Sidekiq::Cron::Job.load_from_hash(
      'check_and_send_reminders' => {
        'cron' => '*/30 * * * *',
        'class' => 'CheckAndSendRemindersJob'
      }
    )
  end
end
