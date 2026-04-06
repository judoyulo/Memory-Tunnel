require "aws-sdk-s3"

class Memory < ApplicationRecord
  belongs_to :chapter
  belongs_to :owner, class_name: "User"

  enum :visibility,  { this_item: "this_item", all: "all" },    scopes: false
  enum :media_type,  { photo: "photo", voice: "voice", text: "text", location_checkin: "location_checkin" }, scopes: false

  validates :chapter, :owner, presence: true
  validates :s3_key,          presence: true, unless: -> { text? || location_checkin? }
  validates :visibility,      presence: true
  validates :media_type,      presence: true

  # ── Signed URL ───────────────────────────────────────────────────────────────
  # Returns a short-lived signed URL for the client to render the photo.
  # TTL is 1 hour; client should call GET /chapters/:id/memories/:id/refresh_url
  # when its local TTL > 50 minutes.
  SIGNED_URL_TTL = 3600 # seconds

  def self.s3_client
    @s3_client ||= Aws::S3::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
  end

  def signed_url
    signer = Aws::S3::Presigner.new(client: self.class.s3_client)
    signer.presigned_url(
      :get_object,
      bucket: ENV.fetch("S3_BUCKET"),
      key: s3_key,
      expires_in: SIGNED_URL_TTL
    )
  end

  # ── Presigned upload URL (direct-to-S3) ──────────────────────────────────────
  # Generates a presigned PUT URL so the iOS client can upload directly to S3
  # without routing the binary through Rails. Returns { upload_url:, s3_key: }.
  def self.presign_upload(chapter_id:, owner_id:, content_type: "image/jpeg")
    ext = content_type.include?("audio") ? ".m4a" : ".jpg"
    key = "memories/#{chapter_id}/#{SecureRandom.uuid}#{ext}"
    signer = Aws::S3::Presigner.new(client: s3_client)

    # NOTE: `acl:` param is intentionally omitted. Passing `acl: "private"` fails on
    # buckets with ObjectOwnership: BucketOwnerEnforced (ACLs disabled). Objects
    # inherit the bucket's default private ACL. Verify your bucket has either
    # ObjectOwnership: BucketOwnerEnforced OR a bucket policy blocking public access
    # before relying on this behavior.
    upload_url = signer.presigned_url(
      :put_object,
      bucket:      ENV.fetch("S3_BUCKET"),
      key:         key,
      expires_in:  900, # 15 minutes to complete upload
      content_type: content_type
    )

    { upload_url: upload_url, s3_key: key }
  end

  # Effective date for sorting and "N years ago" calculation
  def effective_date
    event_date&.to_datetime || taken_at || created_at
  end
end
