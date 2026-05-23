# frozen_string_literal: true

class CheckAndSendRemindersJob
  include Sidekiq::Job

  DURATION_MAP = {
    'one_hour' => 1.hour,
    'two_hours' => 2.hours,
    'four_hours' => 4.hours,
    'eight_hours' => 8.hours,
    'twelve_hours' => 12.hours,
    'twenty_four_hours' => 24.hours,
    'two_days' => 2.days,
    'three_days' => 3.days,
    'four_days' => 4.days,
    'five_days' => 5.days,
    'six_days' => 6.days,
    'seven_days' => 7.days,
    'eight_days' => 8.days,
    'fifteen_days' => 15.days,
    'twenty_one_days' => 21.days,
    'thirty_days' => 30.days
  }.freeze

  def perform
    AccountConfig.where(key: AccountConfig::SUBMITTER_REMINDERS).find_each do |config|
      next unless config.value.is_a?(Hash)

      account = config.account
      durations = [
        config.value['first_duration'],
        config.value['second_duration'],
        config.value['third_duration']
      ].compact.filter_map { |d| DURATION_MAP[d] }.sort

      next if durations.empty?

      pending_submitters = Submitter
        .where(account_id: account.id, completed_at: nil, declined_at: nil)
        .where.not(email: [nil, ''])
        .joins(:submission)
        .where(submissions: { archived_at: nil })
        .where.not(sent_at: nil)

      pending_submitters.find_each do |submitter|
        next unless Accounts.can_send_emails?(account)

        sent_at = submitter.sent_at
        now = Time.current

        durations.each do |duration|
          target_time = sent_at + duration
          window_start = target_time - 30.minutes
          window_end = target_time + 30.minutes

          next unless now.between?(window_start, window_end)

          already_sent = submitter.submission_events
                                  .where(event_type: 'send_reminder_email')
                                  .where(created_at: window_start..window_end)
                                  .exists?

          next if already_sent

          SendReminderEmailJob.perform_async('submitter_id' => submitter.id)
          break
        end
      end
    end
  end
end
