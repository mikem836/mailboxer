class Mailboxer::Message < Mailboxer::Notification
  attr_accessible :attachment if Mailboxer.protected_attributes?
  self.table_name = :mailboxer_notifications

  belongs_to :conversation, :validate => true, :autosave => true
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
    self.body = [body].pack("m")

    #Receiver receipts
    mailbox_type = draft ? "unsent" : "inbox"
    receiver_receipts = recipients.map do |r|
      receipts.build(receiver: r, mailbox_type: mailbox_type, is_read: false)
    end

    #Sender receipt
    mailbox_type = draft ? "drafts" : "sentbox"
    sender_receipt =
      receipts.build(receiver: sender, mailbox_type: mailbox_type, is_read: true)

    if valid?
      Mailboxer::MailDispatcher.new(self, receiver_receipts).call if !draft
      save!

      conversation.touch if reply && !draft

      self.recipients = nil

      on_deliver_callback.call(self) if on_deliver_callback && !draft
    end

    sender_receipt
  end

  #Updates a draft message
  def update_draft(recipients, msg_body, subject, attachment = nil, reply = false, should_clean = true)
    self.body       = msg_body
    self.subject    = subject
    self.attachment = attachment

    self.clean if should_clean
    self.body = [body].pack("m")

    conversation.subject = self.subject if subject_changed?

    #Receiver receipts
    unsent = receipts.unsent
    receiver_receipts = recipients.map { |r|
      unsent.find { |receipt| receipt.receiver == r } ||
      receipts.build(receiver: r, mailbox_type: "unsent", is_read: false)
    }

    #Sender receipt
    sender_receipt = receipt_for(sender).first ||
      receipts.build(receiver: sender, mailbox_type: "drafts", is_read: true)

    if valid?
      save!
      conversation.touch if !reply
    end

    sender_receipt
  end

  #Delivers a draft message
  def deliver_draft
    self.draft = false

    #Receiver receipts
    receiver_receipts = receipts.unsent.to_a
    receipts.unsent.move_to_inbox

    #Sender receipt
    sender_receipt = receipts.drafts.first
    sender_receipt.move_to_sentbox

    conversation.touch

    Mailboxer::MailDispatcher.new(self, receiver_receipts).call
    save!

    on_deliver_callback.call(self) if on_deliver_callback

    sender_receipt
  end
end
