class Mailboxer::Message < Mailboxer::Notification
  attr_accessible :attachment if Mailboxer.protected_attributes?
  self.table_name = :mailboxer_notifications

  belongs_to :conversation, :class_name => "Mailboxer::Conversation", :validate => true, :autosave => true
  validates_presence_of :sender

  class_attribute :on_deliver_callback
  protected :on_deliver_callback
  scope :conversation, lambda { |conversation|
    where(:conversation_id => conversation.id)
  }

  mount_uploader :attachment, Mailboxer::AttachmentUploader

  class << self
    #Sets the on deliver callback method.
    def on_deliver(callback_method)
      self.on_deliver_callback = callback_method
    end
  end

  #Delivers a Message. USE NOT RECOMMENDED.
  #Use Mailboxer::Models::Messageable.send_message instead.
  def deliver(reply = false, should_clean = true, draft = false)
    self.clean if should_clean

    #Receiver receipts
    mailbox_type = draft ? "unsent" : "inbox"
    temp_receipts = recipients.map { |r| build_receipt(r, mailbox_type) }

    #Sender receipt
    mailbox_type = draft ? "drafts" : "sentbox"
    sender_receipt = build_receipt(sender, mailbox_type, true)

    temp_receipts << sender_receipt

    if temp_receipts.all?(&:valid?)
      Mailboxer::MailDispatcher.new(self, temp_receipts).call if !draft
      temp_receipts.each(&:save!)

      conversation.touch if reply

      self.recipients = nil

      on_deliver_callback.call(self) if on_deliver_callback && !draft
    end

    sender_receipt
  end
end
