package main

import (
	"crypto/sha256"
	"database/sql"
	"fmt"
	"strings"
	"sync"
	"time"
)

const maxCachedPools = 16
const maxPoolConnections = 5
const poolIdleTimeout = 5 * time.Minute

type cachedPool struct {
	value    interface{}
	close    func() error
	users    int
	lastUsed time.Time
}

// A request leases a shared pool, not a new set of physical connections.
// Only unused pools may be evicted; the cache never exceeds its configured cap.
type poolCache struct {
	mu      sync.Mutex
	entries map[string]*cachedPool
	limit   int
	idle    time.Duration
	now     func() time.Time
}

func newPoolCache(limit int, idle time.Duration) *poolCache {
	return &poolCache{entries: make(map[string]*cachedPool), limit: limit, idle: idle, now: time.Now}
}

var connectionPools = newPoolCache(maxCachedPools, poolIdleTimeout)

func (c *poolCache) acquire(key string, create func() (interface{}, func() error, error)) (interface{}, func() error, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.now()
	for k, entry := range c.entries {
		if entry.users == 0 && now.Sub(entry.lastUsed) >= c.idle {
			_ = entry.close()
			delete(c.entries, k)
		}
	}
	entry := c.entries[key]
	if entry == nil {
		if len(c.entries) >= c.limit {
			oldestKey := ""
			var oldest *cachedPool
			for k, candidate := range c.entries {
				if candidate.users == 0 && (oldest == nil || candidate.lastUsed.Before(oldest.lastUsed)) {
					oldestKey, oldest = k, candidate
				}
			}
			if oldest == nil {
				return nil, nil, fmt.Errorf("connection pool cache is busy (maximum %d configurations)", c.limit)
			}
			_ = oldest.close()
			delete(c.entries, oldestKey)
		}
		value, closePool, err := create()
		if err != nil {
			return nil, nil, err
		}
		entry = &cachedPool{value: value, close: closePool, lastUsed: now}
		c.entries[key] = entry
	}
	entry.users++
	var once sync.Once
	release := func() error {
		once.Do(func() {
			c.mu.Lock()
			defer c.mu.Unlock()
			entry.users--
			entry.lastUsed = c.now()
		})
		return nil
	}
	return entry.value, release, nil
}

// Credentials participate in the identity, but are not retained as map keys.
func poolKey(driver, dsn string) string {
	return fmt.Sprintf("%s:%x", driver, sha256.Sum256([]byte(dsn)))
}

func acquireSQLPool(driver, dsn string) (*sql.DB, func() error, error) {
	create := func() (interface{}, func() error, error) {
		db, err := sql.Open(driver, dsn)
		if err != nil {
			return nil, nil, err
		}
		maxOpen := maxPoolConnections
		if driver == "sqlite3" {
			maxOpen = 1
		}
		db.SetMaxOpenConns(maxOpen)
		db.SetMaxIdleConns(2)
		db.SetConnMaxIdleTime(poolIdleTimeout)
		if driver != "sqlite3" || !strings.Contains(dsn, "mode=memory") {
			db.SetConnMaxLifetime(30 * time.Minute)
		}
		return db, db.Close, nil
	}
	// Private SQLite memory databases are connection-local and must not leak
	// state between independent requests/tests.
	if driver == "sqlite3" && (dsn == ":memory:" || dsn == "") {
		value, closePool, err := create()
		if err != nil {
			return nil, nil, err
		}
		return value.(*sql.DB), closePool, nil
	}
	value, release, err := connectionPools.acquire(poolKey(driver, dsn), create)
	if err != nil {
		return nil, nil, err
	}
	return value.(*sql.DB), release, nil
}
