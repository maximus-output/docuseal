# frozen_string_literal: true

class SubmissionsBulkController < ApplicationController
  before_action :load_template

  before_action do
    authorize!(:create, Submission)
  end

  def create
    emails = extract_emails_from_spreadsheet(params[:spreadsheet])

    if emails.blank?
      return render turbo_stream: turbo_stream.replace(
        :submitters_error,
        partial: 'submissions/error',
        locals: { error: I18n.t('no_valid_emails_found_in_file') }
      ), status: :unprocessable_content
    end

    submissions = Submissions.create_from_emails(
      template: @template,
      user: current_user,
      source: :bulk,
      mark_as_sent: true,
      emails: emails.join(','),
      params: { 'send_completed_email' => true }
    )

    WebhookUrls.enqueue_events(submissions, 'submission.created')
    Submissions.send_signature_requests(submissions)
    SearchEntries.enqueue_reindex(submissions)

    redirect_to template_path(@template),
                notice: I18n.t('new_recipients_have_been_added')
  rescue StandardError => e
    render turbo_stream: turbo_stream.replace(
      :submitters_error,
      partial: 'submissions/error',
      locals: { error: e.message }
    ), status: :unprocessable_content
  end

  private

  def load_template
    @template = Template.accessible_by(current_ability).find(params[:template_id])
  end

  def extract_emails_from_spreadsheet(file)
    return [] if file.blank?

    content = file.read
    rows =
      if file.original_filename.end_with?('.csv')
        require 'csv'
        CSV.parse(content, headers: true)
      else
        require 'rubyXL'
        workbook = RubyXL::Parser.parse_buffer(StringIO.new(content))
        sheet = workbook.worksheets.first
        headers = sheet[0].cells.map { |c| c&.value.to_s.downcase.strip }
        sheet.drop(1).filter_map do |row|
          next unless row

          headers.zip(row.cells.map { |c| c&.value.to_s }).to_h
        end
      end

    email_key = rows.first&.headers&.find { |h| h.to_s.match?(/email/i) } if rows.respond_to?(:first) && rows.first.respond_to?(:headers)
    email_key ||= rows.first&.keys&.find { |k| k.to_s.match?(/email/i) }

    return [] if email_key.blank?

    rows.filter_map { |row| row[email_key].to_s.strip.presence }.select do |email|
      email.match?(User::EMAIL_REGEXP)
    end.uniq
  end
end
