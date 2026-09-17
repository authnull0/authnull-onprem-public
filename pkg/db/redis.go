package db

import (
	"context"
	"fmt"
	"os"

	"github.com/redis/go-redis/v9"
)

var client *redis.Client

// InitRedisInstance initializes the shared Redis client from env config.
// Call once at startup (from main) before serving requests.
func InitRedisInstance() {
	ctx := context.Background()
	host := os.Getenv("REDIS_HOST")
	key := os.Getenv("REDIS_PASSWORD")
	client = redis.NewClient(&redis.Options{
		Addr:     host,
		Password: key,
		DB:       0,
	})
	pong, err := client.Ping(ctx).Result()
	fmt.Println(pong, err)
}

// GetRedisInstance returns the shared Redis client.
func GetRedisInstance() *redis.Client {
	return client
}
