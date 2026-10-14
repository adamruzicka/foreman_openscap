module ForemanOpenscap
  module ScapFileContent
    require 'digest/sha2'

    extend ActiveSupport::Concern

    included do
      validates :digest, :presence => true
      validate :scap_file_presence

      before_validation :redigest, :if => lambda { |file_content| !file_content.persisted? || file_content.scap_file_changed? }
    end

    delegate :attached?, :to => :scap_file, :prefix => true

    def scap_file_contents
      pending_io = attachment_changes['scap_file']&.attachable&.fetch(:io, nil)
      return read_scap_file(pending_io) if pending_io

      scap_file.download if scap_file_attached?
    end

    def attach_scap_file(io, filename:)
      self.original_filename = filename
      scap_file.attach(:io => io, :filename => filename, :content_type => 'application/xml')
    end

    def scap_file_changed?
      attachment_changes.key?('scap_file')
    end

    def scap_file_previously_changed?
      saved_change_to_digest?
    end

    def digest
      return self[:digest] if self[:digest]
      return unless scap_file_attached?

      self[:digest] = Digest::SHA256.hexdigest(scap_file_contents)
    end

    private

    def read_scap_file(io)
      position = io.pos
      io.read.tap { io.seek(position) }
    end

    def scap_file_presence
      errors.add(:scap_file, :blank) unless scap_file_attached?
    end

    def redigest
      return unless scap_file_attached?

      self[:digest] = Digest::SHA256.hexdigest(scap_file_contents)
    end
  end
end
