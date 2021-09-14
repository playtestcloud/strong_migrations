require "bundler/setup"
Bundler.require(:default)
require "minitest/autorun"
require "minitest/pride"
require "active_record"

# needed for target_version
module Rails
  def self.env
    ActiveSupport::StringInquirer.new("test")
  end
end

$adapter = ENV["ADAPTER"] || "postgresql"
ActiveRecord::Base.establish_connection(adapter: $adapter, database: "strong_migrations_test")

if ENV["VERBOSE"]
  ActiveRecord::Base.logger = ActiveSupport::Logger.new($stdout)
else
  ActiveRecord::Migration.verbose = false
end

def migration_version
  ActiveRecord.version.to_s.to_f
end

TestMigration = ActiveRecord::Migration[migration_version]
TestSchema = ActiveRecord::Schema

ActiveRecord::SchemaMigration.create_table

ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS users")
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS new_users")
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS orders")
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS devices")

ActiveRecord::Schema.define do
  create_table "users" do |t|
    t.string :name
    t.string :city
    t.decimal :credit_score, precision: 10, scale: 5
    t.timestamp :deleted_at
    t.string :country, limit: 20
    t.string :interval
    t.references :order
  end

  create_table "orders" do |t|
  end

  create_table "devices" do |t|
  end
end

module Helpers
  def postgresql?
    $adapter == "postgresql"
  end

  def mysql?
    $adapter == "mysql2" && !ActiveRecord::Base.connection.try(:mariadb?)
  end

  def mariadb?
    $adapter == "mysql2" && ActiveRecord::Base.connection.try(:mariadb?)
  end
end

class Minitest::Test
  include Helpers

  def migrate(migration, direction: :up)
    ActiveRecord::SchemaMigration.delete_all
    if direction == :down
      migration.version ||= 1
      ActiveRecord::SchemaMigration.create!(version: migration.version)
    end
    args = ActiveRecord::VERSION::MAJOR >= 6 ? [ActiveRecord::SchemaMigration] : []
    ActiveRecord::Migrator.new(direction, [migration], *args).migrate
    puts "\n\n" if ENV["VERBOSE"]
    true
  end

  def assert_unsafe(migration, message = nil, **options)
    error = assert_raises(StandardError) { migrate(migration, **options) }
    puts error.message if ENV["VERBOSE"]

    assert_kind_of StrongMigrations::UnsafeMigration, error.cause
    assert_match message, error.message if message
  end

  def assert_safe(migration, direction: nil)
    if direction
      assert migrate(migration, direction: direction)
    else
      assert migrate(migration, direction: :up)
      assert migrate(migration, direction: :down)
    end
  end

  def with_target_version(version)
    StrongMigrations.target_version = version
    yield
  ensure
    StrongMigrations.target_version = nil
  end

  def check_constraints?
    ActiveRecord::VERSION::STRING >= "6.1"
  end

  def reset_timeouts
    StrongMigrations.lock_timeout = nil
    StrongMigrations.statement_timeout = nil
    if postgresql?
      ActiveRecord::Base.connection.execute("RESET lock_timeout")
      ActiveRecord::Base.connection.execute("RESET statement_timeout")
    elsif mysql?
      ActiveRecord::Base.connection.execute("SET max_execution_time = DEFAULT")
      ActiveRecord::Base.connection.execute("SET lock_wait_timeout = DEFAULT")
    elsif mariadb?
      ActiveRecord::Base.connection.execute("SET max_statement_time = DEFAULT")
      ActiveRecord::Base.connection.execute("SET lock_wait_timeout = DEFAULT")
    end
  end
end

StrongMigrations.add_check do |method, args|
  if method == :add_column && args[1].to_s == "forbidden"
    stop! "Cannot add forbidden column"
  end
end

require_relative "migrations"
