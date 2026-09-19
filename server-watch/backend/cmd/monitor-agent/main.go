package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"server-watch/backend/internal/api"
	"server-watch/backend/internal/collect"
	"server-watch/backend/internal/config"
	"server-watch/backend/internal/hub"
	"server-watch/backend/internal/webdist"
)

func main() {
	cfgPath := flag.String("config", "", "config file path")
	flag.Parse()

	cfg, err := config.Load(*cfgPath)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	log.Printf("config: %s", config.Path())

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	mgr := collect.NewManager(cfg)
	mgr.Run(ctx)

	h := hub.New()

	srv := api.NewServer(mgr, h, webdist.FS())
	go srv.Broadcaster(ctx)

	if err := srv.Run(ctx, cfg.Listen); err != nil {
		log.Fatalf("server: %v", err)
	}
}
