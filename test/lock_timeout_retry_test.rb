require_relative "test_helper"

class LockTimeoutRetryTest < Minitest::Test
  def test_lock_timeout_retries
    with_lock_timeout_retries do
      error = assert_raises do
        migrate CheckLockTimeoutRetries
      end
      assert_lock_timeout error
      # MySQL and MariaDB do not support DDL transactions
      assert_equal (postgresql? ? 2 : 1), $migrate_attempts
    end
  end

  def test_lock_timeout_retries_no_transaction
    with_lock_timeout_retries do
      error = assert_raises do
        migrate CheckLockTimeoutRetriesNoTransaction
      end
      assert_lock_timeout error
      assert_equal 1, $migrate_attempts
    end
  end

  private

  def with_lock_timeout_retries
    StrongMigrations.lock_timeout = postgresql? ? 0.1 : 1
    StrongMigrations.lock_timeout_retries = 1
    StrongMigrations.lock_timeout_delay = 0
    $migrate_attempts = 0

    connection = ActiveRecord::Base.connection_pool.checkout
    if postgresql?
      connection.transaction do
        connection.execute("LOCK TABLE users IN ACCESS EXCLUSIVE MODE")
        yield
      end
    else
      begin
        connection.execute("LOCK TABLE users WRITE")
        yield
      ensure
        connection.execute("UNLOCK TABLES")
      end
    end
  ensure
    reset_timeouts
    StrongMigrations.lock_timeout_retries = 0
    StrongMigrations.lock_timeout_delay = 3
    ActiveRecord::Base.connection_pool.checkin(connection) if connection
  end

  def assert_lock_timeout(error)
    if postgresql?
      assert_match "canceling statement due to lock timeout", error.message
    else
      assert_match "Lock wait timeout exceeded", error.message
    end
  end
end