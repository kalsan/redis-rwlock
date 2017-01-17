# redis-rwlock
Ruby implementation of a reader-writer lock using Redis. You can use it to synchronize different processes, even if they run on different computers.

## Disclaimer
I wrote this to experiment with locks on Redis. These classes might be a good inspiration if you're interested in topics like these, but I wouldn't recommend taking them into a production environment, for the following reasons:
- Performance: Synchronizing access over an external server (even Redis) has a considerable overhead and will slow down your program
- Testing: These classes were only superficially tested.

## Classes
### RWLock
This class provides a reader-writer lock as in example "Third problem" in:
https://en.wikipedia.org/wiki/Readers%E2%80%93writers_problem

It will throw an exception when attempting to release a lock that the instance
does not have. Locks are reentrant but not thread-safe: A process may re-
acquire its reader or writer lock, but do not attempt to acquire a read
lock while holding a write lock or vv.

Again, this class is NOT thread-safe. Create one instance per thread.
This way, threads will sync using the redis cache, avoiding local and
remote starvation. Use RWLockThreadsafe for a thread safe wrapper.

### RWLockThreadsafe
Wrapper around RWLock that should make it suitable for a multi-threaded environment. With this wrapper, you can use RWLock to synchronize threads in the same process (in a production environment, that wouldn't make sense due to performance reasons).

## Possible enhancements
- Up- / Downgrading a lock from r to w and vv.
- When dying, clear database for forgotten locks?
