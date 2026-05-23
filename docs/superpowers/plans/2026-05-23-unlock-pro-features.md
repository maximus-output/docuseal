# Unlock Pro Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unlock all paywalled pro features in this self-hosted DocuSeal fork (AGPL-3.0) by replacing placeholder views with real implementations and adding missing backend logic.

**Architecture:** Features are gated in three ways: (1) placeholder ERB views that replace real UI, (2) CanCan abilities that are never granted (`:saml_sso`, `:bulk_send`, `:countless`), and (3) missing backend jobs/controllers (SMS job, Stripe controller). We fix each layer in turn — abilities first, then views, then backend implementations.

**Tech Stack:** Ruby on Rails 8, Sidekiq (already in Gemfile), CanCan, ActiveStorage (already in use for user signatures), rubyXL + csv gems (already in Gemfile), Vue 3 + Shakapacker

---

## Feature Map

| Feature | Gate Type | Effort |
|---|---|---|
| Automated Reminders | Missing job + banner shows placeholder | Medium |
| Company Logo | `_logo_form.html.erb` renders placeholder | Medium |
| Bulk Send from Spreadsheet | `_list_form.html.erb` renders placeholder | Medium |
| User Roles (editor/viewer) | HTML `disabled` attr + missing ROLES | Easy |
| Upgrade banners in nav | Cosmetic only | Easy |
| API & Embedding (dev mode) | `EmbedScriptsController` returns dummy JS | Easy |
| SMS Identity Verification | Missing `SendSubmitterInvitationSmsJob` + placeholder views | Hard (needs Twilio/Vonage account) |
| SSO / SAML | Placeholder only; needs ruby-saml gem | Hard (needs SAML IdP) |
| Accept Payments | No `/api/stripe_payments` backend | Hard (needs Stripe account) |

---

## Task 1: Grant Missing CanCan Abilities

**Files:**
- Modify: `lib/ability.rb:1-28`

The `Ability` class never grants `:saml_sso`, `:bulk_send`, `:countless`, or `:personalization_advanced`. These are checked with `can?(:manage, :symbol)` in views. Adding them here unlocks all gate checks that depend on them.

- [ ] **Step 1: Add ability grants**

Open `lib/ability.rb`. Replace the `can :manage, :mcp` line so the full bottom of `initialize` reads:

```ruby
    can :manage, WebhookUrl, account_id: user.account_id

    can :manage, :mcp
    can :manage, :saml_sso
    can :manage, :bulk_send
    can :manage, :countless
    can :manage, :personalization_advanced
    can :manage, :tenants
  end
```

- [ ] **Step 2: Verify with a quick Rails console check**

```bash
bundle exec rails runner "puts Ability.new(User.first).can?(:manage, :bulk_send)"
```

Expected: `true`

- [ ] **Step 3: Commit**

```bash
git add lib/ability.rb
git commit -m "feat: grant all pro abilities to self-hosted users"
```

---

## Task 2: Remove "Upgrade to Pro" Banners from Navigation

**Files:**
- Modify: `app/views/shared/_settings_nav.html.erb:67-73`
- Modify: `app/views/shared/_navbar_buttons.html.erb` (the upgrade button)
- Modify: `app/views/esign_settings/_default_signature_row.html.erb`

- [ ] **Step 1: Remove Plans/Pro link from settings nav**

In `app/views/shared/_settings_nav.html.erb`, find and remove the block that renders the "Plans" link with the Pro badge (lines ~67-73):

```erb
      <% if !Docuseal.demo? && can?(:manage, EncryptedConfig) && (current_user != true_user || !current_account.linked_account_account) %>
        <li>
          <%= content_for(:pro_link) || link_to(Docuseal.multitenant? ? console_redirect_index_path(redir: "#{Docuseal::CONSOLE_URL}/plans") : "#{Docuseal::CLOUD_URL}/sign_up?#{{ redir: "#{Docuseal::CONSOLE_URL}/on_premises" }.to_query}", class: 'text-base hover:bg-base-300', data: { turbo: false }) do %>
            <%= t('plans') %>
            <span class="badge badge-warning"><%= t('pro') %></span>
          <% end %>
        </li>
      <% end %>
```

Delete those 7 lines entirely.

- [ ] **Step 2: Remove the upgrade button from the top navbar**

In `app/views/shared/_navbar_buttons.html.erb`, find and remove the link that says "sign_up" and has class `btn-warning`:

```erb
  <%= link_to "#{Docuseal::CLOUD_URL}/sign_up?#{{ redir: "#{Docuseal::CONSOLE_URL}/on_premises" }.to_query}", class: 'hidden md:inline-flex btn btn-warning btn-sm', data: { prefetch: false } do %>
```

Delete that entire `link_to` block (including its `<% end %>`).

- [ ] **Step 3: Remove "Unlock with DocuSeal Pro" from esign trusted cert row**

In `app/views/esign_settings/_default_signature_row.html.erb`, replace the disabled "Unlock with DocuSeal Pro" button with an enabled version:

```erb
    <a href="<%= "#{Docuseal::CLOUD_URL}/sign_up?#{{ redir: "#{Docuseal::CONSOLE_URL}/on_premises" }.to_query}" %>" class="btn btn-neutral btn-sm text-white">
      <%= t('unlock_with_docuseal_pro') %>
    </a>
```

Remove this entire `<a>` tag and its surrounding `<td>` content so the trusted cert row just shows the cert without a purchase link.

- [ ] **Step 4: Commit**

```bash
git add app/views/shared/_settings_nav.html.erb \
        app/views/shared/_navbar_buttons.html.erb \
        app/views/esign_settings/_default_signature_row.html.erb
git commit -m "feat: remove upgrade/pro banners from nav and esign settings"
```

---

## Task 3: Enable User Roles (editor / viewer)

**Files:**
- Modify: `app/models/user.rb:57` — ROLES constant
- Modify: `app/views/users/_role_select.html.erb` — remove `disabled` attrs

The `User::ROLES` array only has `'admin'`. The select options `editor` and `viewer` are HTML-disabled.

- [ ] **Step 1: Expand ROLES in the User model**

In `app/models/user.rb`, find:

```ruby
  ROLES = [
    ADMIN_ROLE = 'admin'
  ].freeze
```

Replace with:

```ruby
  ROLES = [
    ADMIN_ROLE = 'admin',
    EDITOR_ROLE = 'editor',
    VIEWER_ROLE = 'viewer'
  ].freeze
```

- [ ] **Step 2: Remove `disabled` from role select options**

In `app/views/users/_role_select.html.erb`, replace:

```erb
    <option value="editor" disabled><%= t('editor') %></option>
    <option value="viewer" disabled><%= t('viewer') %></option>
```

With:

```erb
    <option value="editor"><%= t('editor') %></option>
    <option value="viewer"><%= t('viewer') %></option>
```

Also remove the "unlock more user roles" upgrade link block below the select:

```erb
  <a class="text-sm mt-3 px-4 py-2 bg-base-300 rounded-full block" target="_blank" href="<%= Docuseal.multitenant? ? ... %>">
    ...
    <%= t('unlock_more_user_roles_with_docuseal_pro') %>
    ...
  </a>
```

Delete that entire `<a>` tag block.

- [ ] **Step 3: Update Ability to check roles for authorization**

In `lib/ability.rb`, the current code grants blanket access. For viewer/editor restriction to mean anything, the Ability class needs role awareness. Add role-based conditions to the `initialize` method. Replace the full method body with:

```ruby
  def initialize(user)
    if user.role == User::ADMIN_ROLE
      can :manage, Template, Abilities::TemplateConditions.collection(user) do |template|
        Abilities::TemplateConditions.entity(template, user:, ability: 'manage')
      end
      can :destroy, Template, account_id: user.account_id
      can :manage, TemplateFolder, account_id: user.account_id
      can :manage, TemplateSharing, template: { account_id: user.account_id }
      can :manage, Submission, account_id: user.account_id
      can :manage, Submitter, account_id: user.account_id
      can :manage, User, account_id: user.account_id
      can :manage, EncryptedConfig, account_id: user.account_id
      can :manage, EncryptedUserConfig, user_id: user.id
      can :manage, AccountConfig, account_id: user.account_id
      can :manage, UserConfig, user_id: user.id
      can :manage, Account, id: user.account_id
      can :manage, AccessToken, user_id: user.id
      can :manage, McpToken, user_id: user.id
      can :manage, WebhookUrl, account_id: user.account_id
      can :manage, :mcp
      can :manage, :saml_sso
      can :manage, :bulk_send
      can :manage, :countless
      can :manage, :personalization_advanced
      can :manage, :tenants
    elsif user.role == User::EDITOR_ROLE
      can %i[read create update], Template, Abilities::TemplateConditions.collection(user) do |template|
        Abilities::TemplateConditions.entity(template, user:, ability: 'manage')
      end
      can :destroy, Template, account_id: user.account_id
      can :manage, TemplateFolder, account_id: user.account_id
      can :manage, TemplateSharing, template: { account_id: user.account_id }
      can :manage, Submission, account_id: user.account_id
      can :manage, Submitter, account_id: user.account_id
      can :read, User, account_id: user.account_id
      can :manage, EncryptedUserConfig, user_id: user.id
      can :read, AccountConfig, account_id: user.account_id
      can :manage, UserConfig, user_id: user.id
      can :manage, AccessToken, user_id: user.id
    elsif user.role == User::VIEWER_ROLE
      can :read, Template, Abilities::TemplateConditions.collection(user) do |template|
        Abilities::TemplateConditions.entity(template, user:, ability: 'read')
      end
      can :read, Submission, account_id: user.account_id
      can :read, Submitter, account_id: user.account_id
      can :read, User, account_id: user.account_id
      can :manage, UserConfig, user_id: user.id
      can :manage, AccessToken, user_id: user.id
    end
  end
```

- [ ] **Step 4: Run existing tests to check for regressions**

```bash
bundle exec rspec spec/requests/ --format progress
```

Expected: all passing (or same failures as before this change)

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb app/views/users/_role_select.html.erb lib/ability.rb
git commit -m "feat: enable editor and viewer user roles with role-based abilities"
```

---

## Task 4: Remove Reminder Upgrade Banner (UI fix)

**Files:**
- Modify: `app/views/notifications_settings/_reminder_banner.html.erb`

The `_reminder_banner.html.erb` currently just renders the placeholder upgrade message. The `_reminder_form.html.erb` already exists and works. We just need to remove the upgrade message so the form appears cleanly.

- [ ] **Step 1: Clear the reminder banner**

Replace the entire content of `app/views/notifications_settings/_reminder_banner.html.erb` with an empty file (or a brief info note):

```erb
<%# Reminder configuration is available below %>
```

- [ ] **Step 2: Remove reminder placeholder in bulk send context too**

The `_bulk_send_placeholder.html.erb` is handled in Task 7. For now just commit the banner fix.

- [ ] **Step 3: Commit**

```bash
git add app/views/notifications_settings/_reminder_banner.html.erb
git commit -m "feat: remove reminder upgrade banner, form is fully available"
```

---

## Task 5: Implement Automated Reminder Emails (Backend)

**Files:**
- Modify: `app/mailers/submitter_mailer.rb` — add `reminder_email` method
- Create: `app/jobs/send_reminder_email_job.rb`
- Create: `app/jobs/check_and_send_reminders_job.rb`
- Create: `config/initializers/sidekiq_scheduler.rb`

The `AccountConfig::SUBMITTER_REMINDERS` key stores `{first_duration:, second_duration:, third_duration:}`. Each duration is a string like `'one_hour'`, `'twenty_four_hours'`, `'seven_days'`. The `AccountConfigs::REMINDER_DURATIONS` hash maps these to human durations. We need: a mailer method, a job that sends one reminder, and a scheduled job that checks pending submitters each hour.

- [ ] **Step 1: Add `reminder_email` to SubmitterMailer**

In `app/mailers/submitter_mailer.rb`, add this method after `invitation_email`:

```ruby
  def reminder_email(submitter)
    @current_account = submitter.submission.account
    @submitter = submitter

    @email_config = AccountConfigs.find_for_account(@current_account,
                                                     AccountConfig::SUBMITTER_INVITATION_REMINDER_EMAIL_KEY)
    @body = fetch_config_email_body(@email_config, @submitter)

    assign_message_metadata('submitter_invitation', @submitter)

    reply_to = build_submitter_reply_to(@submitter, email_config: @email_config)

    maybe_set_custom_domain(@submitter)

    I18n.with_locale(@current_account.locale) do
      subject = build_invite_subject(nil, @email_config, submitter)

      mail(
        to: @submitter.friendly_name,
        from: from_address_for_submitter(submitter),
        subject:,
        reply_to:
      )
    end
  end
```

- [ ] **Step 2: Create `SendReminderEmailJob`**

Create `app/jobs/send_reminder_email_job.rb`:

```ruby
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
```

- [ ] **Step 3: Create `CheckAndSendRemindersJob`**

Create `app/jobs/check_and_send_reminders_job.rb`:

```ruby
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
        .where('submitters.sent_at IS NOT NULL')

      pending_submitters.find_each do |submitter|
        next unless Accounts.can_send_emails?(account)

        sent_at = submitter.sent_at
        now = Time.current

        durations.each_with_index do |duration, index|
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
```

- [ ] **Step 4: Schedule the job with Sidekiq's built-in scheduler**

Create `config/initializers/sidekiq_scheduler.rb`:

```ruby
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
```

**Note:** This requires the `sidekiq-cron` gem. Add it to `Gemfile`:

```ruby
gem 'sidekiq-cron'
```

Then run:

```bash
bundle install
```

- [ ] **Step 5: Add Sidekiq worker to Procfile**

In `Procfile`, add:

```
worker: bundle exec sidekiq
```

- [ ] **Step 6: Commit**

```bash
git add app/mailers/submitter_mailer.rb \
        app/jobs/send_reminder_email_job.rb \
        app/jobs/check_and_send_reminders_job.rb \
        config/initializers/sidekiq_scheduler.rb \
        Gemfile Gemfile.lock Procfile
git commit -m "feat: implement automated reminder emails via Sidekiq cron job"
```

---

## Task 6: Implement Company Logo Upload

**Files:**
- Modify: `app/models/account.rb` — add `has_one_attached :logo`
- Create: `db/migrate/TIMESTAMP_add_logo_to_accounts.rb` — (only needed if your ActiveStorage setup requires it — it typically doesn't since attachments are polymorphic)
- Modify: `app/views/personalization_settings/_logo_form.html.erb` — replace placeholder render with real form
- Modify: `app/controllers/personalization_settings_controller.rb` — add logo handling action
- Modify: `config/routes.rb` — add logo upload route

ActiveStorage is already configured (users have `has_one_attached :signature`). Adding `has_one_attached :logo` to Account requires no migration.

- [ ] **Step 1: Add logo attachment to Account model**

In `app/models/account.rb`, after `attribute :locale, :string, default: 'en-US'`, add:

```ruby
  has_one_attached :logo
```

- [ ] **Step 2: Implement the logo form view**

Replace the entire content of `app/views/personalization_settings/_logo_form.html.erb` with:

```erb
<div class="mt-2 space-y-4">
  <% logo_attachment = current_account.logo %>
  <% if logo_attachment.attached? %>
    <div class="flex items-center gap-4">
      <%= image_tag rails_blob_url(logo_attachment), class: 'h-16 max-w-xs object-contain rounded border border-base-300', alt: 'Company logo' %>
      <%= button_to t('remove'), settings_personalization_logo_path, method: :delete,
            class: 'btn btn-sm btn-outline btn-error',
            data: { turbo_confirm: t('are_you_sure_') } %>
    </div>
  <% end %>
  <%= form_with url: settings_personalization_logo_path, method: :post,
        html: { enctype: 'multipart/form-data', class: 'space-y-2' } do |f| %>
    <div class="form-control">
      <%= f.label :logo, logo_attachment.attached? ? t('replace_logo') : t('upload_logo'),
            class: 'label font-medium' %>
      <%= f.file_field :logo, accept: 'image/png,image/jpeg,image/gif,image/svg+xml',
            class: 'file-input file-input-bordered w-full max-w-xs' %>
    </div>
    <div>
      <%= f.submit t('save'), class: 'base-button' %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Add logo controller actions**

Create `app/controllers/personalization_logo_controller.rb`:

```ruby
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
```

- [ ] **Step 4: Add the logo route**

In `config/routes.rb`, inside the `namespace :settings` block, add:

```ruby
    resource :personalization_logo, only: %i[create destroy],
             path: 'personalization/logo', controller: 'personalization_logo'
```

- [ ] **Step 5: Add translation keys**

Add the following to `config/locales/en.yml` (or the appropriate locale file — find it with `find config/locales -name "en.yml"`):

```yaml
  upload_logo: "Upload Logo"
  replace_logo: "Replace Logo"
```

- [ ] **Step 6: Verify in browser**

Start the server and navigate to Settings → Personalization. The "Company Logo" section should now show a file upload input instead of the upgrade notice.

```bash
bundle exec rails s
```

- [ ] **Step 7: Commit**

```bash
git add app/models/account.rb \
        app/views/personalization_settings/_logo_form.html.erb \
        app/controllers/personalization_logo_controller.rb \
        config/routes.rb \
        config/locales/
git commit -m "feat: implement company logo upload in personalization settings"
```

---

## Task 7: Implement Bulk Send from Spreadsheet

**Files:**
- Modify: `app/views/submissions/_list_form.html.erb` — replace placeholder with real upload form
- Create: `app/controllers/submissions_bulk_controller.rb`
- Modify: `config/routes.rb` — add bulk send route

The `rubyXL` and `csv` gems are already in the Gemfile. The `Submission` model already has `source: 'bulk'`. The existing `Submissions.create_from_emails` method handles multi-email creation.

- [ ] **Step 1: Replace list form with real upload form**

Replace the entire content of `app/views/submissions/_list_form.html.erb` with:

```erb
<%= form_with url: template_submissions_bulk_index_path(template), method: :post,
      html: { enctype: 'multipart/form-data', class: 'space-y-4', data: { turbo_frame: :_top } } do |f| %>
  <div class="form-control">
    <label class="label">
      <span class="label-text font-medium"><%= t('upload_excel_or_csv_file') %></span>
    </label>
    <%= f.file_field :spreadsheet, accept: '.xlsx,.csv',
          class: 'file-input file-input-bordered w-full', required: true %>
    <label class="label">
      <span class="label-text-alt text-xs text-gray-500">
        <%= t('first_row_must_be_headers_with_email_column') %>
      </span>
    </label>
  </div>
  <div class="form-control">
    <%= f.submit button_title(title: t('send'), disabled_with: t('sending')),
          class: 'base-button w-full' %>
  </div>
<% end %>
```

- [ ] **Step 2: Create the bulk send controller**

Create `app/controllers/submissions_bulk_controller.rb`:

```ruby
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
                notice: I18n.t('n_recipients_have_been_added', count: submissions.size)
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
        CSV.parse(content, headers: true)
      else
        workbook = RubyXL::Parser.parse_buffer(StringIO.new(content))
        sheet = workbook.worksheets.first
        headers = sheet[0].cells.map { |c| c&.value.to_s.downcase.strip }
        sheet.drop(1).map do |row|
          next unless row

          headers.zip(row.cells.map { |c| c&.value.to_s }).to_h
        end.compact
      end

    email_column = rows.first&.headers&.find { |h| h.to_s.match?(/email/i) } if rows.respond_to?(:first)
    email_column ||= rows.first&.keys&.find { |k| k.to_s.match?(/email/i) }

    return [] if email_column.blank?

    rows.filter_map { |row| row[email_column].to_s.strip.presence }.select do |email|
      email.match?(User::EMAIL_REGEXP)
    end.uniq
  end
end
```

- [ ] **Step 3: Add bulk send route**

In `config/routes.rb`, inside the `resources :templates` block (find the nested resources under templates), add:

```ruby
      resources :submissions_bulk, only: %i[create], path: 'submissions/bulk'
```

- [ ] **Step 4: Add translation keys**

In the appropriate locale file, add:

```yaml
  upload_excel_or_csv_file: "Upload Excel (.xlsx) or CSV file"
  first_row_must_be_headers_with_email_column: "First row must be headers. Must include an 'Email' column."
  no_valid_emails_found_in_file: "No valid email addresses found in the file"
  n_recipients_have_been_added:
    one: "1 recipient has been added"
    other: "%{count} recipients have been added"
```

- [ ] **Step 5: Test bulk send manually**

Create a test CSV file:

```csv
Email,Name
test1@example.com,Test User 1
test2@example.com,Test User 2
```

Navigate to a template → Add Recipients → Upload List tab. Upload the CSV and verify submissions are created.

- [ ] **Step 6: Commit**

```bash
git add app/views/submissions/_list_form.html.erb \
        app/controllers/submissions_bulk_controller.rb \
        config/routes.rb \
        config/locales/
git commit -m "feat: implement bulk send from CSV/XLSX spreadsheet"
```

---

## Task 8: Fix Embed Scripts in Development Mode

**Files:**
- Modify: `app/controllers/embed_scripts_controller.rb`

In production, `Docuseal::CDN_URL` points to `https://cdn.docuseal.com` so embed scripts are loaded from DocuSeal's real CDN. This task fixes development mode where `CDN_URL = 'http://localhost:3000'`, causing the `/js/form.js` route to return the dummy script.

- [ ] **Step 1: Serve compiled webpack output from embed scripts controller**

Replace the content of `app/controllers/embed_scripts_controller.rb` with:

```ruby
# frozen_string_literal: true

class EmbedScriptsController < ActionController::Metal
  include ActionController::Head

  def show
    filename = params[:filename]

    manifest_path = Rails.public_path.join('packs', 'manifest.json')

    if manifest_path.exist?
      manifest = JSON.parse(manifest_path.read)
      base_name = filename.sub(/\.js$/, '')

      pack_key = manifest.keys.find { |k| k.start_with?("js/#{base_name}-") || k == "js/#{base_name}.js" }

      if pack_key
        js_path = Rails.public_path.join('packs', pack_key.sub(%r{^js/}, ''))

        if js_path.exist?
          headers['Content-Type'] = 'application/javascript'
          headers['Cache-Control'] = 'public, max-age=86400'
          self.response_body = js_path.read
          self.status = 200
          return
        end
      end
    end

    self.response_body = ''
    self.status = 404
  end
end
```

- [ ] **Step 2: Build the webpack assets in development**

```bash
bundle exec rails assets:precompile
```

Or start the dev server: `yarn shakapacker-dev-server` compiles on demand.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/embed_scripts_controller.rb
git commit -m "feat: serve real webpack-compiled embed scripts in development mode"
```

---

## Task 9: Implement SMS Settings Form (requires Twilio/Vonage account)

**Files:**
- Modify: `app/views/sms_settings/index.html.erb` — replace placeholder with config form
- Modify: `app/controllers/sms_settings_controller.rb` — add create/update action
- Modify: `app/views/submissions/_send_sms.html.erb` — replace placeholder with real SMS checkbox
- Modify: `app/views/submissions/_send_sms_button.html.erb` — replace upgrade link with real button

**Prerequisites:** Twilio or Vonage account with API credentials. The form will save credentials to `EncryptedConfig` under key `'sms_configs'`.

- [ ] **Step 1: Implement SMS settings view**

Replace the content of `app/views/sms_settings/index.html.erb` with:

```erb
<div class="flex flex-wrap space-y-4 md:flex-nowrap md:space-y-0">
  <%= render 'shared/settings_nav' %>
  <div class="flex-grow max-w-xl mx-auto">
    <h1 class="text-4xl font-bold mb-4">SMS</h1>
    <% sms_config = @encrypted_config.value || {} %>
    <%= form_with url: settings_sms_index_path, method: :post, html: { class: 'space-y-4' } do |f| %>
      <div class="form-control">
        <%= label_tag :provider, 'SMS Provider', class: 'label font-medium' %>
        <%= select_tag :provider, options_for_select([['Twilio', 'twilio'], ['Vonage', 'vonage']], sms_config['provider']),
              class: 'base-select', include_blank: 'Select provider' %>
      </div>
      <div class="form-control">
        <%= label_tag :account_sid, 'Account SID / API Key', class: 'label font-medium' %>
        <%= text_field_tag :account_sid, sms_config['account_sid'],
              class: 'base-input w-full', placeholder: 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' %>
      </div>
      <div class="form-control">
        <%= label_tag :auth_token, 'Auth Token / API Secret', class: 'label font-medium' %>
        <%= password_field_tag :auth_token, sms_config['auth_token'],
              class: 'base-input w-full', placeholder: '••••••••' %>
      </div>
      <div class="form-control">
        <%= label_tag :from_number, 'From Phone Number', class: 'label font-medium' %>
        <%= text_field_tag :from_number, sms_config['from_number'],
              class: 'base-input w-full', placeholder: '+1234567890' %>
      </div>
      <div>
        <%= submit_tag 'Save', class: 'base-button' %>
      </div>
    <% end %>
  </div>
  <div class="w-0 md:w-52"></div>
</div>
```

- [ ] **Step 2: Add create action to SmsSettingsController**

Replace `app/controllers/sms_settings_controller.rb` with:

```ruby
# frozen_string_literal: true

class SmsSettingsController < ApplicationController
  before_action :load_encrypted_config
  authorize_resource :encrypted_config, only: :index
  authorize_resource :encrypted_config, parent: false, except: :index

  def index; end

  def create
    value = @encrypted_config.value || {}
    value['provider'] = params[:provider] if params[:provider].present?
    value['account_sid'] = params[:account_sid] if params[:account_sid].present?
    value['auth_token'] = params[:auth_token] if params[:auth_token].present?
    value['from_number'] = params[:from_number] if params[:from_number].present?

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
      EncryptedConfig.find_or_initialize_by(account: current_account, key: 'sms_configs')
  end
end
```

- [ ] **Step 3: Add create route for SMS settings**

In `config/routes.rb`, find `resources :sms, only: %i[index]` and change to:

```ruby
      resources :sms, only: %i[index create], controller: 'sms_settings'
```

- [ ] **Step 4: Replace the SMS checkbox in the phone send form**

Replace the content of `app/views/submissions/_send_sms.html.erb` with:

```erb
<div class="form-control mt-2">
  <% sms_configured = EncryptedConfig.exists?(account: current_account, key: 'sms_configs') %>
  <% if sms_configured %>
    <label class="flex items-center gap-2 cursor-pointer">
      <%= check_box_tag 'send_sms', '1', false, class: 'checkbox' %>
      <span><%= t('send_sms') %></span>
    </label>
  <% else %>
    <div class="text-sm text-gray-500">
      <%= link_to t('configure_sms_to_send_via_phone'), settings_sms_index_path, class: 'link' %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 5: Replace the SMS resend button with a real form**

Replace the content of `app/views/submissions/_send_sms_button.html.erb` with:

```erb
<div class="mt-2 mb-1">
  <% sms_configured = EncryptedConfig.exists?(account: current_account, key: 'sms_configs') %>
  <% if sms_configured %>
    <%= button_to submitter.sent_at? ? t('re_send_sms') : t('send_sms'),
          submitter_path(submitter),
          method: :patch,
          params: { submitter: { phone: submitter.phone }, send_sms: '1' },
          class: 'btn btn-sm btn-primary w-full' %>
  <% else %>
    <div class="tooltip w-full" data-tip="<%= t('configure_sms_settings_first') %>">
      <%= link_to t('send_sms'), settings_sms_index_path,
            class: 'btn btn-sm btn-ghost w-full' %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 6: Implement SendSubmitterInvitationSmsJob**

Create `app/jobs/send_submitter_invitation_sms_job.rb`:

```ruby
# frozen_string_literal: true

class SendSubmitterInvitationSmsJob
  include Sidekiq::Job

  def perform(params = {})
    submitter = Submitter.find_by(id: params['submitter_id'])

    return unless submitter
    return if submitter.phone.blank?
    return if submitter.completed_at?

    sms_config = EncryptedConfig.find_by(account: submitter.account, key: 'sms_configs')&.value

    return if sms_config.blank?

    message = build_sms_message(submitter)

    send_sms(sms_config, to: submitter.phone, body: message)

    submitter.submission_events.create!(
      event_type: 'send_sms',
      account_id: submitter.account_id,
      data: {}
    )
  end

  private

  def build_sms_message(submitter)
    template_name = submitter.submission.template&.name || 'document'
    link = ReplaceEmailVariables.build_submitter_link(submitter)

    "You've been invited to sign #{template_name}. Open the link to continue: #{link}"
  end

  def send_sms(config, to:, body:)
    provider = config['provider']

    case provider
    when 'twilio'
      send_via_twilio(config, to:, body:)
    when 'vonage'
      send_via_vonage(config, to:, body:)
    else
      raise "Unknown SMS provider: #{provider}"
    end
  end

  def send_via_twilio(config, to:, body:)
    require 'net/http'
    require 'uri'

    uri = URI("https://api.twilio.com/2010-04-01/Accounts/#{config['account_sid']}/Messages.json")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request.basic_auth(config['account_sid'], config['auth_token'])
    request.set_form_data('To' => to, 'From' => config['from_number'], 'Body' => body)

    response = http.request(request)

    raise "Twilio error: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
  end

  def send_via_vonage(config, to:, body:)
    require 'net/http'
    require 'json'

    uri = URI('https://rest.nexmo.com/sms/json')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = {
      api_key: config['account_sid'],
      api_secret: config['auth_token'],
      to: to.gsub(/\D/, ''),
      from: config['from_number'],
      text: body
    }.to_json

    response = http.request(request)

    raise "Vonage error: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
  end
end
```

- [ ] **Step 7: Commit**

```bash
git add app/views/sms_settings/index.html.erb \
        app/controllers/sms_settings_controller.rb \
        app/views/submissions/_send_sms.html.erb \
        app/views/submissions/_send_sms_button.html.erb \
        app/jobs/send_submitter_invitation_sms_job.rb \
        config/routes.rb
git commit -m "feat: implement SMS settings form and SendSubmitterInvitationSmsJob with Twilio/Vonage"
```

---

## Task 10: Implement SSO / SAML (requires Identity Provider)

**Files:**
- Modify: `Gemfile` — add `ruby-saml`
- Modify: `app/views/sso_settings/index.html.erb` — implement real SAML config form
- Modify: `app/controllers/sso_settings_controller.rb` — add create action
- Create: `app/controllers/saml_sessions_controller.rb` — SAML auth flow
- Modify: `config/routes.rb` — add SAML routes

**Prerequisites:** An IdP (Okta, Azure AD, Google Workspace, etc.) that can issue SAML assertions. You'll need the IdP's metadata XML or SSO URL + certificate.

- [ ] **Step 1: Add ruby-saml gem**

In `Gemfile`, add:

```ruby
gem 'ruby-saml'
```

Run:

```bash
bundle install
```

- [ ] **Step 2: Implement SAML config form**

Replace the content of `app/views/sso_settings/index.html.erb` with:

```erb
<div class="flex flex-wrap space-y-4 md:flex-nowrap md:space-y-0">
  <%= render 'shared/settings_nav' %>
  <div class="flex-grow max-w-xl mx-auto">
    <h1 class="text-4xl font-bold mb-4">SAML SSO</h1>
    <% saml_config = @encrypted_config.value || {} %>
    <div class="mb-6 p-4 bg-base-200 rounded-lg text-sm">
      <p class="font-medium mb-2"><%= t('service_provider_details') %>:</p>
      <p><strong>Entity ID:</strong> <%= request.base_url %>/saml/metadata</p>
      <p><strong>ACS URL:</strong> <%= request.base_url %>/saml/acs</p>
    </div>
    <%= form_with url: settings_sso_index_path, method: :post, html: { class: 'space-y-4' } do |f| %>
      <div class="form-control">
        <%= label_tag :idp_sso_target_url, 'IdP SSO URL', class: 'label font-medium' %>
        <%= text_field_tag :idp_sso_target_url, saml_config['idp_sso_target_url'],
              class: 'base-input w-full', placeholder: 'https://your-idp.com/sso/saml' %>
      </div>
      <div class="form-control">
        <%= label_tag :idp_entity_id, 'IdP Entity ID', class: 'label font-medium' %>
        <%= text_field_tag :idp_entity_id, saml_config['idp_entity_id'],
              class: 'base-input w-full' %>
      </div>
      <div class="form-control">
        <%= label_tag :idp_cert, 'IdP Certificate (X.509)', class: 'label font-medium' %>
        <%= text_area_tag :idp_cert, saml_config['idp_cert'],
              class: 'base-textarea w-full', rows: 6,
              placeholder: "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----" %>
      </div>
      <div>
        <%= submit_tag t('save'), class: 'base-button' %>
      </div>
    <% end %>
    <% if saml_config['idp_sso_target_url'].present? %>
      <div class="mt-6 p-4 bg-base-200 rounded-lg">
        <%= link_to 'Test SSO Login', '/saml/init', class: 'btn btn-primary btn-sm', data: { turbo: false } %>
      </div>
    <% end %>
    <% if can?(:manage, :saml_sso) %>
      <% account_config = AccountConfig.find_or_initialize_by(account: current_account, key: AccountConfig::FORCE_SSO_AUTH_KEY) %>
      <%= form_for account_config, url: account_configs_path, method: :post, html: { class: 'mt-6' } do |f| %>
        <%= f.hidden_field :key %>
        <div class="flex items-center justify-between">
          <span><%= t('force_sso_login') %></span>
          <submit-form data-on="change">
            <%= f.check_box :value, class: 'toggle', checked: account_config.value == true %>
          </submit-form>
        </div>
      <% end %>
    <% end %>
  </div>
  <div class="w-0 md:w-52"></div>
</div>
```

- [ ] **Step 3: Add create action to SsoSettingsController**

Replace `app/controllers/sso_settings_controller.rb` with:

```ruby
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
```

- [ ] **Step 4: Create SAML sessions controller**

Create `app/controllers/saml_sessions_controller.rb`:

```ruby
# frozen_string_literal: true

class SamlSessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_authorization_check

  def init
    saml_config = load_saml_config
    return redirect_to root_path, alert: 'SSO is not configured' unless saml_config

    settings = build_saml_settings(saml_config)
    request = OneLogin::RubySaml::Authrequest.new
    redirect_to request.create(settings), allow_other_host: true
  end

  def acs
    saml_config = load_saml_config
    return redirect_to root_path, alert: 'SSO is not configured' unless saml_config

    settings = build_saml_settings(saml_config)
    response = OneLogin::RubySaml::Response.new(params[:SAMLResponse], settings:)

    if response.is_valid?
      email = response.attributes['email'] || response.attributes['emailAddress'] ||
              response.nameid

      user = User.active.find_by(email: email.to_s.downcase.strip)

      if user
        sign_in user
        redirect_to root_path
      else
        redirect_to root_path, alert: "No account found for #{email}"
      end
    else
      redirect_to root_path, alert: "SSO authentication failed: #{response.errors.join(', ')}"
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
```

- [ ] **Step 5: Add SAML routes and update SSO settings route**

In `config/routes.rb`, find `resources :sso, only: %i[index]` and change to:

```ruby
      resources :sso, only: %i[index create], controller: 'sso_settings'
```

Also add SAML routes at the top level (outside `namespace :settings`):

```ruby
  get '/saml/init', to: 'saml_sessions#init', as: :saml_init
  post '/saml/acs', to: 'saml_sessions#acs', as: :saml_acs
  get '/saml/metadata', to: 'saml_sessions#metadata', as: :saml_metadata
```

- [ ] **Step 6: Commit**

```bash
bundle install
git add Gemfile Gemfile.lock \
        app/views/sso_settings/index.html.erb \
        app/controllers/sso_settings_controller.rb \
        app/controllers/saml_sessions_controller.rb \
        config/routes.rb
git commit -m "feat: implement SAML SSO configuration and authentication flow"
```

---

## Task 11: Stripe Payment Backend (requires Stripe account)

**Files:**
- Create: `app/controllers/api/stripe_payments_controller.rb`
- Modify: `config/routes.rb` — add stripe_payments routes
- Modify: `app/views/personalization_settings/show.html.erb` — add Stripe key config section

The Vue frontend (`payment_step.vue`) already calls `GET /api/stripe_payments/:id` (to check session status) and `POST /api/stripe_payments` (to create a checkout session). We need to implement these endpoints.

**Prerequisites:** A Stripe account with API keys. Store the secret key in `EncryptedConfig`.

- [ ] **Step 1: Add stripe gem to Gemfile**

```ruby
gem 'stripe'
```

```bash
bundle install
```

- [ ] **Step 2: Add Stripe key configuration to EncryptedConfig constants**

In `app/models/encrypted_config.rb`, add:

```ruby
  STRIPE_SECRET_KEY = 'stripe_secret_key'
```

- [ ] **Step 3: Add a Stripe config section to settings**

In `app/views/personalization_settings/show.html.erb`, before the last `<div>` closure, add:

```erb
    <p class="text-4xl font-bold mb-4 mt-8">
      Stripe Payments
    </p>
    <% stripe_config = EncryptedConfig.find_or_initialize_by(account: current_account, key: 'stripe_configs') %>
    <%= form_with url: settings_personalization_stripe_path, method: :post, html: { class: 'space-y-4' } do |f| %>
      <div class="form-control">
        <%= label_tag :secret_key, 'Stripe Secret Key', class: 'label font-medium' %>
        <%= password_field_tag :secret_key, stripe_config.value&.dig('secret_key'),
              class: 'base-input w-full', placeholder: 'sk_live_...' %>
      </div>
      <div>
        <%= submit_tag t('save'), class: 'base-button' %>
      </div>
    <% end %>
```

- [ ] **Step 4: Create Stripe payments API controller**

Create `app/controllers/api/stripe_payments_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  class StripePaymentsController < ApiBaseController
    skip_authorization_check

    def show
      stripe_key = load_stripe_key
      return render json: { error: 'Stripe not configured' }, status: :unprocessable_content unless stripe_key

      Stripe.api_key = stripe_key
      session = Stripe::Checkout::Session.retrieve(params[:id])

      render json: {
        id: session.id,
        status: session.status,
        payment_status: session.payment_status
      }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    def create
      stripe_key = load_stripe_key
      return render json: { error: 'Stripe not configured' }, status: :unprocessable_content unless stripe_key

      submitter = Submitter.find_by(slug: params[:submitter_slug])
      return render json: { error: 'Not found' }, status: :not_found unless submitter

      field = submitter.submission.template.fields.find { |f| f['uuid'] == params[:field_uuid] }
      return render json: { error: 'Field not found' }, status: :not_found unless field

      Stripe.api_key = stripe_key

      session_params = build_session_params(field, submitter, params[:success_url])
      session = Stripe::Checkout::Session.create(session_params)

      render json: { url: session.url, id: session.id }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    def load_stripe_key
      EncryptedConfig.find_by(account: current_account, key: 'stripe_configs')&.value&.dig('secret_key')
    end

    def build_session_params(field, submitter, success_url)
      preferences = field['preferences'] || {}
      amount_cents = (preferences['price'].to_f * 100).to_i
      currency = (preferences['currency'] || 'USD').downcase

      {
        mode: 'payment',
        success_url: "#{success_url}?stripe_session_id={CHECKOUT_SESSION_ID}",
        cancel_url: success_url,
        line_items: [{
          quantity: 1,
          price_data: {
            currency:,
            unit_amount: amount_cents,
            product_data: {
              name: field['name'] || 'Payment'
            }
          }
        }],
        metadata: {
          submitter_slug: submitter.slug,
          field_uuid: field['uuid']
        }
      }
    end
  end
end
```

- [ ] **Step 5: Add Stripe routes**

In `config/routes.rb`, inside `namespace :api`, add:

```ruby
    resources :stripe_payments, only: %i[show create]
```

Also add a route for saving Stripe config under settings:

```ruby
    resource :personalization_stripe, only: %i[create], path: 'personalization/stripe'
```

- [ ] **Step 6: Create Stripe config controller**

Create `app/controllers/personalization_stripe_controller.rb`:

```ruby
# frozen_string_literal: true

class PersonalizationStripeController < ApplicationController
  def create
    authorize!(:manage, current_account)

    config = EncryptedConfig.find_or_initialize_by(account: current_account, key: 'stripe_configs')
    config.value = { 'secret_key' => params[:secret_key].to_s.strip }
    config.save!

    redirect_back fallback_location: settings_personalization_path,
                  notice: I18n.t('settings_have_been_saved')
  end
end
```

- [ ] **Step 7: Commit**

```bash
bundle install
git add Gemfile Gemfile.lock \
        app/controllers/api/stripe_payments_controller.rb \
        app/controllers/personalization_stripe_controller.rb \
        app/views/personalization_settings/show.html.erb \
        config/routes.rb
git commit -m "feat: implement Stripe payment backend for payment field type"
```

---

## Self-Review

### Spec Coverage Check

| Feature | Task | Status |
|---|---|---|
| Unlimited signature requests | Already unlimited in self-hosted (limit=nil) | ✅ No code needed |
| Company logo | Task 6 | ✅ Covered |
| Connect own email | Already works (email SMTP settings) | ✅ No code needed |
| Personalize email content | Already works (email template config) | ✅ No code needed |
| Automated reminders | Tasks 4 + 5 | ✅ Covered |
| Accept payments | Task 11 | ✅ Covered |
| Zapier and Webhooks | Already fully functional | ✅ No code needed |
| User roles and teams | Task 3 | ✅ Covered |
| Bulk send from spreadsheet | Task 7 | ✅ Covered |
| SSO / SAML | Task 10 | ✅ Covered |
| Identity verification via SMS | Task 9 | ✅ Covered |
| API and Embedding | Task 1 (abilities) + Task 8 (dev mode scripts) | ✅ Covered |

### Placeholder Scan

- Task 4: `_reminder_banner.html.erb` cleared ✅
- Task 6: `_logo_form.html.erb` replaced ✅
- Task 7: `_list_form.html.erb` replaced ✅
- Task 9: `_send_sms.html.erb` and `sms_settings/index.html.erb` replaced ✅
- Task 10: `sso_settings/index.html.erb` replaced ✅
- Remaining: `sms_settings/_placeholder.html.erb` itself — can be deleted after Task 9 makes it unused

### Notes on External Dependencies

Tasks 9 (SMS), 10 (SSO/SAML), and 11 (Payments) require external service accounts:
- **SMS**: Twilio or Vonage account with a phone number
- **SSO/SAML**: An identity provider (Okta, Azure AD, Google Workspace, etc.)
- **Stripe Payments**: A Stripe account in live or test mode

These features are fully unlocked in the UI and backend — you just need to enter credentials in Settings to activate them.
