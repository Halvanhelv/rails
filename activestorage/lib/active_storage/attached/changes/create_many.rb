# frozen_string_literal: true

module ActiveStorage
  class Attached::Changes::CreateMany # :nodoc:
    attr_reader :name, :attachables, :pending_uploads
    attr_accessor :record

    # When false, +save+ appends the new attachments to the association
    # instead of reassigning (and thereby replacing) the whole collection.
    def replace?
      @replace
    end

    def initialize(name, record, attachables, pending_uploads: [], replace: true)
      @name, @record, @attachables = name, record, Array(attachables)
      @replace = replace
      blobs.each(&:identify_without_saving)
      @pending_uploads = Array(pending_uploads) + subchanges_without_blobs
      attachments
    end

    def attachments
      @attachments ||= subchanges.collect(&:attachment)
    end

    def blobs
      @blobs ||= subchanges.collect(&:blob)
    end

    def analyze
      subchanges.each(&:analyze)
    end

    def upload
      pending_uploads.each(&:upload)
    end

    def save
      if @replace
        assign_associated_attachments
      else
        append_associated_attachments
      end
      reset_associated_blobs
    end

    private
      def subchanges
        @subchanges ||= attachables.collect { |attachable| build_subchange_from(attachable) }
      end

      def build_subchange_from(attachable)
        ActiveStorage::Attached::Changes::CreateOneOfMany.new(name, record, attachable)
      end

      def subchanges_without_blobs
        subchanges.reject { |subchange| subchange.attachable.is_a?(ActiveStorage::Blob) }
      end

      def assign_associated_attachments
        record.public_send("#{name}_attachments=", persisted_or_new_attachments)
      end

      # Appends the new attachments to the existing association without
      # replacing it. Used by +Attached::Many#attach+ so that concurrent
      # attaches to the same record don't overwrite each other (a record that
      # is reassigned the whole collection would drop attachments another
      # process added in between). Only the not-yet-persisted attachments are
      # inserted; blobs already attached are skipped.
      def append_associated_attachments
        new_attachments = attachments.select(&:new_record?)
        record.public_send("#{name}_attachments").concat(new_attachments) if new_attachments.any?
      end

      def reset_associated_blobs
        record.public_send("#{name}_blobs").reset
      end

      def persisted_or_new_attachments
        attachments.select { |attachment| attachment.persisted? || attachment.new_record? }
      end
  end
end
