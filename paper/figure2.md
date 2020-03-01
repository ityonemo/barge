# Figure 2

**NB**:  This has been changed selectively in places from the original to 
reflect renaming choices and typing in the Elixir implementation of the raft 
protocol.

## State

### Persistent State on all servers:

(updated on stable storage before responding to RPCs)
- `:term` - (`non_neg_integer`) latest term server has seen (initialized to 0 
  on first boot, increases monotonically)
- `:voted_for` - (`pid`) that received vote in current term (or `nil` if none)
- `log` log entries, each entry contains command for state machine, and term 
  when entry was received by leader (first index is 1)

### Volatile state on all servers:

- `:commit_index` (`non_neg_integer`) - index of highest log entry known to be 
  committed (initialized to 0, increases monotonically)
- `:last_applied` (`non_neg_integer`) - index of highest log entry applied to 
  state machine (initialized to 0, increases monotonically)

### Volatile state on leaders:

(reinitialized after election)
- `:next_index` (`%{optional(pid) => non_neg_integer}`) - for each server, 
  index of the next log entry to send to that server (initialized to 
  `log.last_index() + 1`)
- `:match_index` (`%{optional(pid) => non_neg_integer}`) - for each server, 
  index of the  highest log entry known to be replicated on the server 
  (initialized to 0, increases monotonically)

## AppendEntries RPC

invoked by leader to replicate log entries (§5.3); also used as a heartbeat (§5.2)

### Arguments

- `:term` (`non_neg_integer`) - leader's `:term`
- `:id` (`non_neg_integer`) - return address, saved by followers to redirect 
  clients
- `:prev_log_index` (`non_neg_integer`) - index of log entry immediately 
  preceding new ones
- `:prev_log_term` (`non_neg_integer`) - term of the `:prev_log_index` entry
- `:entries` (`list(entry)`) - log entries to store (empty for heartbeat; may 
  send more than one for efficiency)
- `:leader_commit` (`non_neg_integer`) - leader's commit index

### Results

- `:term` (`non_neg_integer`) - current term, for leader to update itself.
- `:success` (`boolean`) - `true` if follower contained entry matching 
  `:prev_log_index` and `:prev_log_term`

### Receiver Implementation:

1. Reply `false` if RPC term < server term. (§5.1)
2. Reply `false` if log doesn't contain an entry at `:prev_log_index` whose
  term matches `:prev_log_term` (§5.3)
3. If an existing entry conflicts with a new one (same index but different
  terms), delete the existing entry and all that follow it (§5.3)
4. Append any new entries not already in the log
5. If leader commit > commit index set commit index to the minimum of
  leader commit and the last new entry.

## RequestVote RPC

invoked by candidates to gather votes (§5.2)

### Arguments

- `:term` (`non_neg_integer`) - candidate's term
- `:id` (`pid`) - candidate requesting vote
- `:last_log_index` (`non_neg_integer`) - index of candidate's last log entry 
  (§5.4)
- `:last_log_term` (`non_neg_integer`) - term of candidate's last log entry 
  (§5.4)

### Results

- `:term` (`non_neg_integer`) - current term, for candidate to update itself.
- `:success` (`boolean`) - `true` if candidate received vote

### Receiver implementation

1. Reply `false` if RPC term < server term (§5.1)
2. If server's `:voted_for` is `nil` or `:id`, and candidate's log is at least
  as up-to-date as receiver's log, grant the vote (§5.2, §5.4)

## Rules for Servers

### All Servers:

- If `:commit_index` > `:last_applied`, apply `log[last_applied]` to the state
  machine (§5.3)
- If RPC request or response contains term greater than the server's term,
  convert to follower (§5.1)

### Followers (§5.2):

- respond to RPCs from candidates and leaders
- if election timeout elapses without receiving AppendEntries RPC from current
  leader or granting vote to candidate, `:timeout` to candidate.

### Candidates (§5.2):

- On conversion to candidate, start election:
  - Increment `:term`
  - Vote for self.
  - Reset election timer.
  - Send RequestVote RPC to all other servers
- If votes received from a majority of servers: `:accede` to leader
- If AppendEntries RPC received from a new leader, `:concede` to follower.
- If election timeout elapses, start a new election.

### Leaders:

- Upon election: send initial empty AppendEntries RPCs (heartbeat) to each
  server, repeat during idle periods to prevent election timeouts (§5.2)
- If command received from client: append entry to local log, respond after
  entry applied to state machine (§5.3)
- If `log.last_index()` >= `:next_index` for a follower, send AppendEntries RPC
  with log entries starting at next index.
  - If successful: update `:next_index` and `:match_index` for the follower 
    (§5.3)
  - If AppendEntries RPC fails because of log inconsistency: decrement `:next_index`
    and retry (§5.3)
- If there exists an N such that N > `:commit_index`, a majority of `:match_index`
  >= N and `log[N].term == :term`: set `:commit_index == N` (§5.3, §5.4).