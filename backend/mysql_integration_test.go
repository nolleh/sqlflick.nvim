package main

import (
	"context"
	"os"
	"testing"
	"time"
)

// Opt in against the MySQL service in tests/docker with SQLFLICK_E2E_MYSQL=1.
// Both paths must authenticate with the same account without server changes.
func TestMySQLURLAndFieldAuthentication(t *testing.T) {
	if os.Getenv("SQLFLICK_E2E_MYSQL") != "1" {
		t.Skip("set SQLFLICK_E2E_MYSQL=1 to test the local MySQL container")
	}
	configs := map[string]Config{
		"fields":        {Host: "127.0.0.1", Port: 3306, User: "test_user", Password: "test_password", DBName: "test_db"},
		"url":           {URL: "mysql://test_user:test_password@127.0.0.1:3306/test_db"},
		"localhost_url": {URL: "mysql://test_user:test_password@localhost:3306/test_db"},
	}
	for name, config := range configs {
		t.Run(name, func(t *testing.T) {
			driver := &MySQLDriver{}
			if err := driver.Connect(config); err != nil {
				t.Fatal(err)
			}
			defer driver.Close()
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			result, err := driver.QueryContext(ctx, "SELECT 1 AS connected")
			if err != nil {
				t.Fatal(err)
			}
			if len(result.Rows) != 1 {
				t.Fatal("authentication did not produce the expected result")
			}
		})
	}
}
