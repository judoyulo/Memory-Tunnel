# Pushes an APNs notification to the chapter partner when a new memory is added.
# Enqueued from MemoriesController#create.
class NotifyNewMemoryJob < ApplicationJob
  queue_as :default

  def perform(memory_id:, recipient_id:)
    memory    = Memory.find(memory_id)
    recipient = User.find(recipient_id)
    sender    = memory.owner

    return unless recipient.push_token.present?

    ApnsService.send!(
      push_token: recipient.push_token,
      title:      "#{sender.display_name} added a memory",
      body:       memory.caption.present? ? memory.caption : "Tap to see it",
      data:       {
        type:       "new_memory",
        memory_id:  memory.id,
        chapter_id: memory.chapter_id
      }
    )
  end
end
