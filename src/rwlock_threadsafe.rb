class Redis
  class RWLockThreadsafe
    def initialize(name, opts = {})
      @name = name
      @redis = opts.delete(:redis) || Redis.new(opts)
      @capacity = opts.delete(:capacity) || 512
      @mutex = Mutex.new
      @taken_pool = {}
      @free_pool = []
      @verbose = opts.delete(:verbose_thsafe)
      @verbose_locks = opts.delete(:verbose_locks)
    end

    def lock_read
      return lock false
    end

    def unlock_read
      return unlock false
    end

    def lock_write
      return lock true
    end

    def unlock_write
      return unlock true
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

    def lock(for_write = false)
      tid = Thread.current.object_id
      pr "Locking for thread #{tid}, write: #{for_write}" if @verbose
      l = nil
      @mutex.synchronize do
        l = gimme_lock(tid)
        @taken_pool[tid] = l
        pr "Pools now: (taken: #{@taken_pool.size}, free: #{@free_pool.size})" if @verbose
      end
      ret = for_write ? l.lock_write : l.lock_read
      return ret
    end

    def unlock(for_write = false)
      @mutex.synchronize do
        tid = Thread.current.object_id
        pr "Unlocking thread #{tid}, write: #{for_write}" if @verbose
        l = @taken_pool[tid]
        fail(ThreadError, 'This thread is not holding a lock.') unless l
        ret = for_write ? l.unlock_write : l.unlock_read
        if ret == 0 # If last access, free lock
          pr "Freeing lock of thread #{tid}" if @verbose
          @free_pool.push(@taken_pool.delete(tid))
          pr "Pools now: (taken: #{@taken_pool.size}, free: #{@free_pool.size})" if @verbose
        end
        return ret
      end
    end

    def gimme_lock(tid)
      return @taken_pool[tid] ||
             @free_pool.pop ||
             safe_new_lock(tid)
    end

    def safe_new_lock(tid)
      pr "Creating a new lock for thread #{tid}" if @verbose
      if @taken_pool.size + @free_pool.size + 1 > @capacity
        fail("Creating a new lock would exceed max capacity of #{@capacity}")
      end
      return Redis::RWLock.new(@name, verbose_locks: @verbose_locks) # Do not share redis connection or deadlock!
    end

    def pr(msg)
      puts "rwlock_threadsafe: #{Thread.current.object_id}@#{Time.now.to_f}: #{msg}"
    end
  end
end
