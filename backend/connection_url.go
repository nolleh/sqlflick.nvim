package main

import (
	"fmt"
	"net"
	"net/url"
	"strings"

	"github.com/go-sql-driver/mysql"
	"github.com/redis/go-redis/v9"
)

func mysqlConnectionString(config Config) (string, error) {
	if config.URL == "" {
		return fmt.Sprintf("%s:%s@tcp(%s:%d)/%s", config.User, config.Password, config.Host, config.Port, config.DBName), nil
	}
	u, err := url.Parse(config.URL)
	if err != nil || u.Scheme != "mysql" || u.Fragment != "" {
		return "", fmt.Errorf("invalid MySQL connection URL")
	}
	params, err := url.ParseQuery(u.RawQuery)
	if err != nil {
		return "", fmt.Errorf("invalid MySQL connection options")
	}
	cfg := mysql.NewConfig()
	if u.User != nil {
		cfg.User = u.User.Username()
		cfg.Passwd, _ = u.User.Password()
	}
	if params.Has("user") {
		cfg.User = params.Get("user")
		params.Del("user")
	}
	if params.Has("password") {
		cfg.Passwd = params.Get("password")
		params.Del("password")
	}
	host, port := u.Hostname(), u.Port()
	if host == "" {
		host = "localhost"
	}
	if port == "" {
		port = "3306"
	}
	cfg.Net, cfg.Addr = "tcp", net.JoinHostPort(host, port)
	cfg.DBName = strings.TrimPrefix(u.Path, "/")
	dsn := cfg.FormatDSN()
	if len(params) > 0 {
		separator := "?"
		if strings.Contains(dsn, "?") {
			separator = "&"
		}
		dsn += separator + params.Encode()
	}
	parsed, err := mysql.ParseDSN(dsn)
	if err != nil {
		return "", fmt.Errorf("invalid MySQL connection options")
	}
	return parsed.FormatDSN(), nil
}

func sqliteConnectionString(config Config) (string, error) {
	if config.URL == "" {
		return config.DBName, nil
	}
	if !strings.HasPrefix(config.URL, "file:") {
		return "", fmt.Errorf("invalid SQLite connection URL")
	}
	return config.URL, nil
}

func oracleConnectionString(config Config) (string, error) {
	if config.URL == "" {
		return fmt.Sprintf("oracle://%s:%s@%s:%d/%s", config.User, config.Password, config.Host, config.Port, config.DBName), nil
	}
	u, err := url.Parse(config.URL)
	if err != nil || u.Scheme != "oracle" || u.Hostname() == "" || u.Fragment != "" {
		return "", fmt.Errorf("invalid Oracle connection URL")
	}
	return config.URL, nil
}

func redisConnectionOptions(config Config) (*redis.Options, error) {
	opts := &redis.Options{
		Addr:     fmt.Sprintf("%s:%d", config.Host, config.Port),
		Password: config.Password,
	}
	if config.URL != "" {
		u, err := url.Parse(config.URL)
		if err != nil || (u.Scheme != "redis" && u.Scheme != "rediss") || u.Fragment != "" {
			return nil, fmt.Errorf("invalid Redis connection URL or options")
		}
		host, port := u.Hostname(), u.Port()
		if host == "" {
			host = "localhost"
		}
		if port == "" {
			port = "6379"
		}
		u.Host = net.JoinHostPort(host, port)
		opts, err = redis.ParseURL(u.String())
		if err != nil {
			return nil, fmt.Errorf("invalid Redis connection URL or options")
		}
	}
	// Keep SQLFlick's shared pool bounds and cancellation policy for URL callers.
	opts.PoolSize = maxPoolConnections
	opts.MaxActiveConns = maxPoolConnections
	opts.MaxIdleConns = 2
	opts.MinIdleConns = 0
	opts.ConnMaxIdleTime = poolIdleTimeout
	opts.ContextTimeoutEnabled = true
	opts.MaxRetries = -1
	return opts, nil
}
