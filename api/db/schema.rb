# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_21_224128) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "chapters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "invited_phone"
    t.datetime "last_memory_at"
    t.string "life_chapter_tag"
    t.uuid "member_a_id", null: false
    t.uuid "member_b_id"
    t.string "name"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["last_memory_at"], name: "index_chapters_on_last_memory_at"
    t.index ["member_a_id", "invited_phone"], name: "idx_chapters_pending_pair", unique: true, where: "(member_b_id IS NULL)"
    t.index ["member_a_id", "member_b_id"], name: "idx_chapters_active_pair", unique: true, where: "(member_b_id IS NOT NULL)"
    t.index ["member_a_id"], name: "index_chapters_on_member_a_id"
    t.index ["member_b_id"], name: "index_chapters_on_member_b_id"
    t.index ["status"], name: "index_chapters_on_status"
  end

  create_table "daily_card_queue_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "chapter_id", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.datetime "opened_at"
    t.integer "priority", null: false
    t.date "scheduled_for", null: false
    t.string "trigger_type", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["chapter_id"], name: "index_daily_card_queue_entries_on_chapter_id"
    t.index ["scheduled_for"], name: "index_daily_card_queue_entries_on_scheduled_for"
    t.index ["user_id", "delivered_at"], name: "index_daily_card_queue_entries_on_user_id_and_delivered_at"
    t.index ["user_id", "scheduled_for"], name: "idx_daily_queue_one_per_day", unique: true
    t.index ["user_id"], name: "index_daily_card_queue_entries_on_user_id"
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "callback_priority"
    t.text "callback_queue_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "discarded_at"
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
    t.text "on_discard"
    t.text "on_finish"
    t.text "on_success"
    t.jsonb "serialized_properties"
    t.datetime "updated_at", null: false
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_job_id", null: false
    t.datetime "created_at", null: false
    t.interval "duration"
    t.text "error"
    t.text "error_backtrace", array: true
    t.integer "error_event", limit: 2
    t.datetime "finished_at"
    t.text "job_class"
    t.uuid "process_id"
    t.text "queue_name"
    t.datetime "scheduled_at"
    t.jsonb "serialized_params"
    t.datetime "updated_at", null: false
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lock_type", limit: 2
    t.jsonb "state"
    t.datetime "updated_at", null: false
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "key"
    t.datetime "updated_at", null: false
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_job_id"
    t.uuid "batch_callback_id"
    t.uuid "batch_id"
    t.text "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "cron_at"
    t.text "cron_key"
    t.text "error"
    t.integer "error_event", limit: 2
    t.integer "executions_count"
    t.datetime "finished_at"
    t.boolean "is_discrete"
    t.text "job_class"
    t.text "labels", array: true
    t.datetime "locked_at"
    t.uuid "locked_by_id"
    t.datetime "performed_at"
    t.integer "priority"
    t.text "queue_name"
    t.uuid "retried_good_job_id"
    t.datetime "scheduled_at"
    t.jsonb "serialized_params"
    t.datetime "updated_at", null: false
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at_only", where: "(finished_at IS NOT NULL)"
    t.index ["job_class"], name: "index_good_jobs_on_job_class"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "accepted_at"
    t.uuid "chapter_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.uuid "invited_by_id", null: false
    t.uuid "preview_memory_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_at"], name: "index_invitations_on_accepted_at"
    t.index ["chapter_id"], name: "index_invitations_on_chapter_id"
    t.index ["expires_at"], name: "index_invitations_on_expires_at"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["preview_memory_id"], name: "index_invitations_on_preview_memory_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "memories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "caption"
    t.uuid "chapter_id", null: false
    t.datetime "created_at", null: false
    t.uuid "owner_id", null: false
    t.string "s3_key", null: false
    t.datetime "taken_at"
    t.datetime "updated_at", null: false
    t.string "visibility", default: "this_item", null: false
    t.index ["chapter_id", "created_at"], name: "index_memories_on_chapter_id_and_created_at"
    t.index ["chapter_id", "owner_id", "visibility"], name: "index_memories_on_chapter_id_and_owner_id_and_visibility"
    t.index ["chapter_id"], name: "index_memories_on_chapter_id"
    t.index ["owner_id"], name: "index_memories_on_owner_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "otp_code"
    t.datetime "otp_expires_at"
    t.string "phone", null: false
    t.string "push_token"
    t.datetime "updated_at", null: false
    t.index ["phone"], name: "index_users_on_phone", unique: true
  end

  add_foreign_key "chapters", "users", column: "member_a_id"
  add_foreign_key "chapters", "users", column: "member_b_id"
  add_foreign_key "daily_card_queue_entries", "chapters"
  add_foreign_key "daily_card_queue_entries", "users"
  add_foreign_key "invitations", "chapters"
  add_foreign_key "invitations", "memories", column: "preview_memory_id"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "memories", "chapters"
  add_foreign_key "memories", "users", column: "owner_id"
end
