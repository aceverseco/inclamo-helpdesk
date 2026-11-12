# frozen_string_literal: true

# A conversation queue shared by the whole account (capability team-queues).
# Its `query` is the payload of Chatwoot's own conversation filter, so the
# native list shows a queue the way it shows a saved folder, with the staff
# member's own permissions. The ready queues and what they ship with are in
# Inclamo::TeamQueues.
class Inclamo::TeamQueue < ApplicationRecord
  NAME_LENGTH = 60
  # Each visible queue costs a count query on every refresh of the navigation.
  VISIBLE_LIMIT = 20

  belongs_to :account

  validates :name, presence: true, length: { maximum: NAME_LENGTH }
  validates :key, uniqueness: { scope: :account_id }, allow_nil: true
  validate :room_among_visible, if: -> { !hidden? && (new_record? || will_save_change_to_hidden?) }

  scope :ordered, -> { order(:position, :id) }
  scope :visible, -> { where(hidden: false) }

  def ready?
    key.present? && Inclamo::TeamQueues.ready?(key)
  end

  def as_json(count: nil)
    { id: id, key: key, name: name, position: position, hidden: hidden, ready: ready?, query: query, count: count }
  end

  private

  def room_among_visible
    others = self.class.visible.where(account_id: account_id).where.not(id: id).count
    errors.add(:hidden, :too_many_visible) if others >= VISIBLE_LIMIT
  end
end
