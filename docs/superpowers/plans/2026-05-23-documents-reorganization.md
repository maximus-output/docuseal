# Documents Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the split "Templates / Submissions" dashboard with a unified "Documents" view that shows sent documents (submissions) and unsent drafts (templates with no submissions) in one place, with folder support, matching the UX of DocuSign/HelloSign.

**Architecture:** Add a new `DocumentsController` that queries submissions + zero-submission draft templates, optionally scoped by `folder_id`. Update the root redirect and navbar to point to `/documents`. The underlying data model (Template → Submission → Submitter) stays unchanged.

**Tech Stack:** Ruby on Rails 8, CanCan authorization, Pagy pagination, DaisyUI/Tailwind CSS, Hotwire Turbo, `load_and_authorize_resource` for scoping

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `app/controllers/documents_controller.rb` | Create | Unified query: submissions + draft templates + folder cards |
| `app/views/documents/index.html.erb` | Create | Documents page: folders → sent docs → drafts |
| `app/views/template_folders/_folder.html.erb` | Modify | Accept optional `documents_mode` local to link into documents view |
| `config/routes.rb` | Modify | Add `resources :documents, only: %i[index]` |
| `app/controllers/dashboard_controller.rb` | Modify | Redirect signed-in users to `documents_path` |
| `app/views/shared/_navbar.html.erb` | Modify | Add "Documents" nav link; remove toggle widget reference |
| `app/controllers/submissions_controller.rb` | Modify | Redirect to `documents_path` after `create` and `destroy` |
| `app/views/submissions_dashboard/index.html.erb` | Modify | Change "Create" button to link to `new_template_path` with "New Document" label |
| `app/views/templates_dashboard/index.html.erb` | Modify | Change "Create" button label to "New Document" |

---

## Task 1: Add Route and DocumentsController

**Files:**
- Create: `app/controllers/documents_controller.rb`
- Modify: `config/routes.rb`

### Why
The unified view needs its own controller that queries both submissions and draft templates and respects the `folder_id` param. We reuse the existing CanCan `load_and_authorize_resource` pattern for `Submission` and `Template` to get properly scoped base relations.

- [ ] **Step 1: Add route**

Open `config/routes.rb`. Inside the `resources :submissions, only: %i[index], controller: 'submissions_dashboard'` area (around line 72), add immediately before that line:

```ruby
resources :documents, only: %i[index]
```

The routes file already has `resources :submissions, only: %i[index], controller: 'submissions_dashboard'` on line 72 and `resources :templates, only: %i[index], controller: 'templates_dashboard'` on line 98. Add the documents route near the top of the non-namespaced resources, around line 62 after `resources :dashboard, only: %i[index]`:

```ruby
resources :documents, only: %i[index]
```

- [ ] **Step 2: Create DocumentsController**

Create `app/controllers/documents_controller.rb`:

```ruby
# frozen_string_literal: true

class DocumentsController < ApplicationController
  load_and_authorize_resource :submission, parent: false
  load_and_authorize_resource :template, parent: false

  DRAFTS_LIMIT = 12

  def index
    @current_folder = params[:folder_id].present? ? current_account.template_folders.find(params[:folder_id]) : nil

    load_folders
    load_submissions
    load_draft_templates
  end

  private

  def load_folders
    base_folders = @template_folders_scope
    if @current_folder
      @template_folders = @current_folder.subfolders
                                         .where(id: Template.accessible_by(current_ability).active.select(:folder_id))
    else
      all_templates = Template.accessible_by(current_ability)
      @template_folders = TemplateFolders.filter_active_folders(
        base_folders.where(parent_folder_id: nil),
        all_templates
      )
    end

    @template_folders = TemplateFolders.search(@template_folders, params[:q])
  end

  def load_submissions
    rel = @submissions.left_joins(:template)
                      .where(archived_at: nil)
                      .where(templates: { archived_at: nil })
                      .preload(:template_accesses, :created_by_user, template: :author)

    if @current_folder
      folder_ids = [@current_folder.id] + @current_folder.subfolders.pluck(:id)
      template_ids = Template.active.where(folder_id: folder_ids).select(:id)
      rel = rel.where(template_id: template_ids)
    end

    rel = Submissions.search(current_user, rel, params[:q], search_template: true)
    rel = rel.order(id: :desc)

    @pagy, @submissions = pagy_auto(rel.preload(submitters: :start_form_submission_events))
  end

  def load_draft_templates
    rel = @templates.active
                    .where.missing(:submissions)
                    .preload(:author, :template_accesses)

    folder_id = if @current_folder
                  @current_folder.id
                else
                  current_account.default_template_folder.id
                end
    rel = rel.where(folder_id:)

    rel = Templates.search(current_user, rel, params[:q]) if params[:q].present?

    @draft_templates = rel.order(created_at: :desc).limit(DRAFTS_LIMIT)
  end

  def template_folders_scope
    TemplateFolder.accessible_by(current_ability)
  end

  def @template_folders_scope
    TemplateFolder.accessible_by(current_ability)
  end
end
```

Wait — `load_and_authorize_resource` for TemplateFolder doesn't work with `parent: false` unless we define it. Since DocumentsController doesn't have `load_and_authorize_resource :template_folder`, we'll just query directly. Replace the controller body above with:

```ruby
# frozen_string_literal: true

class DocumentsController < ApplicationController
  load_and_authorize_resource :submission, parent: false
  load_and_authorize_resource :template, parent: false

  DRAFTS_LIMIT = 12

  def index
    @current_folder = load_current_folder
    load_folders
    load_submissions
    load_draft_templates
  end

  private

  def load_current_folder
    return if params[:folder_id].blank?

    current_account.template_folders.find(params[:folder_id])
  end

  def load_folders
    if @current_folder
      @template_folders = @current_folder.subfolders
                                         .where(id: Template.accessible_by(current_ability).active.select(:folder_id))
    else
      all_templates = Template.accessible_by(current_ability)
      base = TemplateFolder.accessible_by(current_ability).where(parent_folder_id: nil)
      @template_folders = TemplateFolders.filter_active_folders(base, all_templates)
    end

    @template_folders = TemplateFolders.search(@template_folders, params[:q])
  end

  def load_submissions
    rel = @submissions.left_joins(:template)
                      .where(archived_at: nil)
                      .where(templates: { archived_at: nil })
                      .preload(:template_accesses, :created_by_user, template: :author)

    if @current_folder
      folder_ids = [@current_folder.id] + @current_folder.subfolders.pluck(:id)
      rel = rel.where(template_id: Template.active.where(folder_id: folder_ids).select(:id))
    end

    rel = Submissions.search(current_user, rel, params[:q], search_template: true)
    rel = rel.order(id: :desc)

    @pagy, @submissions = pagy_auto(rel.preload(submitters: :start_form_submission_events))
  end

  def load_draft_templates
    folder_id = @current_folder&.id || current_account.default_template_folder.id
    rel = @templates.active
                    .where.missing(:submissions)
                    .where(folder_id:)
                    .preload(:author, :template_accesses)

    rel = Templates.search(current_user, rel, params[:q]) if params[:q].present?

    @draft_templates = rel.order(created_at: :desc).limit(DRAFTS_LIMIT)
  end
end
```

- [ ] **Step 3: Verify route exists**

```bash
cd /Users/maximusjb/Repos/docuseal && mise exec -- bundle exec rails routes | grep documents
```

Expected output includes:
```
documents  GET  /documents(.:format)  documents#index
```

- [ ] **Step 4: Smoke-test controller loads**

```bash
cd /Users/maximusjb/Repos/docuseal && mise exec -- bundle exec ruby -e "require_relative 'config/environment'; puts DocumentsController.ancestors.include?(ApplicationController)"
```

Expected: `true`

- [ ] **Step 5: Commit**

```bash
git add app/controllers/documents_controller.rb config/routes.rb
git commit -m "feat: add DocumentsController with unified submissions + draft templates query"
```

---

## Task 2: Documents Index View

**Files:**
- Create: `app/views/documents/index.html.erb`
- Modify: `app/views/template_folders/_folder.html.erb`

### Why
The view needs to show three sections in order: (1) subfolders, (2) sent documents (submissions), (3) unsent drafts (templates with no submissions). The folder partial needs a `documents_mode` local so the link targets `/documents?folder_id=` instead of `/folders/:id`.

- [ ] **Step 1: Update folder partial to accept documents_mode**

Open `app/views/template_folders/_folder.html.erb`. The current `<a href>` is:

```erb
<a href="<%= folder_path(folder) %>" class="flex h-full ...">
```

Change it to:

```erb
<% folder_href = local_assigns[:documents_mode] ? documents_path(folder_id: folder.id) : folder_path(folder) %>
<a href="<%= folder_href %>" class="flex h-full flex-col justify-between rounded-2xl py-5 px-6 w-full bg-base-200 before:border-2 before:border-base-300 before:border-dashed before:absolute before:left-0 before:right-0 before:top-0 before:bottom-0 before:hidden before:rounded-2xl relative" data-targets="dashboard-dropzone.folderCards" data-full-name="<%= folder.full_name %>">
  <% if !is_long %>
    <%= svg_icon('folder', class: 'w-6 h-6') %>
  <% end %>
  <div class="text-lg font-semibold mt-1" style="overflow: hidden; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: <%= is_long ? 2 : 1 %>;">
    <% if is_long %>
      <%= svg_icon('folder', class: 'w-6 h-6 inline') %>
    <% end %>
    <%= folder.name %>
  </div>
</a>
```

Full file after edit:

```erb
<% is_long = folder.name.size > 32 %>
<% folder_href = local_assigns[:documents_mode] ? documents_path(folder_id: folder.id) : folder_path(folder) %>
<a href="<%= folder_href %>" class="flex h-full flex-col justify-between rounded-2xl py-5 px-6 w-full bg-base-200 before:border-2 before:border-base-300 before:border-dashed before:absolute before:left-0 before:right-0 before:top-0 before:bottom-0 before:hidden before:rounded-2xl relative" data-targets="dashboard-dropzone.folderCards" data-full-name="<%= folder.full_name %>">
  <% if !is_long %>
    <%= svg_icon('folder', class: 'w-6 h-6') %>
  <% end %>
  <div class="text-lg font-semibold mt-1" style="overflow: hidden; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: <%= is_long ? 2 : 1 %>;">
    <% if is_long %>
      <%= svg_icon('folder', class: 'w-6 h-6 inline') %>
    <% end %>
    <%= folder.name %>
  </div>
</a>
```

- [ ] **Step 2: Create documents index view**

Create `app/views/documents/index.html.erb`:

```erb
<% if Docuseal.demo? %><%= render 'shared/demo_alert' %><% end %>
<div class="flex justify-between items-center w-full mb-4">
  <div class="flex items-center flex-grow min-w-0">
    <% if @current_folder %>
      <a href="<%= documents_path %>" class="mr-2 opacity-60 hover:opacity-100">
        <%= svg_icon('arrow_left', class: 'w-6 h-6 stroke-2') %>
      </a>
      <h1 class="text-2xl truncate md:text-3xl sm:text-4xl font-bold">
        <%= @current_folder.name %>
      </h1>
    <% else %>
      <h1 class="text-2xl truncate md:text-3xl sm:text-4xl font-bold md:block <%= 'hidden' if params[:q].present? %>">
        <%= t('documents') %>
      </h1>
    <% end %>
  </div>
  <div class="flex space-x-2">
    <% if params[:q].present? || @pagy.pages > 1 || @template_folders.present? %>
      <%= render 'shared/search_input' %>
    <% end %>
    <% if can?(:create, ::Template) %>
      <span class="hidden sm:block">
        <%= render 'templates/upload_button' %>
      </span>
      <%= link_to new_template_path, class: 'white-button !border gap-2', data: { turbo_frame: :modal } do %>
        <%= svg_icon('plus', class: 'w-6 h-6 stroke-2') %>
        <span class="hidden md:block"><%= t('new_document') %></span>
      <% end %>
    <% end %>
  </div>
</div>

<% if @template_folders.present? %>
  <div class="grid gap-4 md:grid-cols-3 mb-6">
    <%= render partial: 'template_folders/folder', collection: @template_folders, as: :folder, locals: { documents_mode: true } %>
  </div>
<% end %>

<% if @submissions.present? || (@pagy.count.present? && @pagy.count > 0) %>
  <div class="space-y-4">
    <%= render partial: 'templates/submission', collection: @submissions, locals: { with_template: true } %>
  </div>
  <% if @pagy.pages > 1 %>
    <div class="mt-4">
      <%= render 'shared/pagination', pagy: @pagy, items_name: 'submissions' %>
    </div>
  <% end %>
<% end %>

<% if @draft_templates.present? %>
  <% if @submissions.present? %>
    <h2 class="text-xl font-bold mt-8 mb-4"><%= t('drafts') %></h2>
  <% end %>
  <div class="grid gap-4 md:grid-cols-3">
    <%= render partial: 'templates/template', collection: @draft_templates %>
  </div>
<% end %>

<% if @submissions.blank? && @draft_templates.blank? && @template_folders.blank? %>
  <% if params[:q].present? %>
    <div class="text-center mt-16 text-3xl font-semibold">
      <%= t('documents_not_found') %>
    </div>
  <% else %>
    <%= render 'templates/dropzone' %>
  <% end %>
<% end %>
```

- [ ] **Step 3: Add `documents` and `new_document` and `documents_not_found` i18n keys**

Open `config/locales/en.yml`. Find the `en:` block and add:

```yaml
    documents: Documents
    new_document: New Document
    documents_not_found: No documents found
    drafts: Drafts
```

Run:
```bash
grep -n "templates_not_found\|submissions_not_found" /Users/maximusjb/Repos/docuseal/config/locales/en.yml | head -5
```
to find a good insertion point near existing similar keys.

- [ ] **Step 4: Verify view renders without crash**

Start rails server or use:
```bash
cd /Users/maximusjb/Repos/docuseal && mise exec -- bundle exec rails runner "puts ActionView::Base.new(ActionController::Base.view_paths, {}, ActionController::Base.new).render(file: 'documents/index')" 2>&1 | head -20
```

If it errors on missing partials, verify the partial paths are correct.

- [ ] **Step 5: Commit**

```bash
git add app/views/documents/ app/views/template_folders/_folder.html.erb config/locales/en.yml
git commit -m "feat: add documents index view with folders, submissions, and drafts sections"
```

---

## Task 3: Update Root and Dashboard Redirect

**Files:**
- Modify: `app/controllers/dashboard_controller.rb`

### Why
The current root (`/`) dispatches to TemplatesDashboardController or SubmissionsDashboardController based on a cookie. We want signed-in users to land on `/documents` instead. The root path still handles unauthenticated landing page rendering via `maybe_render_landing`.

- [ ] **Step 1: Update DashboardController#index to redirect to documents**

Open `app/controllers/dashboard_controller.rb`. The current `index` action is:

```ruby
def index
  if cookies.permanent[:dashboard_view] == 'submissions'
    SubmissionsDashboardController.dispatch(:index, request, response)
  else
    TemplatesDashboardController.dispatch(:index, request, response)
  end
end
```

Replace with:

```ruby
def index
  redirect_to documents_path
end
```

The before_actions (`maybe_render_landing`, `maybe_redirect_product_url`, `maybe_redirect_mfa_setup`) still run before this, so unauthenticated users get the landing page and MFA-required users get redirected to MFA setup before reaching the redirect.

Full file after change:

```ruby
# frozen_string_literal: true

class DashboardController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index]

  before_action :maybe_redirect_product_url
  before_action :maybe_render_landing
  before_action :maybe_redirect_mfa_setup

  skip_authorization_check

  def index
    redirect_to documents_path
  end

  private

  def maybe_redirect_product_url
    return if !Docuseal.multitenant? || signed_in?

    redirect_to Docuseal::PRODUCT_URL, allow_other_host: true
  end

  def maybe_redirect_mfa_setup
    return unless signed_in?
    return if current_user.otp_required_for_login

    return if !current_user.otp_required_for_login && !AccountConfig.exists?(value: true,
                                                                             account_id: current_user.account_id,
                                                                             key: AccountConfig::FORCE_MFA)

    redirect_to mfa_setup_path, notice: I18n.t('setup_2fa_to_continue')
  end

  def maybe_render_landing
    return if signed_in?

    render 'pages/landing'
  end
end
```

- [ ] **Step 2: Verify redirect works via routes**

```bash
cd /Users/maximusjb/Repos/docuseal && mise exec -- bundle exec rails routes | grep "root\|documents"
```

Expected: root points to `dashboard#index`, documents points to `documents#index`.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/dashboard_controller.rb
git commit -m "feat: redirect root to /documents for signed-in users"
```

---

## Task 4: Add Documents Link to Navbar

**Files:**
- Modify: `app/views/shared/_navbar.html.erb`

### Why
Users need a persistent "Documents" link in the top nav to get to the unified view from any page. The existing navbar has a logo/home link on the left and a dropdown on the right. We add "Documents" as a text link between them, visible to signed-in users.

- [ ] **Step 1: Add Documents nav link**

Open `app/views/shared/_navbar.html.erb`. The current structure inside `<% if signed_in? %>` has:

```erb
<div class="space-x-4 flex items-center">
  <% if Docuseal.demo? %>
    ...
  <% else %>
    <div class="flex items-center justify-center space-x-4 mr-1">
      <%= render 'shared/navbar_buttons' %>
      <button onclick="toggleDocusealTheme()" ...>
        ...
      </button>
      <%= link_to t('settings'), settings_profile_index_path, class: 'hidden md:inline-flex font-medium text-lg', id: 'account_settings_button' %>
    </div>
  <% end %>
```

Add a Documents link inside the `<% else %>` block, before the `<div class="flex items-center ...">`. Insert after `<div class="space-x-4 flex items-center">` and before `<% if Docuseal.demo? %>`:

Actually, add it inside the existing `<div class="flex items-center justify-center space-x-4 mr-1">` block, before the settings link:

```erb
<%= link_to t('documents'), documents_path, class: 'hidden md:inline-flex font-medium text-lg' %>
```

Place it immediately before the existing settings link:
```erb
<%= link_to t('settings'), settings_profile_index_path, class: 'hidden md:inline-flex font-medium text-lg', id: 'account_settings_button' %>
```

So the block becomes:
```erb
<div class="flex items-center justify-center space-x-4 mr-1">
  <%= render 'shared/navbar_buttons' %>
  <button onclick="toggleDocusealTheme()" class="opacity-60 hover:opacity-100 transition-opacity" title="Toggle dark mode" aria-label="Toggle dark mode">
    ...
  </button>
  <%= link_to t('documents'), documents_path, class: 'hidden md:inline-flex font-medium text-lg' %>
  <%= link_to t('settings'), settings_profile_index_path, class: 'hidden md:inline-flex font-medium text-lg', id: 'account_settings_button' %>
</div>
```

- [ ] **Step 2: Verify i18n key exists**

```bash
grep "documents:" /Users/maximusjb/Repos/docuseal/config/locales/en.yml | head -3
```

If the key was added in Task 2 Step 3, this should show it. If not, add it now.

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_navbar.html.erb
git commit -m "feat: add Documents link to navbar"
```

---

## Task 5: Post-Send Redirect and Button Labels

**Files:**
- Modify: `app/controllers/submissions_controller.rb`
- Modify: `app/views/submissions_dashboard/index.html.erb`
- Modify: `app/views/templates_dashboard/index.html.erb`

### Why
After a user sends a document (creates a submission), they should land on `/documents` (their inbox) rather than the template detail page. Also relabel the "Create" button throughout the dashboard to "New Document" to match the new mental model.

- [ ] **Step 1: Update submissions_controller.rb create redirect**

Open `app/controllers/submissions_controller.rb`. Find line:

```ruby
redirect_to template_path(@template), notice: I18n.t('new_recipients_have_been_added')
```

Change to:

```ruby
redirect_to documents_path, notice: I18n.t('new_recipients_have_been_added')
```

- [ ] **Step 2: Update submissions_controller.rb destroy fallback**

On the same file, find:

```ruby
redirect_back(fallback_location: @submission.template_id ? template_path(@submission.template) : root_path, notice:)
```

Change to:

```ruby
redirect_back(fallback_location: documents_path, notice:)
```

- [ ] **Step 3: Update submissions_dashboard Create button label**

Open `app/views/submissions_dashboard/index.html.erb`. Find:

```erb
<span class="hidden md:block"><%= t('create') %></span>
```

Change to:

```erb
<span class="hidden md:block"><%= t('new_document') %></span>
```

- [ ] **Step 4: Update templates_dashboard Create button label**

Open `app/views/templates_dashboard/index.html.erb`. Find:

```erb
<span class="hidden md:block"><%= t('create') %></span>
```

Change to:

```erb
<span class="hidden md:block"><%= t('new_document') %></span>
```

- [ ] **Step 5: Verify i18n key**

```bash
grep "new_document:" /Users/maximusjb/Repos/docuseal/config/locales/en.yml
```

Expected: `new_document: New Document`

- [ ] **Step 6: Commit**

```bash
git add app/controllers/submissions_controller.rb \
        app/views/submissions_dashboard/index.html.erb \
        app/views/templates_dashboard/index.html.erb
git commit -m "feat: redirect to documents after send and relabel Create to New Document"
```

---

## Self-Review Checklist

### Spec Coverage
- [x] Unified Documents view showing sent docs + drafts ✓ (Task 1+2)
- [x] Folder support with `?folder_id` param ✓ (Task 1)
- [x] Folder cards link into documents view ✓ (Task 2, folder partial)
- [x] Breadcrumb when inside a folder ✓ (Task 2, back arrow)
- [x] Root redirects signed-in users to /documents ✓ (Task 3)
- [x] "Documents" link in navbar ✓ (Task 4)
- [x] Post-send redirects to /documents ✓ (Task 5)
- [x] "New Document" labeling ✓ (Task 5)

### Notes for Implementer
- `TemplateFolders.filter_active_folders` is a class method on the `TemplateFolders` module — check `app/models/template_folders.rb` for the signature before using it
- `pagy_auto` is a pagy helper included in ApplicationController — same usage as in SubmissionsDashboardController
- `Submissions.search` and `Templates.search` are module methods — `search_template: true` is a keyword arg on `Submissions.search` (grep the module if uncertain)
- `Template.where.missing(:submissions)` requires Rails 6.1+ — this codebase is Rails 8 so it's fine
- The `t('documents')` i18n key should be added in Task 2 Step 3; Task 4 depends on it
- CanCan `accessible_by(current_ability)` on `TemplateFolder` requires that `Ability` grants `:read` on `TemplateFolder` — check `app/models/ability.rb` to confirm this exists before using it in the controller; if missing, add `can :read, TemplateFolder` to the ability
