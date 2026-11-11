# Read-only final counts for the isolated central fixture. No keys or mail bodies.
raise 'synthetic central only' unless ENV['INCLAMO_SUPPORT_TEST_NETWORK'] == 'true' && ENV['INCLAMO_SUPPORT_CENTRAL'] == 'true'
requests = Inclamo::Support::CentralRequest.all
receipts = Inclamo::Support::Receipt.all
messages = Message.where(conversation_id: requests.select(:conversation_id), message_type: :incoming)
deliveries = Inclamo::Support::Delivery.all
result = {
  enterprise_loaded: Rails.root.join('enterprise').exist?,
  central_requests: requests.count,
  native_conversations: requests.distinct.count(:conversation_id),
  receipts: receipts.count,
  receipt_messages: receipts.distinct.count(:message_id),
  native_incoming_messages: messages.count,
  duplicate_receipt_uuids: receipts.group(:source_id, :uuid).having('count(*) > 1').count.length,
  origins: Conversation.where(id: requests.select(:conversation_id)).group("custom_attributes ->> 'inclamo_support_origin'").count,
  notification_records: deliveries.count,
  sent_notifications: deliveries.where.not(delivered_at: nil).count,
  duplicate_notifications: deliveries.group(:recipient_id, :message_id).having('count(*) > 1').count.length
}
raise 'duplicate native message/conversation' unless result[:central_requests] == result[:native_conversations] && result[:receipts] == result[:receipt_messages] && result[:receipts] == result[:native_incoming_messages]
raise 'duplicate receipt/notification' unless result[:duplicate_receipt_uuids].zero? && result[:duplicate_notifications].zero?
puts JSON.pretty_generate(result)
