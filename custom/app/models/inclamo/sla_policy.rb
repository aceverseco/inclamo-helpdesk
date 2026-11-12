# frozen_string_literal: true

# Targets for how fast the conversations of some inboxes get a first answer
# and are resolved (capability sla-timers). Chatwoot's own SLA policies belong
# to its paid edition and are not used.
class Inclamo::SlaPolicy < ApplicationRecord
  # A year; the page offers minutes, hours and days.
  MAX_TARGET_SECONDS = 365 * 86_400

  belongs_to :account
  has_many :timers, class_name: 'Inclamo::SlaTimer', foreign_key: :policy_id, inverse_of: :policy, dependent: nil

  before_validation :normalise_inboxes
  # Each message is a whole sentence: the page shows them as they come.
  validates :name, presence: { message: ->(*) { I18n.t('inclamo.sla.errors.name_needed') } },
                   length: { maximum: 120, message: ->(*) { I18n.t('inclamo.sla.errors.name_too_long') } }
  validates :first_response_seconds, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_TARGET_SECONDS,
                                                     message: ->(*) { I18n.t('inclamo.sla.errors.first_response_range') } }, allow_nil: true
  validates :resolution_seconds, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_TARGET_SECONDS,
                                                 message: ->(*) { I18n.t('inclamo.sla.errors.resolution_range') } }, allow_nil: true
  validates :business_hours_only, inclusion: { in: [true, false], message: ->(*) { I18n.t('inclamo.sla.errors.business_hours_needed') } }
  validates :all_inboxes, inclusion: { in: [true, false], message: ->(*) { I18n.t('inclamo.sla.errors.all_inboxes_needed') } }
  validate :a_target_is_set
  validate :inboxes_belong_to_the_account

  before_create :place_last
  before_destroy :stop_running_timers

  scope :ordered, -> { order(:position, :id) }

  # The policy a new conversation gets: the first in the list that covers its
  # inbox, among the policies that existed when the conversation was created.
  def self.covering(conversation)
    where(account_id: conversation.account_id).where(created_at: ..conversation.created_at).ordered
                                               .find { |policy| policy.covers?(conversation.inbox_id) }
  end

  # Puts the account's policies in the order of `ids`; policies not named keep
  # their order after them.
  def self.reorder!(account, ids)
    ids = Array(ids).map(&:to_i)
    policies = where(account_id: account.id).ordered.to_a
    named = ids.filter_map { |id| policies.find { |policy| policy.id == id } }
    transaction do
      (named + (policies - named)).each_with_index do |policy, index|
        policy.update_columns(position: index, updated_at: Time.current) if policy.position != index # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end

  def covers?(inbox_id)
    all_inboxes? || inbox_ids.include?(inbox_id)
  end

  private

  # An inbox chosen before and deleted since leaves the list: the page no
  # longer shows it, so it could not be unticked. An unknown inbox chosen now
  # is refused (inboxes_belong_to_the_account).
  def normalise_inboxes
    return self.inbox_ids = [] if all_inboxes?

    ids = Array(inbox_ids).compact_blank.map(&:to_i).uniq
    chosen_before = persisted? ? ids & Array(inbox_ids_in_database) : []
    ids -= chosen_before - account.inboxes.where(id: chosen_before).pluck(:id) if chosen_before.any? && account
    self.inbox_ids = ids
  end

  def a_target_is_set
    return if first_response_seconds.present? || resolution_seconds.present?

    errors.add(:base, :target_needed, message: I18n.t('inclamo.sla.errors.target_needed'))
  end

  def inboxes_belong_to_the_account
    return if all_inboxes?
    return errors.add(:inbox_ids, :blank, message: I18n.t('inclamo.sla.errors.inboxes_needed')) if inbox_ids.empty?
    return if account.nil? || account.inboxes.where(id: inbox_ids).count == inbox_ids.size

    errors.add(:inbox_ids, :invalid, message: I18n.t('inclamo.sla.errors.unknown_inbox'))
  end

  def place_last
    self.position = (self.class.where(account_id: account_id).maximum(:position) || -1) + 1
  end

  # Timers already applied keep their targets; those still running stop, so
  # nothing is marked as missed after the policy is gone. A target that passed
  # while the policy was there is marked first, as the check would have done:
  # the check may not have run since.
  def stop_running_timers
    now = Time.current
    Inclamo::Sla::Timers.check_due!(now, timers)
    stopped = timers.running.pluck(:conversation_id)
    timers.running.update_all(stopped_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    # A stopped timer is not overdue any more (team queue "Overdue").
    stopped.each { |conversation_id| Inclamo::TeamQueues::Markers.sync_overdue(conversation_id) }
  end
end
