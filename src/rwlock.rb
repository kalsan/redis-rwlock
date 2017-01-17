class Redis
  class RWLock
    def initialize(name, opts = {})
      @name = name
      @redis = opts.delete(:redis) || Redis.new(opts)
      @rem_res_acc = Semaphore.new(name + ':res_acc', redis: @redis)
      @rem_rcount_acc = Semaphore.new(name + ':read_count_acc', redis: @redis)
      @rem_fcfs_queue = Semaphore.new(name + ':service_queue', redis: @redis)
      @holding_read_lock = 0
      @holding_write_lock = 0
      @verbose = opts.delete(:verbose_locks)

      pr 'Creation' if @verbose
    end

    # Acquire a read lock, blocking.
    # Returns the amount of times this lock is held by this process for read.
    def lock_read
      pr 'Locking for read' if @verbose

      # Remote
      if @holding_read_lock <= 0
        @rem_fcfs_queue.lock
        @rem_rcount_acc.lock
        if read_count_is_zero?
          @rem_res_acc.lock
          pr 'Locking remote lock.' if @verbose
        end
        @redis.incr(read_count_key)
        @rem_fcfs_queue.signal(0)
        @rem_rcount_acc.signal(0)
      end

      # Local
      @holding_read_lock += 1 # Reentrant, not thread-safe
      pr "New local readers count is #{@holding_read_lock}" if @verbose
      return @holding_read_lock
    end

    # Release a read lock.
    # Returns the amount of times this lock is held by this process for read.
    def unlock_read
      pr 'Unlocking (read)' if @verbose

      # Local
      if @holding_read_lock <= 0
        fail(ThreadError, 'Trying to release a read lock, but holding none!')
      end

      # Remote
      if @holding_read_lock <= 1
        @rem_rcount_acc.lock # this line blocks if concurr. acc. on Redis conn.
        @redis.decr(read_count_key)
        if read_count_is_zero?
          @rem_res_acc.signal(0)
          pr 'Unlocking remote lock.' if @verbose
        end
        @rem_rcount_acc.signal(0)
      end

      # Local
      @holding_read_lock -= 1 # Reentrant, not thread-safe
      pr "New local readers count is #{@holding_read_lock}" if @verbose
      return @holding_read_lock
    end

    # Acquire a write lock, blocking.
    # Returns the amount of times this lock is held by this process for write.
    def lock_write
      pr 'Locking for write' if @verbose

      # Remote
      if @holding_write_lock <= 0
        @rem_fcfs_queue.lock
        @rem_res_acc.lock
        @rem_fcfs_queue.signal(0)
      end

      # Local
      @holding_write_lock += 1 # Reentrant, not thread-safe
      pr "New local writers count is #{@holding_read_lock}" if @verbose
      return @holding_write_lock
    end

    # Release a write lock.
    # Returns the amount of times this lock is held by this process for write.
    def unlock_write
      pr 'Unlocking (write)' if @verbose

      # Local
      if @holding_write_lock <= 0
        fail(ThreadError, 'Trying to release a read lock, but holding none!')
      end

      # Remote
      if @holding_write_lock <= 1
        @rem_res_acc.signal(0)
      end

      # Local
      @holding_write_lock -= 1 # Reentrant, not thread-safe
      pr "New local writers count is #{@holding_read_lock}" if @verbose
      return @holding_write_lock
    end

    def with_read_lock(&_block)
      lock_read
      begin
        yield
      ensure
        unlock_read
      end
    end

    def with_write_lock(&_block)
      lock_write
      begin
        yield
      ensure
        unlock_write
      end
    end

    private

    def read_count_key
      'RWLOCK:' + @name + ':READCOUNT'
    end

    def read_count_is_zero?
      count = @redis.get(read_count_key) || '0'
      pr "Remote readers count was (locking) / is new (unlocking) #{count}" if @verbose
      return count == '0'
    end

    def pr(msg)
      puts "rwlock: #{Thread.current.object_id}@#{Time.now.to_f}[lock:#{object_id}]: #{msg}"
    end
  end
end
