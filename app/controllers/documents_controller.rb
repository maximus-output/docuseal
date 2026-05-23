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
