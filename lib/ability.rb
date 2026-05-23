# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    if user.role == User::ADMIN_ROLE
      can %i[read create update], Template, Abilities::TemplateConditions.collection(user) do |template|
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
      can :manage, :bulk_send
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
end
