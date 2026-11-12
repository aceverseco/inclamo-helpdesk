# frozen_string_literal: true

# One account lock makes bulk application and personal writes linearizable.
# A reset retains a revision tombstone, so an older editor cannot resurrect it.
class Inclamo::WorkspaceLayout
  class Invalid < StandardError; end
  class Conflict < StandardError; end

  MANIFEST = JSON.parse(File.read(Rails.root.join('custom/config/workspace_widgets.json'))).freeze

  def self.product
    {
      'schema_version' => MANIFEST.fetch('schema_version'),
      'placements' => MANIFEST.fetch('placements').index_with do |placement|
        MANIFEST.fetch('widgets').select { |widget| widget['placement'] == placement }
                .map { |widget| { 'id' => widget['id'], 'collapsed' => false } }
      end
    }
  end

  def self.validate!(layout, preserved_ids: [])
    raise Invalid, 'invalid_layout' unless layout.is_a?(Hash) && layout.keys.sort == %w[placements schema_version]
    raise Invalid, 'unsupported_version' unless layout['schema_version'] == MANIFEST['schema_version']

    placements = layout['placements']
    raise Invalid, 'invalid_placements' unless placements.is_a?(Hash) && placements.keys.sort == MANIFEST['placements'].sort

    seen = []
    placements.each do |placement, entries|
      raise Invalid, 'invalid_entries' unless entries.is_a?(Array) && entries.length <= 50

      entries.each do |entry|
        raise Invalid, 'invalid_entry' unless entry.is_a?(Hash) && entry.keys.sort == %w[collapsed id]
        raise Invalid, 'invalid_entry' unless entry['id'].is_a?(String) && [true, false].include?(entry['collapsed'])
        raise Invalid, 'duplicate_widget' if seen.include?(entry['id'])

        seen << entry['id']
        descriptor = MANIFEST['widgets'].find { |widget| widget['id'] == entry['id'] }
        if descriptor
          raise Invalid, 'unsupported_placement' unless descriptor['placement'] == placement
        elsif !preserved_ids.include?(entry['id'])
          raise Invalid, 'unknown_widget'
        end
      end
    end
    layout
  end

  def initialize(member)
    @member = member
    @defaults = Inclamo::WorkspaceDefault.create_or_find_by!(account_id: member.account_id)
  end

  def read
    @defaults.reload
    preference = Inclamo::WorkspacePreference.find_by(account_user_id: @member.id)
    layout = preference&.layout || @defaults.layout || self.class.product
    {
      layout: layout, revision: revision(preference),
      source: preference&.layout ? 'personal' : (@defaults.layout ? 'account' : 'product'),
      unavailable: ids(layout) - MANIFEST['widgets'].pluck('id')
    }
  end

  def save!(layout:, expected:, reset: false)
    @defaults.with_lock do
      # Membership may have been removed while a request waited on the lock.
      @member.reload
      preference = Inclamo::WorkspacePreference.find_or_initialize_by(account_user_id: @member.id)
      raise Conflict unless expected == revision(preference)

      previous = preference.layout || @defaults.layout || self.class.product
      self.class.validate!(layout, preserved_ids: ids(previous)) unless reset
      preference.update!(layout: reset ? nil : layout, revision: preference.revision.to_i + 1)
    end
    read
  end

  def administration
    @defaults.reload
    members = @member.account.account_users.includes(:user).order(:id)
    {
      layout: @defaults.layout || self.class.product, revision: @defaults.revision.to_s,
      members: members.map { |member| { user_id: member.user_id, name: member.user.name, role: member.role } }
    }
  end

  def administer!(layout:, expected:, target:, user_id: nil, confirmed_count: nil)
    raise ActiveRecord::RecordNotFound unless @member.reload.administrator?

    @defaults.with_lock do
      raise Conflict unless expected == @defaults.revision.to_s
      raise Invalid, 'invalid_target' unless %w[default member all].include?(target)

      members = @member.account.account_users
      member = members.find_by!(user_id: user_id) if target == 'member'
      previous = target == 'member' ? Inclamo::WorkspacePreference.find_by(account_user_id: member.id)&.layout : @defaults.layout
      self.class.validate!(layout, preserved_ids: ids(previous || self.class.product))
      if target == 'member'
        preference = Inclamo::WorkspacePreference.find_or_initialize_by(account_user_id: member.id)
        preference.update!(layout: layout, revision: preference.revision.to_i + 1)
      else
        if target == 'all'
          raise Conflict unless confirmed_count == members.count

          Inclamo::WorkspacePreference.where(account_user_id: members.select(:id)).delete_all
        end
        @defaults.layout = layout
      end
      @defaults.revision += 1
      @defaults.save!
    end
    administration
  end

  private

  def revision(preference)
    "#{@defaults.revision}:#{preference&.revision.to_i}"
  end

  def ids(layout)
    layout.fetch('placements', {}).values.flatten.filter_map { |entry| entry['id'] }
  end
end
