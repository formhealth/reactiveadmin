ActiveRecord::Schema[8.1].define(version: 1) do
  create_table :active_admin_comments, force: :cascade do |t|
    t.string :namespace
    t.text :body
    t.string :resource_type
    t.integer :resource_id
    t.string :author_type
    t.integer :author_id
    t.timestamps
  end

  create_table :admin_users, force: :cascade do |t|
    t.string :name, null: false
    t.string :email
    t.string :role, null: false, default: "admin"
    t.integer :author_id
    t.timestamps
  end

  create_table :authors, force: :cascade do |t|
    t.string :name, null: false
    t.string :email
    t.decimal :rating, precision: 4, scale: 2
    t.date :born_on
    t.timestamps
  end

  create_table :profiles, force: :cascade do |t|
    t.integer :author_id, null: false
    t.text :bio
    t.timestamps
  end

  create_table :categories, force: :cascade do |t|
    t.string :name, null: false
    t.string :api_token
    t.json :settings
    t.timestamps
  end

  create_table :tags, force: :cascade do |t|
    t.string :name, null: false
    t.timestamps
  end

  create_table :posts, force: :cascade do |t|
    t.string :title, null: false
    t.text :body
    t.integer :status, null: false, default: 0
    t.json :metadata
    t.datetime :published_at
    t.integer :views_count, null: false, default: 0
    t.boolean :featured, null: false, default: false
    t.integer :author_id, null: false
    t.integer :category_id
    t.timestamps
  end

  create_table :taggings, force: :cascade do |t|
    t.integer :post_id, null: false
    t.integer :tag_id, null: false
    t.timestamps
  end

  create_table :comments, force: :cascade do |t|
    t.integer :post_id, null: false
    t.text :body, null: false
    t.boolean :approved, null: false, default: false
    t.json :context
    t.timestamps
  end

  create_table :notes, force: :cascade do |t|
    t.string :title, null: false
    t.text :body
    t.integer :weight, null: false, default: 0
    t.timestamps
  end

  create_table :memos, force: :cascade do |t|
    t.string :title, null: false
    t.text :summary
    t.json :payload
    t.string :secret
    t.integer :priority, null: false, default: 0
    t.boolean :pinned, null: false, default: false
    t.integer :author_id
    t.datetime :noted_at
    t.timestamps
  end

  create_table :lockers, force: :cascade do |t|
    t.string :label, null: false
    t.string :code
    t.timestamps
  end

  create_table :plans, force: :cascade do |t|
    t.string :name, null: false
    t.string :api_token
    t.text :notes
    t.timestamps
  end

  create_table :accounts, force: :cascade do |t|
    t.integer :author_id, null: false
    t.integer :plan_id
    t.integer :sponsor_id
    t.timestamps
  end

  create_table :rosters, force: :cascade do |t|
    t.string :name, null: false
    t.json :contacts
    t.json :backups
    t.date :starts_on
    t.date :signed_on
    t.datetime :ends_at
    t.timestamps
  end

  create_table :scans, force: :cascade do |t|
    t.string :title, null: false
    t.binary :image
    t.timestamps
  end

  create_table :tickets, force: :cascade do |t|
    t.string :title, null: false
    t.integer :lock_version, null: false, default: 0
    t.timestamps
  end

  create_table :stock_levels, primary_key: [:warehouse, :sku], force: :cascade do |t|
    t.string :warehouse, null: false
    t.string :sku, null: false
    t.integer :quantity, null: false, default: 0
    t.json :details
    t.timestamps
  end
end
