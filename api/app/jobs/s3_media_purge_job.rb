require "aws-sdk-s3"

# Deletes media files from S3 in the background.
# Idempotent: safe to retry. Missing keys are silently skipped.
class S3MediaPurgeJob < ApplicationJob
  queue_as :default

  def perform(s3_keys)
    return if s3_keys.blank?

    bucket = ENV.fetch("S3_BUCKET")
    client = Aws::S3::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))

    # S3 delete_objects max 1000 keys per call
    s3_keys.each_slice(1000) do |batch|
      client.delete_objects(
        bucket: bucket,
        delete: {
          objects: batch.map { |key| { key: key } },
          quiet: true
        }
      )
    end
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("[S3MediaPurgeJob] failed: #{e.message}")
    raise # retry
  end
end
