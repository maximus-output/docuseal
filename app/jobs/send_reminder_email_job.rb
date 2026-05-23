# frozen_string_literal: true

class SendReminderEmailJob
  include Sidekiq::Job

  def perform(params = {})
    submitter = Submitter.find_by(id: params['submitter_id'])

    return unless submitter
    return if submitter.completed_at?
    return if submitter.declined_at?
    return if submitter.email.blank?
    return if submitter.submission.archived_at?

    SubmitterMailer.reminder_email(submitter).deliver_now!

    submitter.submission_events.create!(
      event_type: 'send_reminder_email',
      account_id: submitter.account_id,
      data: {}
    )
  end
end
