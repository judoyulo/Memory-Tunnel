class Memory < ApplicationRecord
  belongs_to :chapter
  belongs_to :owner, class_name: "User"

  enum :visibility, { this_item: "this_item", all: "all" }, scopes: false

  validates :chapter, :owner, presence: true
  validates :s3_key,     presence: true
  validates :visibility, presence: true

  # ── Signed URL ───────────────────────────────────────────────────────────────
  # Returns a short-lived signed URL for the client to render the photo.
  # TTL is 1 hour; client should call GET /chapters/:id/memories/:id/refresh_url
  # when its local TTL > 50 minutes.
  SIGNED_URL_TTL = 3600 # seconds

  def signed_url
    s3 = Aws::S3::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
    signer = Aws::S3::Presigner.new(client: s3)
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
    key = "memories/#{chapter_id}/#{SecureRandom.uuid}.jpg"
    s3  = Aws::S3::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
    signer = Aws::S3::Presigner.new(client: s3)

    upload_url = signer.presigned_url(
      :put_object,
      bucket:      ENV.fetch("S3_BUCKET"),
      key:         key,
      expires_in:  900, # 15 minutes to complete upload
      content_type: content_type,
      acl:         "private"
    )

    { upload_url: upload_url, s3_key: key }
  end

  # Effective date for sorting and "N years ago" calculation
  def effective_date
    taken_at || created_at
  end
end
