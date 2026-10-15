package main

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

func fakePoolFactory(created, closed *int) func() (interface{}, func() error, error) {
	return func() (interface{}, func() error, error) {
		*created = *created + 1
		value := new(int)
		return value, func() error { *closed = *closed + 1; return nil }, nil
	}
}

func TestPoolCacheReusesOnePoolAcrossRequests(t *testing.T) {
	cache := newPoolCache(2, time.Minute)
	created, closed := 0, 0
	factory := fakePoolFactory(&created, &closed)
	first, releaseFirst, err := cache.acquire("same-config", factory)
	if err != nil {
		t.Fatal(err)
	}
	second, releaseSecond, err := cache.acquire("same-config", factory)
	if err != nil {
		t.Fatal(err)
	}
	if first != second || created != 1 {
		t.Fatal("same configuration created multiple pools")
	}
	_ = releaseFirst()
	_ = releaseFirst() // Releasing a lease twice cannot make an active pool evictable.
	if cache.entries["same-config"].users != 1 {
		t.Fatal("lease released more than once")
	}
	_ = releaseSecond()
	if closed != 0 {
		t.Fatal("request completion closed the shared pool")
	}
	third, releaseThird, err := cache.acquire("same-config", factory)
	if err != nil {
		t.Fatal(err)
	}
	defer releaseThird()
	if third != first || created != 1 {
		t.Fatal("completed request did not leave a reusable pool")
	}
}

func TestPoolCacheCapsConfigurationsWithoutClosingActivePools(t *testing.T) {
	cache := newPoolCache(1, time.Minute)
	created, closed := 0, 0
	factory := fakePoolFactory(&created, &closed)
	_, release, err := cache.acquire("active", factory)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := cache.acquire("other", factory); err == nil {
		t.Fatal("cache exceeded its limit")
	}
	if created != 1 || closed != 0 {
		t.Fatal("active pool was evicted or an excess pool was created")
	}
	_ = release()
	_, releaseOther, err := cache.acquire("other", factory)
	if err != nil {
		t.Fatal(err)
	}
	defer releaseOther()
	if created != 2 || closed != 1 || len(cache.entries) != 1 {
		t.Fatal("unused pool was not evicted within the cap")
	}
}

func TestPoolCacheExpiresOnlyUnusedPools(t *testing.T) {
	cache := newPoolCache(2, time.Minute)
	now := time.Now()
	cache.now = func() time.Time { return now }
	created, closed := 0, 0
	factory := fakePoolFactory(&created, &closed)
	_, releaseIdle, _ := cache.acquire("idle", factory)
	_ = releaseIdle()
	_, releaseActive, _ := cache.acquire("active", factory)
	now = now.Add(2 * time.Minute)
	_, releaseNew, err := cache.acquire("new", factory)
	if err != nil {
		t.Fatal(err)
	}
	defer releaseActive()
	defer releaseNew()
	if closed != 1 || cache.entries["idle"] != nil || cache.entries["active"] == nil {
		t.Fatal("expiry must close unused pools and retain active pools")
	}
}

func TestPoolCacheConcurrentAcquisitionCreatesOnePool(t *testing.T) {
	cache := newPoolCache(2, time.Minute)
	created, closed := 0, 0
	factory := fakePoolFactory(&created, &closed)
	var group sync.WaitGroup
	for i := 0; i < 20; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			_, release, err := cache.acquire("same", factory)
			if err != nil {
				t.Error(err)
				return
			}
			_ = release()
		}()
	}
	group.Wait()
	if created != 1 || closed != 0 {
		t.Fatal("concurrent requests created or closed extra pools")
	}
}

func TestPoolKeySeparatesDatabaseAndCredentials(t *testing.T) {
	key := poolKey("postgres", "host=db dbname=first password=one")
	for _, other := range []string{
		poolKey("postgres", "host=db dbname=second password=one"),
		poolKey("postgres", "host=db dbname=first password=two"),
		poolKey("mysql", "host=db dbname=first password=one"),
	} {
		if key == other {
			t.Fatal("different connection identities shared a pool")
		}
	}
}

func TestSQLiteDriversLeaseTheSameBoundedFilePool(t *testing.T) {
	config := Config{DBName: t.TempDir() + "/pool.db"}
	first, second := &SQLiteDriver{}, &SQLiteDriver{}
	if err := first.Connect(config); err != nil {
		t.Fatal(err)
	}
	defer first.Close()
	if err := second.Connect(config); err != nil {
		t.Fatal(err)
	}
	defer second.Close()
	if first.db != second.db {
		t.Fatal("driver wrappers created separate SQL pools")
	}
	if first.db.Stats().MaxOpenConnections != 1 {
		t.Fatal("SQLite pool was not bounded")
	}
	_ = first.Close()
	if err := second.db.Ping(); err != nil {
		t.Fatalf("one request closed another request's pool: %v", err)
	}
}

func TestSQLiteCancellationLeavesSharedPoolUsable(t *testing.T) {
	driver := &SQLiteDriver{}
	if err := driver.Connect(Config{DBName: t.TempDir() + "/cancel.db"}); err != nil {
		t.Fatal(err)
	}
	defer driver.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 25 * time.Millisecond)
	defer cancel()
	_, err := driver.QueryContext(ctx, `
		WITH RECURSIVE numbers(n) AS (
			SELECT 1 UNION ALL SELECT n + 1 FROM numbers WHERE n < 100000000
		) SELECT SUM(n) FROM numbers`)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("expected database work to stop at its deadline, got %v", err)
	}
	result, err := driver.QueryContext(context.Background(), "SELECT 1")
	if err != nil || len(result.Rows) != 1 {
		t.Fatalf("shared pool unusable after cancellation: %v", err)
	}
}
